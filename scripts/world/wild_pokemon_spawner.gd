class_name WildPokemonSpawner # Creates temporary Pokémon inside terrain matching their Generation IV primary type.
extends Node3D # Owns active roaming Pokémon without owning terrain-generation policy.

const WILD_POKEMON_SCENE: PackedScene = preload("res://scenes/characters/wild_pokemon.tscn") # Keeps the reusable roaming character scene ready for inexpensive instantiation.
const RADIAL_SPECIES_SEARCH_ATTEMPTS: int = 64 # Bounds type-matching species selection in the infinite radial world.
const RADIAL_SPAWN_RADIUS: float = 24.0 # Keeps infinite-world wildlife close enough to the player to remain inside streamed terrain.
const RADIAL_INITIAL_WANDER_RADIUS: float = 12.0 # Gives newly spawned local wildlife a short first movement within its current type world.

var random: RandomNumberGenerator = RandomNumberGenerator.new() # Provides independent spawn timing, species selection, form selection, and behaviour seeds.
var species_directories: PackedStringArray = PackedStringArray() # Stores installed National Dex sprite folders discovered lazily by the sprite library.
var world_builder: HgssWorldBuilder # References the active world's habitat-aware terrain service.
var player_reference: Node3D # References the player when radial streaming requires local wildlife population.
var max_active_pokemon: int = 34 # Keeps the visible world populated without creating hundreds of physics bodies.
var min_spawn_delay: float = 1.0 # Fills the visible region at a steady but non-bursty rate.
var max_spawn_delay: float = 2.4 # Adds timing variation while maintaining useful population density.
var spawn_countdown: float = 0.0 # Tracks time remaining until the next eligible spawn attempt.

func _ready() -> void: # Resolves world dependencies, discovers installed species folders, and schedules the first spawn.
    random.randomize() # Separates runtime wildlife choices between play sessions.
    world_builder = get_tree().get_first_node_in_group(&"world_builder") as HgssWorldBuilder # Resolves the active finite or radial world through the established semantic group.
    player_reference = get_tree().get_first_node_in_group(&"player") as Node3D # Resolves the player for local radial-world population decisions.
    species_directories = PokemonSpriteLibrary.discover_species() # Enumerates only species folders while deferring form and texture validation until use.
    if world_builder == null: # Detects malformed scene composition before spawning begins.
        push_error("WildPokemonSpawner requires an HgssWorldBuilder in the world_builder group.") # Reports the missing world dependency directly.
        set_process(false) # Prevents repeated work from an unusable spawner.
        return # Stops initialization without dereferencing the missing world.
    if species_directories.is_empty(): # Handles projects where the optional HGSS sprite folder has not been installed.
        push_warning("No HGSS Pokémon species folders were found under res://assets/pokemon/hgss_overworld.") # Reports the expected asset location without treating it as a fatal world error.
        return # Leaves the world playable without temporary roaming Pokémon.
    _reset_spawn_countdown() # Schedules the first bounded wildlife spawn attempt.

func _process(delta: float) -> void: # Advances the lightweight spawn timer outside the fixed-rate physics loop.
    if world_builder == null or species_directories.is_empty(): # Rejects processing when required world or sprite data is unavailable.
        return # Avoids needless per-frame work from an inactive spawner.
    if get_child_count() >= max_active_pokemon: # Enforces the established active wildlife population cap.
        return # Waits until an existing temporary Pokémon leaves before spawning another.
    spawn_countdown -= delta # Advances the spawn timer by rendered frame time.
    if spawn_countdown > 0.0: # Detects whether the next spawn attempt is still scheduled in the future.
        return # Avoids species and terrain work until the timer expires.
    _spawn_random_pokemon() # Creates one habitat-correct temporary Pokémon when possible.
    _reset_spawn_countdown() # Schedules the next bounded spawn attempt independently of success.

func _spawn_random_pokemon() -> void: # Routes spawning through finite-world or local infinite-world policy without duplicating character setup.
    if world_builder is RadialWorldBuilder: # Detects the streamed infinite radial topology introduced for open-ended exploration.
        _spawn_radial_pokemon(world_builder as RadialWorldBuilder) # Keeps wildlife near the player and inside the currently occupied type world.
        return # Prevents the finite-world boundary-spawn policy from creating distant offscreen bodies.
    _spawn_finite_world_pokemon() # Preserves the established species-first finite-world spawning behavior for other world implementations.

func _spawn_radial_pokemon(radial_world: RadialWorldBuilder) -> void: # Spawns one species matching the player's current radial biome inside loaded nearby terrain.
    if player_reference == null or not is_instance_valid(player_reference): # Recovers if player resolution happened before scene siblings were ready or the player was replaced.
        player_reference = get_tree().get_first_node_in_group(&"player") as Node3D # Re-resolves the semantic player dependency only when necessary.
    if player_reference == null: # Handles a malformed radial gameplay scene without producing offscreen fallback wildlife.
        return # Defers spawning until a valid player exists.
    var biome_kind: int = radial_world.get_biome_kind_at_world_position(player_reference.global_position) # Reads the player's current neutral or infinite type region directly from radial topology.
    var species_directory: String = _choose_species_for_biome(biome_kind) # Chooses an installed species whose Generation IV primary type matches the local region.
    if species_directory.is_empty(): # Handles a type whose installed sprite subset contains no eligible species.
        return # Skips this spawn attempt instead of using the wrong habitat.
    var sprite_directory: String = PokemonSpriteLibrary.choose_random_form_directory(species_directory, random) # Lazily validates and chooses one complete form for the selected species.
    if sprite_directory.is_empty(): # Rejects species whose installed form folders are incomplete or unavailable to ResourceLoader.
        return # Leaves the failed asset uncached and tries another spawn on a later timer.
    var entry_position: Vector3 = radial_world.get_random_walkable_world_position_near_in_biome(player_reference.global_position, RADIAL_SPAWN_RADIUS, biome_kind, random) # Chooses practical nearby terrain inside the player's current biome.
    var initial_target: Vector3 = radial_world.get_random_walkable_world_position_near_in_biome(entry_position, RADIAL_INITIAL_WANDER_RADIUS, biome_kind, random) # Gives the new visitor a short local movement target in the same type region.
    _create_pokemon(sprite_directory, entry_position, initial_target, biome_kind) # Instantiates the character using the common setup path.

func _spawn_finite_world_pokemon() -> void: # Preserves the original species-first spawning policy for non-radial world implementations.
    var species_index: int = random.randi_range(0, species_directories.size() - 1) # Selects one installed species uniformly.
    var species_directory: String = species_directories[species_index] # Reads the chosen species folder.
    var biome_kind: int = PokemonGen4TypeLibrary.get_biome_kind_for_species_directory(species_directory) # Maps its Generation IV primary type to the world biome index.
    if biome_kind < 0: # Rejects species outside the supported Generation IV type mapping.
        return # Skips this attempt without constructing an invalid visitor.
    var sprite_directory: String = PokemonSpriteLibrary.choose_random_form_directory(species_directory, random) # Lazily chooses one complete directional sprite form.
    if sprite_directory.is_empty(): # Handles incomplete or unavailable sprite resources.
        return # Skips this attempt without creating a partially configured character.
    var entry_pair: Array[Vector3] = world_builder.get_random_biome_entry_pair(biome_kind, random) # Reads the finite world's habitat boundary entry and inward target.
    if entry_pair.size() < 2: # Rejects malformed world entry data before indexing it.
        return # Leaves spawning to a later attempt.
    _create_pokemon(sprite_directory, entry_pair[0], entry_pair[1], biome_kind) # Instantiates the visitor through the shared character setup path.

func _choose_species_for_biome(biome_kind: int) -> String: # Finds one installed species matching a requested Generation IV primary-type biome with bounded work.
    if species_directories.is_empty(): # Guards random indexing when the optional sprite library is absent.
        return "" # Reports that no species can be selected.
    var start_index: int = random.randi_range(0, species_directories.size() - 1) # Randomizes the first candidate while keeping the search bounded and allocation-free.
    var maximum_attempts: int = mini(RADIAL_SPECIES_SEARCH_ATTEMPTS, species_directories.size()) # Never checks more candidates than either the configured budget or installed species count.
    for offset: int in range(maximum_attempts): # Walks a bounded circular slice of the installed species catalogue.
        var index: int = (start_index + offset) % species_directories.size() # Wraps through the species array without creating a shuffled copy.
        var species_directory: String = species_directories[index] # Reads one candidate species folder.
        if PokemonGen4TypeLibrary.get_biome_kind_for_species_directory(species_directory) == biome_kind: # Accepts only species whose primary type matches the player's current radial region.
            return species_directory # Returns immediately on the first valid local species.
    return "" # Reports that no matching installed species was found inside the bounded search budget.

func _create_pokemon(sprite_directory: String, entry_position: Vector3, initial_target: Vector3, biome_kind: int) -> void: # Instantiates and configures one temporary Pokémon from already validated spawn data.
    var pokemon: WildPokemon = WILD_POKEMON_SCENE.instantiate() as WildPokemon # Creates the reusable overworld Pokémon scene.
    if pokemon == null: # Guards an unexpected scene-type regression before parenting.
        return # Avoids adding an invalid instance to the active population.
    add_child(pokemon) # Parents the visitor so the spawner's child count remains the active population source of truth.
    pokemon.global_position = entry_position # Places the visitor on its chosen practical terrain before movement setup.
    pokemon.setup(sprite_directory, world_builder, initial_target, biome_kind, random.randi()) # Supplies sprite, terrain policy, first destination, habitat, and independent behavior seed.

func _reset_spawn_countdown() -> void: # Schedules another spawn attempt within the configured interval range.
    spawn_countdown = random.randf_range(min_spawn_delay, max_spawn_delay) # Chooses independent timing variation between the established spawn-delay limits.

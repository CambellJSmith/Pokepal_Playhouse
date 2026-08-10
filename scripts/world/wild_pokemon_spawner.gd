class_name WildPokemonSpawner # Periodically creates temporary Pokémon that enter the generated world, wander, and leave.
extends Node3D # Owns active roaming Pokémon without owning terrain-generation policy.

const WILD_POKEMON_SCENE: PackedScene = preload("res://scenes/characters/wild_pokemon.tscn") # Keeps the reusable roaming character scene ready for inexpensive instantiation.

var random: RandomNumberGenerator = RandomNumberGenerator.new() # Provides independent spawn timing, species selection, entry selection, and per-instance seeds.
var species_directories: PackedStringArray = PackedStringArray() # Stores all valid Pokédex folders discovered beneath the configured HGSS asset root.
var world_builder: HgssWorldBuilder # References the generated world's walkability and route-gateway service.
var max_active_pokemon: int = 18 # Allows the substantially larger map to feel populated without creating hundreds of physics bodies.
var min_spawn_delay: float = 1.6 # Defines the shortest delay between successful visitor arrivals.
var max_spawn_delay: float = 3.8 # Defines the longest delay between visitor arrivals.
var spawn_countdown: float = 0.0 # Tracks time remaining until the next eligible spawn attempt.

func _ready() -> void: # Resolves the generated world, discovers Pokémon assets, and schedules the first visitor.
    random.randomize() # Seeds this spawner from the engine random source for varied sessions.
    world_builder = get_tree().get_first_node_in_group(&"world_builder") as HgssWorldBuilder # Resolves terrain policy semantically instead of depending on a scene path.
    species_directories = PokemonSpriteLibrary.discover_species() # Scans downloaded numbered folders and retains only complete usable species.
    if world_builder == null: # Detects a scene missing the required generated-world component.
        push_error("WildPokemonSpawner requires an HgssWorldBuilder in the world_builder group.") # Reports the structural problem instead of spawning into undefined space.
        set_process(false) # Disables the lightweight timer because safe positions cannot be generated.
        return # Stops startup configuration.
    if species_directories.is_empty(): # Detects a project without complete Pokémon overworld assets.
        push_warning("No complete HGSS Pokémon sprite folders were found under res://assets/pokemon/hgss_overworld.") # Explains where the expected assets belong.
    _reset_spawn_countdown() # Schedules the first temporary visitor.

func _process(delta: float) -> void: # Advances the lightweight spawn timer outside the fixed-rate physics loop.
    if world_builder == null or species_directories.is_empty(): # Avoids spawn work while either required data source is unavailable.
        return # Leaves the spawner dormant until the scene is rebuilt with valid dependencies.
    if get_child_count() >= max_active_pokemon: # Keeps the temporary population below the configured physics and readability cap.
        return # Waits for an existing Pokémon to leave before counting down another arrival.
    spawn_countdown -= delta # Advances the next-spawn timer while capacity is available.
    if spawn_countdown > 0.0: # Checks whether the randomized interval has elapsed yet.
        return # Leaves the current population unchanged until another arrival is due.
    _spawn_random_pokemon() # Creates one visitor using a uniformly selected species and generated-world entry gate.
    _reset_spawn_countdown() # Schedules the following visitor independently.

func _spawn_random_pokemon() -> void: # Instantiates and configures one random temporary overworld Pokémon.
    var sprite_directory: String = PokemonSpriteLibrary.choose_random_sprite_directory(species_directories, random) # Selects a species uniformly and then one available form for that species.
    if sprite_directory.is_empty(): # Guards assets removed after the initial discovery scan.
        return # Skips this attempt rather than creating an incomplete character.
    var entry_pair: Array[Vector3] = world_builder.get_random_entry_pair(random) # Requests one route-gate pair from the generated world.
    if entry_pair.size() < 2: # Guards an unexpectedly incomplete generated-world response.
        return # Skips this spawn because it cannot enter safely.
    var edge_position: Vector3 = entry_pair[1] # Uses the solid route-edge cell rather than the off-map helper point so gravity never starts over void.
    var initial_target: Vector3 = world_builder.get_random_walkable_world_position_near(edge_position, 8.0, random) # Chooses a nearby interior cell so the visitor visibly walks into the map.
    var pokemon: WildPokemon = WILD_POKEMON_SCENE.instantiate() as WildPokemon # Creates the reusable CharacterBody3D roaming Pokémon scene.
    add_child(pokemon) # Parents the visitor to the spawner so active population tracking stays allocation-free.
    pokemon.global_position = edge_position # Places the visitor on a valid route cell at the visible world boundary.
    pokemon.setup(sprite_directory, world_builder, initial_target, random.randi()) # Supplies assets, terrain policy, arrival target, and an independent behaviour seed.

func _reset_spawn_countdown() -> void: # Schedules another spawn attempt within the configured interval range.
    spawn_countdown = random.randf_range(min_spawn_delay, max_spawn_delay) # Chooses the next delay independently so arrivals do not become mechanical.

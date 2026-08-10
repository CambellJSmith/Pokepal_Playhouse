class_name WildPokemonSpawner # Periodically creates random temporary Pokémon that enter, linger, wander, and leave the visible area.
extends Node3D # Uses its world transform as the centre of a lightweight rectangular roaming region.

const WILD_POKEMON_SCENE: PackedScene = preload("res://scenes/characters/wild_pokemon.tscn") # Keeps the reusable roaming character scene ready for inexpensive instantiation.

var random: RandomNumberGenerator = RandomNumberGenerator.new() # Provides independent spawn timing, species selection, positions, and per-instance seeds.
var species_directories: PackedStringArray = PackedStringArray() # Stores all valid Pokédex folders discovered beneath the configured HGSS asset root.
var roaming_half_size: Vector2 = Vector2(8.0, 4.0) # Defines the X/Z half-extents of the lower-route area used by temporary wild Pokémon.
var max_active_pokemon: int = 7 # Limits simultaneous roaming characters to keep the small test scene readable and inexpensive.
var min_spawn_delay: float = 2.5 # Defines the shortest delay between successful wild Pokémon spawn attempts.
var max_spawn_delay: float = 5.5 # Defines the longest delay between successful wild Pokémon spawn attempts.
var spawn_countdown: float = 0.0 # Tracks time remaining until the next eligible spawn attempt.
var spawn_edge_margin: float = 0.75 # Places new Pokémon just outside the logical roaming boundary before they walk inward.
var interior_margin: float = 1.1 # Keeps arrival targets away from the edge so entering movement is clearly visible.

func _ready() -> void: # Discovers available Pokémon assets and schedules the first temporary visitor.
    random.randomize() # Seeds the spawner from the engine's random source for varied sessions.
    species_directories = PokemonSpriteLibrary.discover_species() # Scans the downloaded numbered folders and retains only complete usable species.
    if species_directories.is_empty(): # Detects the starter project before the full HGSS sprite folder has been copied in.
        push_warning("No complete HGSS Pokémon sprite folders were found under res://assets/pokemon/hgss_overworld.") # Explains exactly where the downloadable asset folders belong.
    _reset_spawn_countdown() # Schedules the first spawn using the configured random interval.

func _process(delta: float) -> void: # Advances the lightweight spawn timer outside the fixed-rate physics loop.
    if species_directories.is_empty(): # Avoids repeated discovery work when no usable Pokémon assets are installed.
        return # Leaves the spawner dormant until the scene is reloaded after assets have been imported.
    if get_child_count() >= max_active_pokemon: # Keeps the temporary population below the configured performance and readability cap.
        return # Waits for an existing Pokémon to leave and free itself before counting down another spawn.
    spawn_countdown -= delta # Advances the next-spawn timer while population capacity is available.
    if spawn_countdown > 0.0: # Checks whether the randomized interval has elapsed yet.
        return # Leaves the current population unchanged until the next spawn is due.
    _spawn_random_pokemon() # Creates one visitor using a uniformly selected species and one of its valid forms.
    _reset_spawn_countdown() # Schedules the following visitor independently of the one just created.

func _spawn_random_pokemon() -> void: # Instantiates and configures one random temporary overworld Pokémon.
    var sprite_directory: String = PokemonSpriteLibrary.choose_random_sprite_directory(species_directories, random) # Selects a species uniformly and then one available form for that species.
    if sprite_directory.is_empty(): # Guards assets that may have been removed after the initial discovery scan.
        return # Skips this spawn attempt rather than creating a visually incomplete character.
    var pokemon: WildPokemon = WILD_POKEMON_SCENE.instantiate() as WildPokemon # Creates the reusable CharacterBody3D roaming Pokémon scene.
    add_child(pokemon) # Parents the visitor to the spawner so active population tracking is allocation-free.
    var spawn_position: Vector3 = _choose_edge_position() # Chooses a random point just outside one of the four logical roaming edges.
    var initial_target: Vector3 = _choose_initial_interior_target(spawn_position) # Chooses a corresponding interior point that makes the entrance movement obvious.
    pokemon.global_position = spawn_position # Places the character at the selected edge before its first physics frame.
    pokemon.setup(sprite_directory, global_position, roaming_half_size, initial_target, random.randi()) # Supplies assets, bounds, arrival destination, and an independent behaviour seed.

func _choose_edge_position() -> Vector3: # Chooses one of four rectangular edges and a random position along that edge.
    var edge: int = random.randi_range(0, 3) # Selects west, east, north, or south with equal probability.
    var min_x: float = global_position.x - roaming_half_size.x # Calculates the western edge of the logical roaming region.
    var max_x: float = global_position.x + roaming_half_size.x # Calculates the eastern edge of the logical roaming region.
    var min_z: float = global_position.z - roaming_half_size.y # Calculates the northern edge of the logical roaming region.
    var max_z: float = global_position.z + roaming_half_size.y # Calculates the southern edge of the logical roaming region.
    if edge == 0: # Handles spawning from the west side of the roaming rectangle.
        return Vector3(min_x - spawn_edge_margin, global_position.y, random.randf_range(min_z, max_z)) # Places the visitor just beyond the west edge at a random Z position.
    if edge == 1: # Handles spawning from the east side of the roaming rectangle.
        return Vector3(max_x + spawn_edge_margin, global_position.y, random.randf_range(min_z, max_z)) # Places the visitor just beyond the east edge at a random Z position.
    if edge == 2: # Handles spawning from the north side of the roaming rectangle.
        return Vector3(random.randf_range(min_x, max_x), global_position.y, min_z - spawn_edge_margin) # Places the visitor just beyond the north edge at a random X position.
    return Vector3(random.randf_range(min_x, max_x), global_position.y, max_z + spawn_edge_margin) # Places the visitor just beyond the south edge at a random X position.

func _choose_initial_interior_target(spawn_position: Vector3) -> Vector3: # Chooses a point inside the area that naturally continues inward from the selected spawn edge.
    var min_x: float = global_position.x - roaming_half_size.x + interior_margin # Calculates the western interior limit used for safe arrival targets.
    var max_x: float = global_position.x + roaming_half_size.x - interior_margin # Calculates the eastern interior limit used for safe arrival targets.
    var min_z: float = global_position.z - roaming_half_size.y + interior_margin # Calculates the northern interior limit used for safe arrival targets.
    var max_z: float = global_position.z + roaming_half_size.y - interior_margin # Calculates the southern interior limit used for safe arrival targets.
    var target: Vector3 = Vector3(clampf(spawn_position.x, min_x, max_x), global_position.y, clampf(spawn_position.z, min_z, max_z)) # Projects the edge position into the safe interior rectangle.
    if spawn_position.x < global_position.x - roaming_half_size.x: # Detects a visitor entering from the west side.
        target.x = min_x # Pulls the arrival destination distinctly inside the west boundary.
    elif spawn_position.x > global_position.x + roaming_half_size.x: # Detects a visitor entering from the east side.
        target.x = max_x # Pulls the arrival destination distinctly inside the east boundary.
    elif spawn_position.z < global_position.z - roaming_half_size.y: # Detects a visitor entering from the north side.
        target.z = min_z # Pulls the arrival destination distinctly inside the north boundary.
    else: # Handles the remaining case where the visitor entered from the south side.
        target.z = max_z # Pulls the arrival destination distinctly inside the south boundary.
    return target # Returns the world-space point used for the new Pokémon's arrival phase.

func _reset_spawn_countdown() -> void: # Schedules another spawn attempt within the configured interval range.
    spawn_countdown = random.randf_range(min_spawn_delay, max_spawn_delay) # Chooses the next delay independently so arrivals do not feel mechanical.

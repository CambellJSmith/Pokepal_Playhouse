class_name WildPokemonSpawner # Creates temporary Pokémon inside the biome matching their Generation IV primary type.
extends Node3D # Owns active roaming Pokémon without owning terrain-generation policy.

const WILD_POKEMON_SCENE: PackedScene = preload("res://scenes/characters/wild_pokemon.tscn") # Keeps the reusable roaming character scene ready for inexpensive instantiation.

var random: RandomNumberGenerator = RandomNumberGenerator.new() # Provides independent spawn timing, species selection, form selection, and behaviour seeds.
var species_directories: PackedStringArray = PackedStringArray() # Stores all complete installed National Dex sprite folders.
var world_builder: HgssWorldBuilder # References the generated world's habitat-aware walkability and boundary service.
var max_active_pokemon: int = 34 # Keeps the much larger world populated without creating hundreds of physics bodies.
var min_spawn_delay: float = 1.0 # Fills the expanded region at a steady but non-bursty rate.
var max_spawn_delay: float = 2.4 # Adds timing variation while maintaining useful population density.
var spawn_countdown: float = 0.0 # Tracks time remaining until the next eligible spawn attempt.

func _ready() -> void: # Resolves the world, discovers installed sprites, and schedules the first type-aware spawn.
    random.randomize()
    world_builder = get_tree().get_first_node_in_group(&"world_builder") as HgssWorldBuilder
    species_directories = PokemonSpriteLibrary.discover_species()
    if world_builder == null:
        push_error("WildPokemonSpawner requires an HgssWorldBuilder in the world_builder group.")
        set_process(false)
        return
    if species_directories.is_empty():
        push_warning("No complete HGSS Pokémon sprite folders were found under res://assets/pokemon/hgss_overworld.")
        return
    _reset_spawn_countdown()

func _process(delta: float) -> void: # Advances the lightweight spawn timer outside the fixed-rate physics loop.
    if world_builder == null or species_directories.is_empty():
        return
    if get_child_count() >= max_active_pokemon:
        return
    spawn_countdown -= delta
    if spawn_countdown > 0.0:
        return
    _spawn_random_pokemon()
    _reset_spawn_countdown()

func _spawn_random_pokemon() -> void: # Selects a species first, then lets its Generation IV slot-one type dictate the habitat.
    var species_index: int = random.randi_range(0, species_directories.size() - 1)
    var species_directory: String = species_directories[species_index]
    var biome_kind: int = PokemonGen4TypeLibrary.get_biome_kind_for_species_directory(species_directory)
    if biome_kind < 0:
        return
    var sprite_directory: String = PokemonSpriteLibrary.choose_random_form_directory(species_directory, random)
    if sprite_directory.is_empty():
        return
    var entry_pair: Array[Vector3] = world_builder.get_random_biome_entry_pair(biome_kind, random)
    if entry_pair.size() < 2:
        return
    var entry_position: Vector3 = entry_pair[0]
    var initial_target: Vector3 = entry_pair[1]
    var pokemon: WildPokemon = WILD_POKEMON_SCENE.instantiate() as WildPokemon
    add_child(pokemon)
    pokemon.global_position = entry_position
    pokemon.setup(sprite_directory, world_builder, initial_target, biome_kind, random.randi())

func _reset_spawn_countdown() -> void: # Schedules another spawn attempt within the configured interval range.
    spawn_countdown = random.randf_range(min_spawn_delay, max_spawn_delay)

class_name WildPokemonSpawner # Creates temporary Pokémon inside the biome matching their Generation IV primary type.
extends Node3D # Owns active roaming Pokémon without owning terrain-generation policy.

const WILD_POKEMON_SCENE: PackedScene = preload("res://scenes/characters/wild_pokemon.tscn") # Keeps the reusable roaming character scene ready for inexpensive instantiation.

var random: RandomNumberGenerator = RandomNumberGenerator.new() # Provides independent spawn timing, habitat selection, species selection, and behaviour seeds.
var species_directories: PackedStringArray = PackedStringArray() # Stores all complete installed National Dex sprite folders.
var species_by_biome: Dictionary = {} # Indexes installed species by the region dictated by their Generation IV slot-one type.
var available_biomes: Array[int] = [] # Stores only type regions that currently have at least one installed primary-type species.
var world_builder: HgssWorldBuilder # References the generated world's habitat-aware walkability and boundary service.
var max_active_pokemon: int = 34 # Keeps the enlarged sixteen populated type habitats visibly active without hundreds of physics bodies.
var min_spawn_delay: float = 1.0 # Fills the much larger region at a steady but non-bursty rate.
var max_spawn_delay: float = 2.4 # Adds timing variation while maintaining useful population density.
var spawn_countdown: float = 0.0 # Tracks time remaining until the next eligible spawn attempt.

func _ready() -> void: # Resolves the world, discovers installed sprites, indexes them by primary type, and schedules the first spawn.
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
    _index_species_by_primary_type()
    if available_biomes.is_empty():
        push_warning("No installed Pokémon could be mapped to a Generation IV primary-type biome.")
        return
    _reset_spawn_countdown()

func _process(delta: float) -> void: # Advances the lightweight spawn timer outside the fixed-rate physics loop.
    if world_builder == null or available_biomes.is_empty():
        return
    if get_child_count() >= max_active_pokemon:
        return
    spawn_countdown -= delta
    if spawn_countdown > 0.0:
        return
    _spawn_random_pokemon()
    _reset_spawn_countdown()

func _index_species_by_primary_type() -> void: # Builds one installed-species pool per Gen IV biome once instead of reclassifying every spawn.
    species_by_biome.clear()
    available_biomes.clear()
    for species_directory: String in species_directories:
        var biome_kind: int = PokemonGen4TypeLibrary.get_biome_kind_for_species_directory(species_directory)
        if biome_kind < 0:
            continue
        var pool: PackedStringArray = species_by_biome.get(biome_kind, PackedStringArray())
        pool.append(species_directory)
        species_by_biome[biome_kind] = pool
    for biome_kind: int in range(HgssWorldBuilder.BiomeKind.size()):
        var pool: PackedStringArray = species_by_biome.get(biome_kind, PackedStringArray())
        if pool.is_empty():
            continue
        available_biomes.append(biome_kind)

func _spawn_random_pokemon() -> void: # Chooses a populated type biome first, then one species whose first type belongs there.
    var biome_index: int = random.randi_range(0, available_biomes.size() - 1)
    var biome_kind: int = available_biomes[biome_index]
    var species_pool: PackedStringArray = species_by_biome.get(biome_kind, PackedStringArray())
    if species_pool.is_empty():
        return
    var species_directory: String = species_pool[random.randi_range(0, species_pool.size() - 1)]
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

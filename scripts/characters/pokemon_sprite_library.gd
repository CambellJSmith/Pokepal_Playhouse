class_name PokemonSpriteLibrary # Provides runtime discovery and cached SpriteFrames creation for downloaded HGSS Pokémon sprites.
extends RefCounted # Keeps the asset utility lightweight because it does not need to exist in the scene tree.

const DEFAULT_ROOT: String = "res://assets/pokemon/hgss_overworld" # Defines the project folder containing numbered Pokémon sprite directories.
const DIRECTIONS: Array[StringName] = [&"down", &"up", &"left", &"right"] # Defines the directional animation names expected from the downloader.

static var _sprite_frames_cache: Dictionary[String, SpriteFrames] = {} # Reuses constructed animation resources so repeated species do not reload every texture.
static var _form_cache: Dictionary[String, PackedStringArray] = {} # Reuses valid form-directory lookups for each discovered species.

static func discover_species(root_path: String = DEFAULT_ROOT) -> PackedStringArray: # Finds Pokémon number folders containing at least one complete normal overworld sprite set.
    var species_directories: PackedStringArray = PackedStringArray() # Stores valid species folders as project resource paths.
    for entry: String in ResourceLoader.list_directory(root_path): # Reads project resources in a way that remains usable after export.
        if not entry.ends_with("/"):
            continue
        var directory_name: String = entry.trim_suffix("/")
        if not directory_name.is_valid_int():
            continue
        var species_directory: String = root_path.path_join(directory_name)
        if get_form_directories(species_directory).is_empty():
            continue
        species_directories.append(species_directory)
    species_directories.sort()
    return species_directories

static func get_form_directories(species_directory: String) -> PackedStringArray: # Finds complete normal sprite directories for every form of one species.
    if _form_cache.has(species_directory):
        return _form_cache[species_directory]
    var form_directories: PackedStringArray = PackedStringArray()
    for entry: String in ResourceLoader.list_directory(species_directory):
        if not entry.ends_with("/"):
            continue
        var form_name: String = entry.trim_suffix("/")
        var normal_directory: String = species_directory.path_join(form_name).path_join("normal")
        if not _has_complete_direction_set(normal_directory):
            continue
        form_directories.append(normal_directory)
    form_directories.sort()
    _form_cache[species_directory] = form_directories
    return form_directories

static func choose_random_sprite_directory(species_directories: PackedStringArray, random: RandomNumberGenerator) -> String: # Chooses a species uniformly, then one available form for that species.
    if species_directories.is_empty():
        return ""
    var species_index: int = random.randi_range(0, species_directories.size() - 1)
    return choose_random_form_directory(species_directories[species_index], random)

static func choose_random_form_directory(species_directory: String, random: RandomNumberGenerator) -> String: # Chooses one complete form while preserving an already-selected species/type pool.
    var form_directories: PackedStringArray = get_form_directories(species_directory)
    if form_directories.is_empty():
        return ""
    var form_index: int = random.randi_range(0, form_directories.size() - 1)
    return form_directories[form_index]

static func get_sprite_frames(sprite_directory: String) -> SpriteFrames: # Builds or retrieves the directional animation library for one Pokémon form.
    if _sprite_frames_cache.has(sprite_directory):
        return _sprite_frames_cache[sprite_directory]
    var sprite_frames: SpriteFrames = SpriteFrames.new()
    if sprite_frames.has_animation(&"default"):
        sprite_frames.remove_animation(&"default")
    for direction: StringName in DIRECTIONS:
        var idle_animation: StringName = StringName("idle_" + String(direction))
        var walk_animation: StringName = StringName("walk_" + String(direction))
        var frame_zero_path: String = sprite_directory.path_join(String(direction) + "_0.png")
        var frame_one_path: String = sprite_directory.path_join(String(direction) + "_1.png")
        var frame_zero: Texture2D = ResourceLoader.load(frame_zero_path, "Texture2D") as Texture2D
        var frame_one: Texture2D = ResourceLoader.load(frame_one_path, "Texture2D") as Texture2D
        if frame_zero == null or frame_one == null:
            push_error("Could not load complete HGSS sprite set from: " + sprite_directory)
            return SpriteFrames.new()
        sprite_frames.add_animation(idle_animation)
        sprite_frames.set_animation_loop(idle_animation, true)
        sprite_frames.set_animation_speed(idle_animation, 4.0)
        sprite_frames.add_frame(idle_animation, frame_zero)
        sprite_frames.add_animation(walk_animation)
        sprite_frames.set_animation_loop(walk_animation, true)
        sprite_frames.set_animation_speed(walk_animation, 6.0)
        sprite_frames.add_frame(walk_animation, frame_zero)
        sprite_frames.add_frame(walk_animation, frame_one)
    _sprite_frames_cache[sprite_directory] = sprite_frames
    return sprite_frames

static func _has_complete_direction_set(sprite_directory: String) -> bool: # Checks that a candidate folder has both frames for all four required directions.
    for direction: StringName in DIRECTIONS:
        var frame_zero_path: String = sprite_directory.path_join(String(direction) + "_0.png")
        var frame_one_path: String = sprite_directory.path_join(String(direction) + "_1.png")
        if not ResourceLoader.exists(frame_zero_path, "Texture2D"):
            return false
        if not ResourceLoader.exists(frame_one_path, "Texture2D"):
            return false
    return true

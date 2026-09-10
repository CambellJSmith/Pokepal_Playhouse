class_name PokemonSpriteLibrary # Provides lazy runtime discovery and cached SpriteFrames creation for installed HGSS Pokémon sprites.
extends RefCounted # Keeps the asset utility lightweight because it does not need to exist in the scene tree.

const DEFAULT_ROOT: String = "res://assets/pokemon/hgss_overworld" # Defines the project folder containing numbered Pokémon sprite directories.
const DIRECTIONS: Array[StringName] = [&"down", &"up", &"left", &"right"] # Defines the directional animation names expected from the downloader.

static var _sprite_frames_cache: Dictionary[String, SpriteFrames] = {} # Reuses constructed animation resources so repeated species do not reload every texture.
static var _form_cache: Dictionary[String, PackedStringArray] = {} # Reuses valid form-directory lookups after a species is actually selected.

static func discover_species(root_path: String = DEFAULT_ROOT) -> PackedStringArray: # Finds numbered Pokémon folders without eagerly opening and validating every sprite resource.
    var species_directories: PackedStringArray = PackedStringArray() # Stores discovered species folders as project resource paths.
    for entry: String in ResourceLoader.list_directory(root_path): # Enumerates only the top-level species directory once at startup.
        if not entry.ends_with("/"): # Rejects files because species are represented by directories.
            continue # Skips non-directory entries without touching their import metadata.
        var directory_name: String = entry.trim_suffix("/") # Removes the directory marker before numeric validation.
        if not directory_name.is_valid_int(): # Rejects helper folders and unrelated assets.
            continue # Keeps only National Dex style numbered directories.
        species_directories.append(root_path.path_join(directory_name)) # Defers expensive form and texture validation until this species is selected.
    species_directories.sort() # Keeps species ordering deterministic across operating systems.
    return species_directories # Returns the lightweight species catalogue used by the spawner.

static func get_form_directories(species_directory: String) -> PackedStringArray: # Finds complete normal sprite directories only when one species is selected for use.
    if _form_cache.has(species_directory): # Reuses a prior validation result for this species.
        return _form_cache[species_directory] # Avoids repeating directory and resource checks for already-seen species.
    var form_directories: PackedStringArray = PackedStringArray() # Stores only complete normal animation folders for this species.
    for entry: String in ResourceLoader.list_directory(species_directory): # Enumerates the selected species forms on demand.
        if not entry.ends_with("/"): # Rejects loose files because a form must be a directory.
            continue # Skips unrelated entries without attempting to load them.
        var form_name: String = entry.trim_suffix("/") # Removes the ResourceLoader directory suffix.
        var normal_directory: String = species_directory.path_join(form_name).path_join("normal") # Resolves the expected normal-animation folder for this form.
        if not _has_complete_direction_set(normal_directory): # Validates the eight required frame resources for this selected form only.
            continue # Rejects incomplete forms without polluting the sprite cache.
        form_directories.append(normal_directory) # Retains a valid form directory for random selection.
    form_directories.sort() # Keeps form selection inputs deterministic before the random choice.
    _form_cache[species_directory] = form_directories # Caches the completed validation result for this species.
    return form_directories # Returns the selected species' usable forms.

static func choose_random_sprite_directory(species_directories: PackedStringArray, random: RandomNumberGenerator) -> String: # Chooses a species uniformly, then one available form for that species.
    if species_directories.is_empty(): # Rejects selection when no species folders are installed.
        return "" # Reports that no sprite directory can be chosen.
    var species_index: int = random.randi_range(0, species_directories.size() - 1) # Selects one discovered species uniformly.
    return choose_random_form_directory(species_directories[species_index], random) # Resolves and validates only the selected species' forms.

static func choose_random_form_directory(species_directory: String, random: RandomNumberGenerator) -> String: # Chooses one complete form while preserving an already-selected species/type pool.
    var form_directories: PackedStringArray = get_form_directories(species_directory) # Lazily resolves valid forms for the selected species.
    if form_directories.is_empty(): # Handles species that contain no complete normal sprite set.
        return "" # Reports that this species cannot currently provide a sprite.
    var form_index: int = random.randi_range(0, form_directories.size() - 1) # Selects one valid form uniformly.
    return form_directories[form_index] # Returns the resource directory containing the chosen directional frames.

static func get_sprite_frames(sprite_directory: String) -> SpriteFrames: # Builds or retrieves the directional animation library for one Pokémon form.
    if _sprite_frames_cache.has(sprite_directory): # Reuses an already-created SpriteFrames resource.
        return _sprite_frames_cache[sprite_directory] # Avoids repeated texture loads for species that respawn.
    var sprite_frames: SpriteFrames = SpriteFrames.new() # Creates one directional animation resource for this form.
    if sprite_frames.has_animation(&"default"): # Removes Godot's automatic placeholder animation when present.
        sprite_frames.remove_animation(&"default") # Leaves only the explicit directional animations used by gameplay.
    for direction: StringName in DIRECTIONS: # Builds idle and walking animation pairs for all four directions.
        var idle_animation: StringName = StringName("idle_" + String(direction)) # Resolves the idle animation name for this direction.
        var walk_animation: StringName = StringName("walk_" + String(direction)) # Resolves the walking animation name for this direction.
        var frame_zero_path: String = sprite_directory.path_join(String(direction) + "_0.png") # Resolves the first directional frame resource path.
        var frame_one_path: String = sprite_directory.path_join(String(direction) + "_1.png") # Resolves the second directional frame resource path.
        var frame_zero: Texture2D = _load_texture(frame_zero_path) # Loads the first frame through the guarded resource loader.
        var frame_one: Texture2D = _load_texture(frame_one_path) # Loads the second frame through the guarded resource loader.
        if frame_zero == null or frame_one == null: # Detects an import failure without attempting to build a partial animation set.
            push_error("Could not load complete HGSS sprite set from: " + sprite_directory) # Reports the affected species form once at the point of use.
            return SpriteFrames.new() # Returns an empty resource rather than caching broken frame data.
        sprite_frames.add_animation(idle_animation) # Creates the directional idle animation.
        sprite_frames.set_animation_loop(idle_animation, true) # Keeps idle playback valid when animation state is held.
        sprite_frames.set_animation_speed(idle_animation, 4.0) # Preserves the established idle animation timing.
        sprite_frames.add_frame(idle_animation, frame_zero) # Uses the first directional frame as the idle pose.
        sprite_frames.add_animation(walk_animation) # Creates the directional walking animation.
        sprite_frames.set_animation_loop(walk_animation, true) # Repeats the two-frame walking cycle continuously.
        sprite_frames.set_animation_speed(walk_animation, 6.0) # Preserves the established walking cadence.
        sprite_frames.add_frame(walk_animation, frame_zero) # Adds the first walking frame.
        sprite_frames.add_frame(walk_animation, frame_one) # Adds the second walking frame.
    _sprite_frames_cache[sprite_directory] = sprite_frames # Caches the fully validated animation resource for reuse.
    return sprite_frames # Returns the completed directional animation library.

static func _load_texture(resource_path: String) -> Texture2D: # Loads one imported texture only after confirming Godot recognizes the resource path.
    if not ResourceLoader.exists(resource_path, "Texture2D"): # Avoids calling load on missing or currently unavailable imported resources.
        return null # Reports failure without asking ResourceLoader to resolve an invalid path.
    return ResourceLoader.load(resource_path, "Texture2D") as Texture2D # Loads the recognized texture using Godot's export-safe resource remapping.

static func _has_complete_direction_set(sprite_directory: String) -> bool: # Checks that a selected form has both frames for all four required directions.
    for direction: StringName in DIRECTIONS: # Validates the selected form's directional image pairs.
        var frame_zero_path: String = sprite_directory.path_join(String(direction) + "_0.png") # Resolves the first expected frame path.
        var frame_one_path: String = sprite_directory.path_join(String(direction) + "_1.png") # Resolves the second expected frame path.
        if not ResourceLoader.exists(frame_zero_path, "Texture2D"): # Rejects forms missing the first imported directional frame.
            return false # Stops validation immediately on the first missing resource.
        if not ResourceLoader.exists(frame_one_path, "Texture2D"): # Rejects forms missing the second imported directional frame.
            return false # Stops validation immediately on the first incomplete directional pair.
    return true # Confirms that all eight directional frame resources are available.

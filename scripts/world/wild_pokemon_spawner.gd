class_name WildPokemonSpawner # Creates temporary Pokémon using habitat-aware, camera-safe, varied encounter rules.
extends Node3D # Owns active roaming Pokémon without owning terrain-generation policy.

const WILD_POKEMON_SCENE: PackedScene = preload("res://scenes/characters/wild_pokemon.tscn") # Keeps the reusable roaming character scene ready for inexpensive instantiation.
const RADIAL_MIN_SPAWN_RADIUS: float = 20.0 # Keeps new wildlife far enough from the player to avoid obvious arrival pop-in.
const RADIAL_MAX_SPAWN_RADIUS: float = 54.0 # Keeps new wildlife inside the useful streamed neighborhood around the player.
const RADIAL_INITIAL_WANDER_RADIUS: float = 14.0 # Gives newly spawned wildlife a varied first movement target inside its habitat.
const RADIAL_POSITION_ATTEMPTS: int = 18 # Bounds terrain and occlusion work for each requested individual.
const LOCAL_DENSITY_RADIUS: float = 10.0 # Defines the neighborhood used to prevent implausible spawn stacking.
const LOCAL_DENSITY_LIMIT: int = 3 # Prevents too many roaming Pokémon from occupying one small patch.
const RECENT_SPECIES_LIMIT: int = 10 # Keeps a short encounter history so the same species does not dominate successive spawns.
const OCCLUSION_COLLISION_MASK: int = 1 # Tests camera occlusion against the world collision layer used by generated terrain and static geometry.
const OCCLUSION_END_CLEARANCE: float = 0.55 # Requires the blocking surface to occur meaningfully before the candidate body sample.
const OCCLUSION_SAMPLE_OFFSETS: Array[Vector3] = [Vector3(0.0, 0.30, 0.0), Vector3(0.0, 0.95, 0.0), Vector3(0.0, 1.65, 0.0), Vector3(-0.42, 1.05, 0.0), Vector3(0.42, 1.05, 0.0)] # Covers feet, torso, head, and both sides so partially exposed candidates are rejected.

var random: RandomNumberGenerator = RandomNumberGenerator.new() # Provides independent spawn timing, species selection, form selection, and behaviour seeds.
var species_directories: PackedStringArray = PackedStringArray() # Stores installed National Dex sprite folders discovered lazily by the sprite library.
var species_by_biome: Dictionary = {} # Caches installed species into primary-type habitat pools for fast varied selection.
var recent_species: Array[String] = [] # Remembers recent species choices so repeated encounters receive lower priority.
var world_builder: HgssWorldBuilder # References the active world's habitat-aware terrain service.
var player_reference: Node3D # References the player for local population, distance, and ray-exclusion decisions.
var max_active_pokemon: int = 34 # Caps roaming CharacterBody3D count to keep physics work bounded.
var min_spawn_delay: float = 0.85 # Allows lively encounter pacing when the local population is sparse.
var max_spawn_delay: float = 3.1 # Adds broad timing variation so appearances do not feel mechanical.
var spawn_countdown: float = 0.0 # Tracks physics time remaining until the next eligible spawn attempt.

func _ready() -> void: # Resolves dependencies, indexes habitat pools, and schedules the first spawn attempt.
    random.randomize() # Separates runtime wildlife choices between play sessions.
    world_builder = get_tree().get_first_node_in_group(&"world_builder") as HgssWorldBuilder # Resolves the active world through the established semantic group.
    player_reference = get_tree().get_first_node_in_group(&"player") as Node3D # Resolves the player used by radial spawning and camera-safe exclusions.
    species_directories = PokemonSpriteLibrary.discover_species() # Enumerates species folders while deferring form texture validation until actual use.
    if world_builder == null: # Detects malformed scene composition before spawning begins.
        push_error("WildPokemonSpawner requires an HgssWorldBuilder in the world_builder group.") # Reports the missing world dependency directly.
        set_physics_process(false) # Prevents repeated work from an unusable spawner.
        return # Stops initialization without dereferencing the missing world.
    if species_directories.is_empty(): # Handles projects where the optional HGSS sprite folder has not been installed.
        push_warning("No HGSS Pokémon species folders were found under res://assets/pokemon/hgss_overworld.") # Reports the expected asset location without treating it as a fatal world error.
        set_physics_process(false) # Avoids running an empty spawn loop when no species can be created.
        return # Leaves the rest of the world playable without temporary roaming Pokémon.
    _index_species_by_biome() # Builds fast habitat pools once instead of scanning the whole catalogue for every spawn.
    _reset_spawn_countdown() # Schedules the first bounded wildlife spawn attempt.

func _physics_process(delta: float) -> void: # Advances spawn timing and performs physics-safe camera occlusion queries.
    if world_builder == null or species_directories.is_empty(): # Rejects processing when required world or sprite data is unavailable.
        return # Avoids needless per-frame work from an inactive spawner.
    if get_child_count() >= max_active_pokemon: # Enforces the global active wildlife population cap.
        spawn_countdown = maxf(spawn_countdown, 0.35) # Prevents an immediate burst the instant one crowded visitor despawns.
        return # Waits until population pressure falls before attempting another encounter.
    spawn_countdown -= delta # Advances the spawn timer inside the physics callback required for direct-space ray queries.
    if spawn_countdown > 0.0: # Detects whether the next attempt is still scheduled in the future.
        return # Avoids terrain, species, and ray work until the timer expires.
    _spawn_random_pokemon() # Attempts one varied encounter using the active world's spawning policy.
    _reset_spawn_countdown() # Schedules the next attempt independently of whether current camera occlusion allowed a spawn.

func _index_species_by_biome() -> void: # Groups installed species by Generation IV primary-type biome for fast repeated selection.
    species_by_biome.clear() # Removes stale pool data before rebuilding from the currently installed sprite catalogue.
    for species_directory: String in species_directories: # Visits each installed species exactly once during initialization.
        var biome_kind: int = PokemonGen4TypeLibrary.get_biome_kind_for_species_directory(species_directory) # Resolves the species' Generation IV primary-type habitat.
        if biome_kind < 0: # Rejects unsupported or unmapped species without contaminating habitat pools.
            continue # Leaves invalid entries available to no biome.
        var pool: PackedStringArray = species_by_biome.get(biome_kind, PackedStringArray()) # Reads or creates this biome's compact species pool.
        pool.append(species_directory) # Adds the installed species to its matching habitat pool.
        species_by_biome[biome_kind] = pool # Stores the updated packed array back into the dictionary value.

func _spawn_random_pokemon() -> void: # Routes spawning through finite-world or local infinite-world policy without duplicating character setup.
    if world_builder is RadialWorldBuilder: # Detects the streamed infinite radial topology used by the active main world.
        _spawn_radial_encounter(world_builder as RadialWorldBuilder) # Uses smarter local population and strict camera occlusion rules.
        return # Prevents the legacy finite-world entry policy from creating distant bodies.
    _spawn_finite_world_pokemon() # Preserves the original finite-world policy for alternate world implementations.

func _spawn_radial_encounter(radial_world: RadialWorldBuilder) -> void: # Creates a solo, pair, or small group encounter entirely inside the player's current habitat.
    if player_reference == null or not is_instance_valid(player_reference): # Recovers if startup ordering or scene replacement invalidated the cached player.
        player_reference = get_tree().get_first_node_in_group(&"player") as Node3D # Re-resolves the semantic player dependency only when necessary.
    if player_reference == null: # Handles malformed radial scenes without inventing a fallback spawn origin.
        return # Defers spawning until a valid player exists.
    var camera: Camera3D = get_viewport().get_camera_3d() # Reads the active gameplay camera used for strict occlusion validation.
    if camera == null: # Refuses to spawn when visibility cannot be evaluated reliably.
        return # Waits for an active camera rather than risking visible pop-in.
    var biome_kind: int = radial_world.get_biome_kind_at_world_position(player_reference.global_position) # Uses the player's current radial habitat as the encounter type.
    var species_directory: String = _choose_varied_species_for_biome(biome_kind) # Selects from the pre-indexed pool while avoiding recent repetition.
    if species_directory.is_empty(): # Handles habitats with no installed matching species.
        return # Skips the encounter instead of substituting an incorrect type.
    var encounter_size: int = _choose_encounter_size() # Produces mostly solo encounters with occasional pairs and compact groups.
    encounter_size = mini(encounter_size, max_active_pokemon - get_child_count()) # Respects the global population cap before doing any placement work.
    if encounter_size <= 0: # Handles a population race where the cap was reached during this frame.
        return # Avoids unnecessary form and terrain work.
    var anchor_position: Vector3 = _find_fully_occluded_spawn_position(radial_world, biome_kind, camera, player_reference.global_position, RADIAL_MAX_SPAWN_RADIUS) # Finds one camera-hidden anchor in the preferred distance band.
    if anchor_position == Vector3.INF: # Detects that no fully occluded practical position was found inside the bounded attempt budget.
        return # Refuses to spawn anywhere merely off-screen or exposed.
    var spawned_count: int = 0 # Tracks successfully created members of this encounter.
    for member_index: int in range(encounter_size): # Attempts each solo, pair, or group member independently.
        var entry_position: Vector3 = anchor_position # Uses the validated anchor directly for the first member.
        if member_index > 0: # Gives companions their own nearby hidden positions rather than stacking bodies exactly together.
            entry_position = _find_fully_occluded_spawn_position(radial_world, biome_kind, camera, anchor_position, 6.5) # Searches a compact neighborhood around the encounter anchor.
            if entry_position == Vector3.INF: # Allows a smaller group when nearby terrain is visible or crowded.
                continue # Skips only this companion rather than discarding the already valid encounter.
        if _count_pokemon_near(entry_position, LOCAL_DENSITY_RADIUS) >= LOCAL_DENSITY_LIMIT: # Prevents groups from creating implausible local crowding.
            continue # Looks to the next planned member without adding another body here.
        var member_species: String = species_directory # Keeps pairs and groups coherent by default.
        if member_index > 0 and random.randf() < 0.28: # Occasionally mixes a second habitat-compatible species into a group.
            var alternate_species: String = _choose_varied_species_for_biome(biome_kind) # Selects another recent-aware species from the same type habitat.
            if not alternate_species.is_empty(): # Accepts the alternate only when the habitat pool can provide one.
                member_species = alternate_species # Creates a mixed-species local encounter for additional variety.
        var sprite_directory: String = PokemonSpriteLibrary.choose_random_form_directory(member_species, random) # Lazily validates and chooses one complete sprite form.
        if sprite_directory.is_empty(): # Rejects incomplete forms without constructing a partially configured character.
            continue # Lets other planned encounter members continue normally.
        var initial_target: Vector3 = radial_world.get_random_walkable_world_position_near_in_biome(entry_position, RADIAL_INITIAL_WANDER_RADIUS, biome_kind, random) # Gives this visitor an independent first destination inside the same habitat.
        _create_pokemon(sprite_directory, entry_position, initial_target, biome_kind) # Instantiates the fully validated hidden visitor.
        _remember_species(member_species) # Lowers immediate repetition probability for subsequent encounters.
        spawned_count += 1 # Records one successful member for adaptive pacing and diagnostics.
    if spawned_count == 0: # Handles rare cases where the anchor was valid but density or asset checks rejected every member.
        return # Leaves pacing to the normal countdown reset without modifying recent-species history.

func _find_fully_occluded_spawn_position(radial_world: RadialWorldBuilder, biome_kind: int, camera: Camera3D, search_origin: Vector3, search_radius: float) -> Vector3: # Finds practical terrain that is completely hidden from the active camera by static world geometry.
    for attempt: int in range(RADIAL_POSITION_ATTEMPTS): # Bounds terrain, density, and raycast cost for one requested individual.
        var candidate: Vector3 = radial_world.get_random_walkable_world_position_near_in_biome(search_origin, search_radius, biome_kind, random) # Samples practical habitat terrain using the world's deterministic walkability service.
        if radial_world.get_biome_kind_at_world_position(candidate) != biome_kind: # Defends against edge cases near warped biome boundaries.
            continue # Keeps every encounter member inside the intended habitat.
        var distance_from_player: float = candidate.distance_to(player_reference.global_position) # Measures player separation for natural arrival spacing.
        if search_origin == player_reference.global_position and distance_from_player < RADIAL_MIN_SPAWN_RADIUS: # Applies the larger safety annulus only to primary encounter anchors.
            continue # Prevents wildlife from materializing immediately beside the player even behind a tiny obstacle.
        if _count_pokemon_near(candidate, LOCAL_DENSITY_RADIUS) >= LOCAL_DENSITY_LIMIT: # Rejects already crowded terrain patches before paying for raycasts.
            continue # Encourages population to spread around the explored environment.
        if not _is_fully_occluded_from_camera(candidate, camera): # Requires every representative body sample to be blocked by static world geometry.
            continue # Rejects candidates that are off-screen, behind-camera, or only partially hidden without genuine occlusion.
        return candidate # Returns the first practical, uncrowded, fully occluded candidate.
    return Vector3.INF # Reports failure without falling back to a potentially visible spawn.

func _is_fully_occluded_from_camera(candidate: Vector3, camera: Camera3D) -> bool: # Verifies that the complete approximate Pokémon body is hidden by static geometry from the active camera.
    var camera_origin: Vector3 = camera.global_position # Uses the physical camera location as the source of every visibility ray.
    var camera_right: Vector3 = camera.global_transform.basis.x.normalized() # Uses camera-right so lateral body samples correspond to what the player can actually see.
    var exclusions: Array[RID] = _build_occlusion_exclusions() # Prevents the player and existing Pokémon from masquerading as valid world occluders.
    var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state # Accesses the physics space safely from the spawner's physics callback.
    for offset: Vector3 in OCCLUSION_SAMPLE_OFFSETS: # Tests multiple vertical and lateral points across the approximate billboard body.
        var sample_position: Vector3 = candidate + Vector3.UP * offset.y + camera_right * offset.x # Converts the local body sample into a camera-relative world point.
        var sample_distance: float = camera_origin.distance_to(sample_position) # Measures total unobstructed distance to this body sample.
        if sample_distance <= OCCLUSION_END_CLEARANCE: # Rejects nonsensical candidates effectively occupying the camera itself.
            return false # Prevents a degenerate ray from being interpreted as hidden.
        var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(camera_origin, sample_position, OCCLUSION_COLLISION_MASK, exclusions) # Builds one allocation-contained world visibility query.
        query.collide_with_areas = false # Prevents trigger volumes from counting as visual occluders.
        query.collide_with_bodies = true # Includes terrain and other physical world geometry.
        query.hit_back_faces = true # Allows cliffs and terrain triangles to occlude consistently from either sampled direction.
        var result: Dictionary = space_state.intersect_ray(query) # Finds the first physical object between the camera and this body sample.
        if result.is_empty(): # Detects a completely clear camera ray.
            return false # Rejects the candidate because at least one part of its body would be visible.
        var collider: Object = result.get("collider") as Object # Reads the physical object responsible for the first obstruction.
        if not collider is StaticBody3D: # Rejects dynamic characters or other transient bodies as valid spawn concealment.
            return false # Requires stable world geometry to hide every body sample.
        var hit_position: Vector3 = result.get("position", sample_position) # Reads the obstruction point in global coordinates.
        if camera_origin.distance_to(hit_position) >= sample_distance - OCCLUSION_END_CLEARANCE: # Detects terrain hit only at or immediately beneath the candidate endpoint.
            return false # Prevents the candidate's own ground contact from falsely satisfying occlusion.
    return true # Confirms every tested body point is genuinely blocked by static world geometry.

func _build_occlusion_exclusions() -> Array[RID]: # Builds a small dynamic exclusion list for strict world-only camera occlusion rays.
    var exclusions: Array[RID] = [] # Stores collision-object RIDs ignored by the visibility queries.
    if player_reference is CollisionObject3D: # Excludes the player so their own body cannot hide a nearby spawn from the camera.
        exclusions.append((player_reference as CollisionObject3D).get_rid()) # Adds the player's current physics RID to every query.
    for child: Node in get_children(): # Visits only active roaming Pokémon owned by this spawner.
        if child is CollisionObject3D: # Restricts exclusions to nodes that actually participate in physics queries.
            exclusions.append((child as CollisionObject3D).get_rid()) # Prevents existing wildlife from counting as permanent visual cover.
    return exclusions # Returns the compact exclusion list for this spawn attempt.

func _count_pokemon_near(position: Vector3, radius: float) -> int: # Counts active wildlife inside one horizontal neighborhood without allocations.
    var radius_squared: float = radius * radius # Precomputes the squared comparison distance once.
    var count: int = 0 # Tracks nearby active visitors.
    for child: Node in get_children(): # Visits the bounded active population owned by this spawner.
        var pokemon: Node3D = child as Node3D # Narrows active children to spatial Pokémon nodes.
        if pokemon == null: # Guards any future non-spatial helper child.
            continue # Excludes helpers from local population density.
        var offset: Vector3 = pokemon.global_position - position # Measures displacement from the candidate patch.
        offset.y = 0.0 # Uses horizontal crowding so Pokémon on nearby terraces still affect local density naturally.
        if offset.length_squared() <= radius_squared: # Detects a visitor inside the configured local neighborhood.
            count += 1 # Adds this visitor to the crowding score.
    return count # Returns the bounded local population count.

func _choose_varied_species_for_biome(biome_kind: int) -> String: # Selects habitat-correct wildlife while strongly preferring species not seen in recent encounters.
    var pool: PackedStringArray = species_by_biome.get(biome_kind, PackedStringArray()) # Reads the pre-indexed species pool for the requested habitat.
    if pool.is_empty(): # Handles habitats without installed matching sprite species.
        return "" # Reports that no valid selection exists.
    var fallback: String = pool[random.randi_range(0, pool.size() - 1)] # Keeps one guaranteed candidate if every species happens to be recent.
    var attempts: int = mini(12, pool.size() * 2) # Bounds random recent-avoidance work regardless of catalogue size.
    for attempt: int in range(attempts): # Samples several candidates without allocating or shuffling the entire pool.
        var candidate: String = pool[random.randi_range(0, pool.size() - 1)] # Picks one habitat-correct species uniformly.
        if not recent_species.has(candidate): # Strongly favors species absent from the short recent encounter history.
            return candidate # Returns immediately when a fresh species is found.
        if random.randf() < 0.16: # Still permits occasional natural repeats so the system does not look artificially exhaustive.
            return candidate # Accepts this repeated species at a low probability.
    return fallback # Falls back safely when a small biome pool contains only recently seen species.

func _remember_species(species_directory: String) -> void: # Maintains a bounded recent encounter history for variety weighting.
    recent_species.append(species_directory) # Records the newly created species after a successful spawn.
    while recent_species.size() > RECENT_SPECIES_LIMIT: # Keeps lookup work and memory strictly bounded.
        recent_species.pop_front() # Removes the oldest encounter from repetition suppression.

func _choose_encounter_size() -> int: # Produces mostly solo encounters with occasional social groups for spatial variety.
    var roll: float = random.randf() # Draws one unit random value for the encounter composition.
    if roll < 0.08: # Makes compact trios uncommon enough to feel notable.
        return 3 # Requests a three-member encounter when terrain and population capacity allow it.
    if roll < 0.30: # Makes pairs meaningfully present without dominating the world.
        return 2 # Requests a two-member encounter.
    return 1 # Keeps most encounters as individual roaming Pokémon.

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

func _create_pokemon(sprite_directory: String, entry_position: Vector3, initial_target: Vector3, biome_kind: int) -> void: # Instantiates and configures one temporary Pokémon from already validated spawn data.
    var pokemon: WildPokemon = WILD_POKEMON_SCENE.instantiate() as WildPokemon # Creates the reusable overworld Pokémon scene.
    if pokemon == null: # Guards an unexpected scene-type regression before parenting.
        return # Avoids adding an invalid instance to the active population.
    add_child(pokemon) # Parents the visitor so the spawner's child count remains the active population source of truth.
    pokemon.global_position = entry_position # Places the visitor on its chosen practical terrain before movement setup.
    pokemon.setup(sprite_directory, world_builder, initial_target, biome_kind, random.randi()) # Supplies sprite, terrain policy, first destination, habitat, and independent behavior seed.

func _reset_spawn_countdown() -> void: # Schedules the next attempt using population-aware timing plus random variation.
    var population_ratio: float = clampf(float(get_child_count()) / float(maxi(max_active_pokemon, 1)), 0.0, 1.0) # Measures how full the active wildlife budget currently is.
    var base_delay: float = random.randf_range(min_spawn_delay, max_spawn_delay) # Provides broad non-periodic timing variation between encounters.
    spawn_countdown = base_delay * lerpf(0.78, 1.55, population_ratio) # Refills sparse worlds faster and naturally slows spawning as the area becomes busy.

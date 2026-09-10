class_name RadialWorldBuilder # Streams the infinite radial biome world while preserving the existing gameplay world-service API.
extends HgssWorldBuilder # Keeps existing player, wildlife, map, and navigation type contracts compatible.

const STREAM_LOAD_RADIUS: int = 5 # Keeps an eleven-by-eleven chunk window around the player instead of generating the infinite world at once.
const STREAM_UNLOAD_RADIUS: int = 6 # Retains one extra chunk ring to prevent load/unload thrashing near boundaries.
const INITIAL_CHUNK_RADIUS: int = 1 # Builds the immediate three-by-three terrain neighborhood synchronously so the player has a floor at startup.
const CHUNKS_PER_FRAME: int = 1 # Limits streamed terrain construction to one bounded chunk per rendered frame.
const LAND_SHADER: Shader = preload("res://resources/shaders/landscape.gdshader") # Reuses the established terrain shader for radial biome colour and route blending.

var radial_sampler: RadialWorldFieldSampler # Owns deterministic infinite topology, height, route, and biome sampling.
var active_chunks: Dictionary[Vector2i, RadialWorldChunk] = {} # Tracks only terrain chunks currently resident around the player.
var pending_chunks: Array[Vector2i] = [] # Queues nearby missing chunks for bounded incremental generation.
var player_reference: Node3D # Tracks the player position that drives streaming.
var stream_center_chunk: Vector2i = Vector2i(2147483647, 2147483647) # Forces the first resolved player position to populate a stream window.
var shared_terrain_material: ShaderMaterial # Reuses one shader material across every resident terrain chunk.

func _ready() -> void: # Initializes an infinite mathematical world without running the inherited finite full-map generator.
    add_to_group(&"world_builder") # Preserves the semantic world service lookup used throughout gameplay.
    process_physics_priority = -100 # Updates streamed floor coverage before ordinary character physics each frame.
    radial_sampler = RadialWorldFieldSampler.new(world_seed) # Creates one coordinate-stable infinite field sampler from the established world seed.
    shared_terrain_material = ShaderMaterial.new() # Allocates one shared terrain material for all streamed chunks.
    shared_terrain_material.shader = LAND_SHADER # Reuses the existing continuous ground shader.
    shared_terrain_material.set_shader_parameter(&"water_level", -1000.0) # Disables old finite-world wet-bank shading until radial water streaming is introduced separately.
    player_reference = get_tree().get_first_node_in_group(&"player") as Node3D # Resolves the player immediately when sibling setup order allows it.
    var initial_position: Vector3 = Vector3(0.0, 0.0, 69.0) # Matches the main scene's established starting area if the player group is not ready yet.
    if player_reference != null: # Prefers the real player transform whenever it is already available.
        initial_position = player_reference.global_position # Uses the actual spawn location as the first stream centre.
    var initial_chunk: Vector2i = world_to_chunk(initial_position) # Converts the starting point into the infinite chunk grid.
    _build_initial_chunks(initial_chunk) # Guarantees collision directly beneath and around the player before exploration begins.
    _refresh_stream_window(initial_chunk) # Queues the remaining visible terrain around the initial neighborhood.
    call_deferred("_resolve_player") # Rechecks the player after all scene siblings complete their ready lifecycle.

func _process(_delta: float) -> void: # Builds queued terrain incrementally so exploration never triggers a whole-world frame spike.
    var builds_remaining: int = CHUNKS_PER_FRAME # Caps expensive mesh and collision construction per rendered frame.
    while builds_remaining > 0 and not pending_chunks.is_empty(): # Processes only the allowed bounded amount of queued work.
        var coordinate: Vector2i = pending_chunks.pop_front() # Takes the nearest-priority missing chunk from the stream queue.
        if not active_chunks.has(coordinate): # Avoids rebuilding chunks loaded synchronously or by an earlier queue entry.
            _build_chunk(coordinate) # Materializes this deterministic local section of the infinite world.
        builds_remaining -= 1 # Accounts for one chunk-generation budget slot.

func _physics_process(_delta: float) -> void: # Tracks player chunk changes before character movement consumes terrain collision.
    if player_reference == null: # Handles startup ordering or a temporarily missing player safely.
        return # Waits for deferred dependency resolution instead of streaming around an invalid position.
    var current_chunk: Vector2i = world_to_chunk(player_reference.global_position) # Finds the infinite chunk currently containing the player.
    if not active_chunks.has(current_chunk): # Handles fast travel or unusually rapid movement into an unbuilt chunk.
        _build_chunk(current_chunk) # Builds the player's floor synchronously before their physics update.
    if current_chunk == stream_center_chunk: # Skips queue rebuilding while the player remains inside the same chunk.
        return # Leaves incremental generation to the normal process loop.
    _refresh_stream_window(current_chunk) # Re-centres loaded terrain and queues newly visible chunks after crossing a chunk boundary.

func _resolve_player() -> void: # Resolves the player after scene construction and recentres streaming if necessary.
    player_reference = get_tree().get_first_node_in_group(&"player") as Node3D # Uses the existing semantic player group rather than a hard-coded NodePath.
    if player_reference == null: # Reports malformed scene composition without crashing world generation.
        push_error("RadialWorldBuilder could not find the player group.") # Gives an actionable dependency error.
        return # Stops before dereferencing the missing player.
    var current_chunk: Vector2i = world_to_chunk(player_reference.global_position) # Reads the real player start or post-fast-travel location.
    if not active_chunks.has(current_chunk): # Ensures the resolved player always has physical terrain immediately beneath them.
        _build_chunk(current_chunk) # Creates the local floor synchronously when startup ordering required the fallback position.
    _refresh_stream_window(current_chunk) # Aligns the visible infinite-world window with the actual player location.

func _build_initial_chunks(center_chunk: Vector2i) -> void: # Creates only the immediate startup terrain needed for safe player physics.
    for offset_y: int in range(-INITIAL_CHUNK_RADIUS, INITIAL_CHUNK_RADIUS + 1): # Traverses the small initial chunk rows.
        for offset_x: int in range(-INITIAL_CHUNK_RADIUS, INITIAL_CHUNK_RADIUS + 1): # Traverses each chunk in the startup row.
            _build_chunk(center_chunk + Vector2i(offset_x, offset_y)) # Builds the compact three-by-three physical neighborhood synchronously.

func _refresh_stream_window(center_chunk: Vector2i) -> void: # Rebuilds the desired resident chunk set around a new player chunk.
    stream_center_chunk = center_chunk # Stores the active stream origin for cheap unchanged-position checks.
    pending_chunks.clear() # Drops stale priorities because deterministic chunks can be re-queued safely from the new centre.
    for radius: int in range(STREAM_LOAD_RADIUS + 1): # Queues chunks in concentric square rings so nearest missing terrain builds first.
        for offset_y: int in range(-radius, radius + 1): # Traverses one ring's candidate rows.
            for offset_x: int in range(-radius, radius + 1): # Traverses every candidate coordinate in the current ring.
                if maxi(absi(offset_x), absi(offset_y)) != radius: # Keeps each coordinate in exactly one concentric ring.
                    continue # Skips interior cells already visited by smaller radii.
                var coordinate: Vector2i = center_chunk + Vector2i(offset_x, offset_y) # Resolves the desired infinite chunk coordinate.
                if active_chunks.has(coordinate): # Leaves already resident terrain untouched.
                    continue # Avoids redundant queue entries and mesh work.
                pending_chunks.append(coordinate) # Queues this missing chunk behind all nearer rings.
    var loaded_coordinates: Array[Vector2i] = [] # Takes a stable typed snapshot before mutating the active chunk dictionary.
    for coordinate: Vector2i in active_chunks: # Reads every currently resident terrain coordinate.
        loaded_coordinates.append(coordinate) # Copies the key for safe unload iteration.
    for coordinate: Vector2i in loaded_coordinates: # Evaluates old chunks after the desired queue has been rebuilt.
        var distance: int = maxi(absi(coordinate.x - center_chunk.x), absi(coordinate.y - center_chunk.y)) # Measures cheap Chebyshev chunk distance from the player.
        if distance <= STREAM_UNLOAD_RADIUS: # Keeps chunks inside the hysteresis ring resident.
            continue # Avoids churn around the visible stream boundary.
        var chunk: RadialWorldChunk = active_chunks[coordinate] # Reads the scene node being retired.
        active_chunks.erase(coordinate) # Removes bookkeeping immediately so the coordinate can be regenerated later.
        chunk.queue_free() # Releases render, collision, and MultiMesh resources safely at frame end.

func _build_chunk(coordinate: Vector2i) -> void: # Materializes one deterministic terrain chunk if it is not already resident.
    if active_chunks.has(coordinate): # Rejects duplicate requests from startup, streaming, or fast travel.
        return # Preserves one scene node per infinite chunk coordinate.
    var chunk: RadialWorldChunk = RadialWorldChunk.new() # Creates the bounded renderer and collider for this coordinate.
    chunk.build(coordinate, radial_sampler, shared_terrain_material, TILE_SIZE) # Generates local geometry entirely from global deterministic samples.
    add_child(chunk) # Adds the complete chunk beneath the world service node.
    active_chunks[coordinate] = chunk # Records residency after successful construction.

func world_to_chunk(world_position: Vector3) -> Vector2i: # Converts an arbitrary world position into the unbounded streamed chunk grid.
    var chunk_world_size: float = float(RadialWorldChunk.CHUNK_CELLS) * TILE_SIZE # Measures one chunk edge in world units.
    return Vector2i(floori(world_position.x / chunk_world_size), floori(world_position.z / chunk_world_size)) # Uses floor semantics so negative coordinates map continuously.

func world_to_cell(world_position: Vector3) -> Vector2i: # Converts world-space X/Z into an unbounded logical terrain cell coordinate.
    return Vector2i(floori(world_position.x / TILE_SIZE), floori(world_position.z / TILE_SIZE)) # Removes the inherited finite-world half-size offset entirely.

func cell_to_world(cell: Vector2i) -> Vector3: # Converts an unbounded logical cell into its deterministic streamed terrain centre.
    var cell_position: Vector2 = Vector2(float(cell.x) + 0.5, float(cell.y) + 0.5) # Samples the centre of the requested infinite terrain cell.
    var height: float = radial_sampler.sample_height(cell_position) # Reads the same deterministic surface function used by chunk vertices.
    return Vector3(cell_position.x * TILE_SIZE, height + 0.06, cell_position.y * TILE_SIZE) # Returns the established small character floor-contact lift above terrain.

func is_cell_walkable(cell: Vector2i) -> bool: # Tests local geometric slope without consulting any finite world bounds.
    var x: float = float(cell.x) # Converts the integer cell X into field coordinates once.
    var z: float = float(cell.y) # Converts the integer cell Z into field coordinates once.
    var a: float = radial_sampler.sample_height(Vector2(x, z)) # Samples the near-left terrain corner.
    var b: float = radial_sampler.sample_height(Vector2(x + 1.0, z)) # Samples the near-right terrain corner.
    var c: float = radial_sampler.sample_height(Vector2(x + 1.0, z + 1.0)) # Samples the far-right terrain corner.
    var d: float = radial_sampler.sample_height(Vector2(x, z + 1.0)) # Samples the far-left terrain corner.
    var minimum_height: float = minf(minf(a, b), minf(c, d)) # Finds the lowest corner in the physical terrain cell.
    var maximum_height: float = maxf(maxf(a, b), maxf(c, d)) # Finds the highest corner in the physical terrain cell.
    return (maximum_height - minimum_height) / TILE_SIZE <= MAX_WALKABLE_SLOPE # Accepts cells whose physical grade remains inside the established traversal limit.

func get_nearest_walkable_world_position(world_position: Vector3) -> Vector3: # Snaps an arbitrary infinite-world position to nearby traversable terrain.
    var origin_cell: Vector2i = world_to_cell(world_position) # Starts the bounded search at the requested horizontal coordinate.
    if is_cell_walkable(origin_cell): # Uses the requested cell immediately when its physical slope is practical.
        return cell_to_world(origin_cell) # Returns the deterministic terrain centre without scanning neighbors.
    for radius: int in range(1, 13): # Expands a bounded square search far enough to escape local steep terrain.
        for offset_y: int in range(-radius, radius + 1): # Traverses the current search ring rows.
            for offset_x: int in range(-radius, radius + 1): # Traverses candidate cells around the requested point.
                if maxi(absi(offset_x), absi(offset_y)) != radius: # Keeps the search on the current ring perimeter.
                    continue # Avoids rechecking cells from smaller search radii.
                var candidate: Vector2i = origin_cell + Vector2i(offset_x, offset_y) # Resolves one nearby infinite cell candidate.
                if is_cell_walkable(candidate): # Accepts the first practical terrain cell in distance order.
                    return cell_to_world(candidate) # Returns the deterministic grounded world position.
    return cell_to_world(origin_cell) # Falls back to the requested terrain cell if an extreme generated area defeats the bounded search.

func get_biome_kind_at_world_position(world_position: Vector3) -> int: # Exposes radial biome ownership for UI, spawning, and diagnostics.
    var cell_position: Vector2 = Vector2(world_position.x / TILE_SIZE, world_position.z / TILE_SIZE) # Converts world X/Z into the sampler's global logical coordinates.
    return radial_sampler.sample_biome(cell_position) # Returns central neutral ownership or one infinite outer type sector.

func get_biome_landmark_cell(biome_kind: int) -> Vector2: # Exposes deterministic radial landmark coordinates to the dedicated landmark system.
    return radial_sampler.get_biome_landmark_cell(biome_kind) # Delegates topology placement to the single authoritative sampler.

func get_random_biome_entry_pair(biome_kind: int, random: RandomNumberGenerator) -> Array[Vector3]: # Creates wildlife entry and inward targets without finite cached habitat boundaries.
    if biome_kind == BiomeKind.NORMAL: # Keeps Normal Pokémon inside the large neutral central area.
        var start_angle: float = random.randf_range(0.0, TAU) # Chooses an unbiased direction around the central hub.
        var start_radius: float = random.randf_range(28.0, 58.0) # Places the visitor well inside neutral terrain.
        var start_cell: Vector2 = Vector2(cos(start_angle), sin(start_angle)) * start_radius # Resolves the neutral entry cell coordinate.
        var target_cell: Vector2 = start_cell * 0.72 # Moves the visitor gently farther into the central hub.
        return [_cell_vector_to_world(start_cell), _cell_vector_to_world(target_cell)] # Returns grounded entry and inward positions.
    var axis_angle: float = radial_sampler.get_biome_axis_angle(biome_kind) # Uses the assigned type world's evenly spaced centre axis.
    var angular_jitter: float = random.randf_range(-RadialWorldFieldSampler.SECTOR_ANGLE * 0.20, RadialWorldFieldSampler.SECTOR_ANGLE * 0.20) # Varies entries while keeping them safely inside the sector.
    var direction: Vector2 = Vector2(cos(axis_angle + angular_jitter), sin(axis_angle + angular_jitter)) # Builds the outward unit direction for this visitor.
    var edge_radius: float = radial_sampler.get_neutral_boundary_radius(direction * RadialWorldFieldSampler.CENTER_RADIUS_CELLS) # Reads the organic hub edge along the chosen direction.
    var entry_cell: Vector2 = direction * (edge_radius + 7.0) # Starts the visitor just inside its infinite type world.
    var target_cell: Vector2 = direction * (edge_radius + 20.0) # Gives it an initial destination farther outward in its own region.
    return [_cell_vector_to_world(entry_cell), _cell_vector_to_world(target_cell)] # Returns grounded world positions derived from the infinite terrain function.

func get_biome_exit_target_from(world_position: Vector3, biome_kind: int) -> Vector3: # Returns a nearby inner boundary target when a temporary Pokémon leaves.
    if biome_kind == BiomeKind.NORMAL: # Sends neutral visitors toward the central plaza when their visit ends.
        return get_nearest_walkable_world_position(Vector3.ZERO) # Uses the deterministic central hub floor as the departure target.
    var cell_position: Vector2 = Vector2(world_position.x / TILE_SIZE, world_position.z / TILE_SIZE) # Converts the current visitor position into radial cell coordinates.
    var radius: float = maxf(cell_position.length(), 0.001) # Measures current distance from the central hub safely.
    var direction: Vector2 = cell_position / radius # Preserves the visitor's current angular direction within its sector.
    var edge_radius: float = radial_sampler.get_neutral_boundary_radius(direction * RadialWorldFieldSampler.CENTER_RADIUS_CELLS) # Reads the local organic neutral boundary.
    var target_cell: Vector2 = direction * (edge_radius + 5.0) # Places the departure point just outside the neutral hub.
    if radial_sampler.sample_biome(target_cell) != biome_kind: # Handles strongly warped border cases near a neighboring type sector.
        var axis_angle: float = radial_sampler.get_biome_axis_angle(biome_kind) # Falls back to the guaranteed centre axis of this type world.
        target_cell = Vector2(cos(axis_angle), sin(axis_angle)) * (RadialWorldFieldSampler.CENTER_RADIUS_CELLS + 7.0) # Places a deterministic safe boundary target in the correct sector.
    return get_nearest_walkable_world_position(_cell_vector_to_world(target_cell)) # Returns a practical grounded departure location.

func get_random_walkable_world_position_in_biome(biome_kind: int, random: RandomNumberGenerator) -> Vector3: # Samples a practical position from an infinite type region without precomputed habitat caches.
    for attempt: int in range(64): # Uses bounded deterministic-style random attempts so spawn work remains predictable.
        var cell_position: Vector2 # Stores one candidate global logical coordinate.
        if biome_kind == BiomeKind.NORMAL: # Samples within the large neutral central disk for Normal Pokémon.
            var angle: float = random.randf_range(0.0, TAU) # Chooses an unbiased neutral-hub direction.
            var radius: float = sqrt(random.randf()) * (RadialWorldFieldSampler.CENTER_RADIUS_CELLS - 14.0) # Samples the disk approximately uniformly by area.
            cell_position = Vector2(cos(angle), sin(angle)) * radius # Resolves the candidate neutral cell coordinate.
        else: # Samples along the infinite outward extent of one type sector.
            var axis_angle: float = radial_sampler.get_biome_axis_angle(biome_kind) # Reads the stable centre axis for this type.
            var angle_jitter: float = random.randf_range(-RadialWorldFieldSampler.SECTOR_ANGLE * 0.30, RadialWorldFieldSampler.SECTOR_ANGLE * 0.30) # Keeps the sample comfortably inside neighboring borders.
            var radius: float = random.randf_range(RadialWorldFieldSampler.CENTER_RADIUS_CELLS + 18.0, RadialWorldFieldSampler.CENTER_RADIUS_CELLS + 85.0) # Chooses a nearby representative part of the otherwise infinite region.
            cell_position = Vector2(cos(axis_angle + angle_jitter), sin(axis_angle + angle_jitter)) * radius # Resolves the candidate outer-world coordinate.
        var cell: Vector2i = Vector2i(floori(cell_position.x), floori(cell_position.y)) # Converts the floating sample into a logical terrain cell.
        if radial_sampler.sample_biome(cell_position) == biome_kind and is_cell_walkable(cell): # Requires correct regional ownership and practical physical slope.
            return cell_to_world(cell) # Returns the first valid grounded habitat position.
    return get_nearest_walkable_world_position(_cell_vector_to_world(radial_sampler.get_biome_landmark_cell(biome_kind))) # Falls back to the region's guaranteed inner landmark area.

func get_random_walkable_world_position_near_in_biome(world_position: Vector3, radius: float, biome_kind: int, random: RandomNumberGenerator) -> Vector3: # Samples a local wander target while preserving infinite radial habitat ownership.
    var radius_cells: float = maxf(radius / TILE_SIZE, 1.0) # Converts the caller's world-space radius into logical-cell distance.
    var center_cell: Vector2 = Vector2(world_position.x / TILE_SIZE, world_position.z / TILE_SIZE) # Converts the current position into global logical coordinates.
    for attempt: int in range(64): # Keeps local wander sampling bounded for stable frame time.
        var angle: float = random.randf_range(0.0, TAU) # Chooses an unbiased local direction.
        var distance: float = sqrt(random.randf()) * radius_cells # Samples approximately uniformly across the local search disk.
        var candidate_position: Vector2 = center_cell + Vector2(cos(angle), sin(angle)) * distance # Resolves one nearby infinite-world coordinate.
        var candidate_cell: Vector2i = Vector2i(floori(candidate_position.x), floori(candidate_position.y)) # Converts the candidate to the logical navigation grid.
        if radial_sampler.sample_biome(candidate_position) == biome_kind and is_cell_walkable(candidate_cell): # Keeps wandering inside the assigned type and on practical terrain.
            return cell_to_world(candidate_cell) # Returns the first valid nearby grounded target.
    return get_nearest_walkable_world_position(world_position) # Keeps the visitor near its current position if no local candidate succeeds.

func get_random_entry_pair(random: RandomNumberGenerator) -> Array[Vector3]: # Preserves the legacy global entry API by selecting one radial outer type world.
    var biome_kind: int = random.randi_range(1, BiomeKind.size() - 1) # Selects one non-neutral type region uniformly.
    return get_random_biome_entry_pair(biome_kind, random) # Reuses the authoritative radial habitat entry logic.

func _cell_vector_to_world(cell_position: Vector2) -> Vector3: # Grounds a floating logical coordinate directly on the infinite terrain surface.
    var height: float = radial_sampler.sample_height(cell_position) # Samples the deterministic terrain function at the exact requested point.
    return Vector3(cell_position.x * TILE_SIZE, height + 0.06, cell_position.y * TILE_SIZE) # Converts to world space with the established floor-contact lift.

extends SceneTree # Exercises the generated landscape, navigation, and physical travel through the real main scene.

var _scene: Node3D # Owns the complete gameplay scene under test.
var _world: HgssWorldBuilder # References the actual generated terrain service.
var _player: CharacterBody3D # References the actual player physics body.
var _destinations: Array[Dictionary] = [] # Stores the real map travel destinations.
var _frames: int = 0 # Tracks deterministic test frames without connecting signals.
var _arrival_index: int = -1 # Tracks the destination currently undergoing a physical landing check.
var _failures: PackedStringArray = PackedStringArray() # Collects actionable failures before returning the test exit status.
var _started: int = 0 # Measures actual scene generation time.

func _initialize() -> void: # Schedules scene construction after the test tree exists.
    _started = Time.get_ticks_msec() # Starts timing before any world generation work.
    _start.call_deferred() # Loads the main scene after tree initialization without signals.

func _start() -> void: # Instantiates the same scene used when the project is played.
    var packed: PackedScene = load("res://scenes/world/main.tscn") as PackedScene # Loads the project's actual gameplay composition.
    _scene = packed.instantiate() as Node3D # Creates the complete game world and player.
    root.add_child(_scene) # Runs the normal generation and system initialization lifecycle.
    _world = get_first_node_in_group(&"world_builder") as HgssWorldBuilder # Resolves the generated world service.
    _player = get_first_node_in_group(&"player") as CharacterBody3D # Resolves the real movement and collision controller.
    print("world_generation_ms=", Time.get_ticks_msec() - _started) # Reports generation duration for the expanded terrain.

func _process(_delta: float) -> bool: # Advances deterministic setup and destination landing checks.
    if _world == null: # Waits until deferred scene construction completes.
        return false # Keeps the test tree alive during initialization.
    _frames += 1 # Advances the deterministic test frame counter.
    if _frames == 3: # Waits for the landmark system's deferred initialization.
        _check_world() # Verifies region reachability, physical route grades, and generated render structure.
        _start_arrival(0) # Begins the first actual player landing check.
    elif _frames > 3 and (_frames - 3) % 24 == 0: # Gives physics time to settle at each destination.
        _check_arrival() # Confirms that the actual player lands on usable terrain.
        if _arrival_index + 1 < _destinations.size(): # Continues while there are untested travel destinations.
            _start_arrival(_arrival_index + 1) # Teleports the player using the same destination positions as the map.
        else: # Finishes after checking the complete destination list.
            for failure: String in _failures: # Prints every actionable failure together.
                printerr(failure) # Exposes the failing travel or terrain invariant.
            print("world_smoke: ", "PASS" if _failures.is_empty() else "FAIL", "; destinations=", _destinations.size()) # Reports the complete integration result.
            quit(0 if _failures.is_empty() else 1) # Returns a failing process status when any physical or navigation check failed.
    return false # Keeps normal gameplay physics running throughout the integration test.

func _check_world() -> void: # Validates generated terrain and every type habitat before testing physical arrivals.
    var landmarks: WorldLandmarkSystem = get_first_node_in_group(&"world_landmarks") as WorldLandmarkSystem # Resolves the map's actual landmark provider.
    _destinations = landmarks.get_destinations() # Reads the same arrival metadata consumed by fast travel.
    _check(_destinations.size() == HgssWorldBuilder.BiomeKind.size(), "Missing biome travel destinations") # Requires every supported habitat to remain explorable.
    _check(_world.height_vertices.size() == (HgssWorldBuilder.WORLD_WIDTH + 1) * (HgssWorldBuilder.WORLD_DEPTH + 1), "Incomplete terrain height field") # Guards truncated or partially generated terrain.
    var hub: Vector3 = _player.global_position # Uses the actual safe player start as the navigation origin.
    for destination: Dictionary in _destinations: # Checks every biome through the real shared navigation cache.
        var position: Vector3 = destination["position"] # Reads the actual travel arrival position.
        var biome: int = destination["biome"] # Reads the destination's habitat identity.
        var route: Array[Vector3] = HgssWorldNavigation.get_world_path(_world, hub, position) # Builds a route through the real walkable terrain.
        _check(not route.is_empty(), "Unreachable destination: %s" % destination["landmark_name"]) # Detects disconnected regions after river or terrain changes.
        _check(not _world.biome_spawn_cells[biome].is_empty(), "Empty habitat: %s" % biome) # Ensures every type region retains usable habitat terrain.
        _check(not _world.biome_entry_cells[biome].is_empty(), "Missing habitat route entries: %s" % biome) # Preserves wildlife entry and departure support.
    var steep_routes: int = 0 # Counts routes that exceed the real player controller's slope allowance.
    for cell: Vector2i in _world.terrain_cache: # Examines every generated route cell rather than selected landmarks alone.
        if _world.terrain_cache[cell] != HgssWorldBuilder.TerrainKind.PATH: # Skips natural slopes that do not promise a walking route.
            continue # Limits physical grade checks to designed travel corridors.
        var width: int = HgssWorldBuilder.WORLD_WIDTH + 1 # Reads the shared terrain row stride.
        var a: float = _world.height_vertices[cell.y * width + cell.x] # Reads the near-left route corner.
        var b: float = _world.height_vertices[cell.y * width + cell.x + 1] # Reads the near-right route corner.
        var d: float = _world.height_vertices[(cell.y + 1) * width + cell.x] # Reads the far-left route corner.
        var c: float = _world.height_vertices[(cell.y + 1) * width + cell.x + 1] # Reads the far-right route corner.
        var grade: float = maxf(Vector2(b - a, c - b).length(), Vector2(c - d, d - a).length()) / HgssWorldBuilder.TILE_SIZE # Measures the actual steepest rendered route triangle.
        if grade > tan(_player.floor_max_angle): # Compares route geometry with the actual controller's walkable incline.
            steep_routes += 1 # Counts an inaccessible route surface for the final assertion.
    _check(steep_routes == 0, "Route triangles exceed player slope limit: %s" % steep_routes) # Prevents logical paths that the player cannot physically follow.
    var terrain_chunks: int = 0 # Counts independently culled terrain render objects.
    var scenery_chunks: int = 0 # Counts bounded repeated-scenery batches.
    for child: Node in _world.get_children(): # Inspects the actual generated world composition.
        if child is MeshInstance3D and String(child.name).begins_with("terrain_"): # Identifies the indexed terrain chunks.
            terrain_chunks += 1 # Records the terrain's culling granularity.
        if child is MultiMeshInstance3D: # Identifies GPU-instanced scenery groups.
            var batch: MultiMeshInstance3D = child as MultiMeshInstance3D # Reads typed batch bounds for validation.
            if not String(child.name).begins_with("generated_bridges"): # Leaves the separate bridge builder outside scenery-batch bounds checks.
                _check(batch.multimesh.get_aabb().size.x < 60.0 and batch.multimesh.get_aabb().size.z < 60.0, "Unbounded scenery batch: %s" % child.name) # Prevents a regression to drawing whole-world scenery at once.
                scenery_chunks += 1 # Records the number of bounded scenery groups.
    _check(terrain_chunks > 1, "Terrain is not split into cullable chunks") # Requires the expanded landscape to retain spatial rendering bounds.
    print("terrain_chunks=", terrain_chunks, "; scenery_chunks=", scenery_chunks, "; trees=", _world.tree_cells.size(), "; bridge_cells=", _world.bridge_cells.size(), "; steep_routes=", steep_routes) # Reports meaningful generated-world metrics.

func _start_arrival(index: int) -> void: # Moves the real player to a map destination for a physical landing check.
    _arrival_index = index # Stores the destination currently under test.
    if index >= _destinations.size(): # Handles missing destinations without indexing an empty list.
        return # Leaves the missing-destination assertion to report the failure.
    _player.global_position = _destinations[index]["position"] # Uses the exact map fast-travel arrival position.
    _player.velocity = Vector3.ZERO # Matches the game's fast-travel velocity reset.

func _check_arrival() -> void: # Confirms that navigation arrivals also work with actual physics collision.
    if _arrival_index < 0 or _arrival_index >= _destinations.size(): # Guards setup failures before destination metadata exists.
        return # Avoids obscuring the original failure with a bounds error.
    var name: String = _destinations[_arrival_index]["landmark_name"] # Identifies the destination in any failure report.
    var position: Vector3 = _destinations[_arrival_index]["position"] # Reads the expected grounded arrival point.
    _check(_player.is_on_floor(), "Player did not land at %s" % name) # Detects missing floor collision or inaccessible slope surfaces.
    _check(absf(_player.global_position.y - position.y) < 0.24, "Rendered and physical arrival heights disagree at %s" % name) # Detects height interpolation mismatches or disconnected decks.
    _check(_world.is_cell_walkable(_world.world_to_cell(_player.global_position)), "Player landed in a blocked cell at %s" % name) # Keeps final physical positions consistent with habitat navigation.

func _check(condition: bool, message: String) -> void: # Collects failures without aborting the remaining integration checks.
    if not condition: # Retains only failed invariants for the final report.
        _failures.append(message) # Preserves the actionable failure detail.

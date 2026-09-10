extends SceneTree # Exercises the streamed radial landscape, infinite topology, navigation, and physical fast travel through the real main scene.

var _scene: Node3D # Owns the complete gameplay scene under test.
var _world: RadialWorldBuilder # References the actual infinite streamed terrain service.
var _player: CharacterBody3D # References the actual player physics body.
var _destinations: Array[Dictionary] = [] # Stores the real map travel destinations.
var _frames: int = 0 # Tracks deterministic test frames without connecting signals.
var _arrival_index: int = -1 # Tracks the destination currently undergoing a physical landing check.
var _failures: PackedStringArray = PackedStringArray() # Collects actionable failures before returning the test exit status.
var _started: int = 0 # Measures actual scene startup time before incremental background-style chunk streaming continues.

func _initialize() -> void: # Schedules scene construction after the test tree exists.
    _started = Time.get_ticks_msec() # Starts timing before the main scene is instantiated.
    _start.call_deferred() # Loads the gameplay scene after SceneTree initialization without signals.

func _start() -> void: # Instantiates the same radial world scene used when the project is played.
    var packed: PackedScene = load("res://scenes/world/main.tscn") as PackedScene # Loads the project's actual gameplay composition.
    _scene = packed.instantiate() as Node3D # Creates the streamed world, player, wildlife, landmarks, and map.
    root.add_child(_scene) # Runs the normal scene initialization lifecycle.
    _world = get_first_node_in_group(&"world_builder") as RadialWorldBuilder # Resolves the radial world service specifically.
    _player = get_first_node_in_group(&"player") as CharacterBody3D # Resolves the real movement and collision controller.
    print("radial_world_startup_ms=", Time.get_ticks_msec() - _started) # Reports startup cost before the full visible chunk window has streamed in.

func _process(_delta: float) -> bool: # Advances deterministic setup and destination landing checks while chunk streaming runs normally.
    if _world == null or _player == null: # Waits until deferred scene construction completes.
        return false # Keeps the test tree alive during initialization.
    _frames += 1 # Advances the deterministic frame counter.
    if _frames == 20: # Allows deferred landmarks and several incremental chunks to become resident.
        _check_world() # Verifies infinite radial topology and bounded streaming behavior.
        _start_arrival(0) # Begins the first actual player landing check.
    elif _frames > 20 and (_frames - 20) % 24 == 0: # Gives physics and immediate destination chunk streaming time to settle after each teleport.
        _check_arrival() # Confirms the actual player lands on generated terrain.
        if _arrival_index + 1 < _destinations.size(): # Continues while untested map destinations remain.
            _start_arrival(_arrival_index + 1) # Teleports to the next real fast-travel arrival.
        else: # Finishes after every destination has undergone a physical landing check.
            for failure: String in _failures: # Prints every actionable failure together.
                printerr(failure) # Exposes the failing topology, stream, navigation, or landing invariant.
            print("world_smoke: ", "PASS" if _failures.is_empty() else "FAIL", "; destinations=", _destinations.size(), "; resident_chunks=", _world.active_chunks.size()) # Reports the integration result and bounded stream size.
            quit(0 if _failures.is_empty() else 1) # Returns a failing process status when any invariant failed.
    return false # Keeps ordinary gameplay processing and physics active throughout the integration test.

func _check_world() -> void: # Validates central neutrality, equal infinite sectors, streamed residency, and local navigation.
    var landmarks: WorldLandmarkSystem = get_first_node_in_group(&"world_landmarks") as WorldLandmarkSystem # Resolves the map's actual radial landmark provider.
    _check(landmarks != null, "Missing radial landmark system") # Requires the landmark dependency before reading destinations.
    if landmarks == null: # Prevents a secondary error when landmark initialization failed.
        return # Leaves the dependency assertion to report the failure.
    _destinations = landmarks.get_destinations() # Reads the same arrival metadata consumed by fast travel.
    _check(_destinations.size() == HgssWorldBuilder.BiomeKind.size(), "Missing radial biome travel destinations") # Requires the neutral hub plus all sixteen outer type worlds.
    _check(_world.get_biome_kind_at_world_position(Vector3.ZERO) == HgssWorldBuilder.BiomeKind.NORMAL, "World origin is not neutral") # Requires the complete centre of the pizza topology to be neutral.
    var maximum_resident: int = (RadialWorldBuilder.STREAM_UNLOAD_RADIUS * 2 + 1) * (RadialWorldBuilder.STREAM_UNLOAD_RADIUS * 2 + 1) # Calculates the hard upper bound implied by streaming hysteresis.
    _check(_world.active_chunks.size() > 0, "No streamed terrain chunks are resident") # Requires physical terrain to exist around the player.
    _check(_world.active_chunks.size() <= maximum_resident, "Stream retained too many terrain chunks") # Prevents regression to accumulating the infinite world in memory.
    var previous_angle: float = -1.0 # Tracks outer landmark angular ordering for even-sector validation.
    for biome_kind: int in range(1, HgssWorldBuilder.BiomeKind.size()): # Checks every non-Normal type sector independently.
        var axis_angle: float = _world.radial_sampler.get_biome_axis_angle(biome_kind) # Reads the authoritative evenly spaced sector axis.
        if previous_angle >= 0.0: # Skips spacing comparison before the second outer type.
            _check(absf((axis_angle - previous_angle) - RadialWorldFieldSampler.SECTOR_ANGLE) < 0.0001, "Outer biome axes are not evenly spaced") # Requires identical mean angular shares around the hub.
        previous_angle = axis_angle # Stores this axis for the next spacing comparison.
        var direction: Vector2 = Vector2(cos(axis_angle), sin(axis_angle)) # Builds the centre ray of this infinite type world.
        var near_cell: Vector2 = direction * (RadialWorldFieldSampler.CENTER_RADIUS_CELLS + 32.0) # Samples safely beyond the blobbed neutral boundary.
        var far_cell: Vector2 = direction * 10000.0 # Samples extremely far outward to prove the type region has no finite edge.
        _check(_world.radial_sampler.sample_biome(near_cell) == biome_kind, "Wrong inner radial biome on axis: %s" % biome_kind) # Requires the intended type immediately outside the hub.
        _check(_world.radial_sampler.sample_biome(far_cell) == biome_kind, "Radial biome does not continue indefinitely: %s" % biome_kind) # Requires the same type ten thousand cells outward along its centre ray.
    var negative_world: Vector3 = Vector3(-120.0, 0.0, -90.0) # Chooses a signed-coordinate sample outside the old finite grid assumptions.
    var negative_cell: Vector2i = _world.world_to_cell(negative_world) # Converts the negative world position through the radial world API.
    _check(negative_cell.x < 0 and negative_cell.y < 0, "Infinite world cell conversion rejected negative coordinates") # Requires unbounded signed logical cells.
    var hub: Vector3 = _world.get_nearest_walkable_world_position(Vector3.ZERO) # Uses practical central terrain as the navigation origin.
    for destination: Dictionary in _destinations: # Checks every radial destination through the local unbounded navigation service.
        var position: Vector3 = destination.get("position", Vector3.ZERO) # Reads the real fast-travel arrival position.
        var route: Array[Vector3] = HgssWorldNavigation.get_world_path(_world, hub, position) # Builds a route without a finite global navigation grid.
        _check(not route.is_empty(), "Unreachable radial destination: %s" % destination.get("landmark_name", "unknown")) # Detects an outer landmark disconnected by terrain slope.
    print("radial_topology_checked; resident_chunks=", _world.active_chunks.size(), "; center_radius_cells=", RadialWorldFieldSampler.CENTER_RADIUS_CELLS) # Reports useful streamed-world diagnostics.

func _start_arrival(index: int) -> void: # Moves the real player to one radial map destination for a physical landing check.
    _arrival_index = index # Stores the destination currently under test.
    if index >= _destinations.size(): # Handles missing destinations without indexing an empty list.
        return # Leaves the destination-count assertion to report the original failure.
    _player.global_position = _destinations[index].get("position", _player.global_position) # Uses the exact map fast-travel arrival position.
    _player.velocity = Vector3.ZERO # Matches the game's fast-travel velocity reset.

func _check_arrival() -> void: # Confirms streamed collision exists and agrees with radial terrain at every destination.
    if _arrival_index < 0 or _arrival_index >= _destinations.size(): # Guards setup failures before destination metadata exists.
        return # Avoids obscuring the original failure with a bounds error.
    var landmark_name: String = _destinations[_arrival_index].get("landmark_name", "unknown") # Identifies the destination in any failure report.
    var expected_position: Vector3 = _destinations[_arrival_index].get("position", _player.global_position) # Reads the expected grounded arrival position.
    var player_chunk: Vector2i = _world.world_to_chunk(_player.global_position) # Resolves the player's current streamed chunk after teleportation.
    _check(_world.active_chunks.has(player_chunk), "Fast travel did not stream destination chunk at %s" % landmark_name) # Requires the floor chunk to be resident before movement continues.
    _check(_player.is_on_floor(), "Player did not land at %s" % landmark_name) # Detects missing streamed collision beneath the actual CharacterBody3D.
    _check(absf(_player.global_position.y - expected_position.y) < 0.35, "Rendered and physical arrival heights disagree at %s" % landmark_name) # Detects mismatch between deterministic sampling and chunk collision.
    _check(_world.is_cell_walkable(_world.world_to_cell(_player.global_position)), "Player landed on impractical terrain at %s" % landmark_name) # Keeps map arrivals consistent with navigation slope policy.

func _check(condition: bool, message: String) -> void: # Collects failures without aborting remaining integration checks.
    if not condition: # Retains only failed invariants for the final report.
        _failures.append(message) # Preserves the actionable failure detail for final output.

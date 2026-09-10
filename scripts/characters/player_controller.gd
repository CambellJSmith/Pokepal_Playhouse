extends CharacterBody3D # Controls the player as a real 3D physics character.

@onready var visual: BillboardCharacterVisual = $player_visual as BillboardCharacterVisual # References the composed billboard renderer.

var move_speed: float = 4.0 # Controls the player's normal horizontal travel speed.
var sprint_speed: float = 7.0 # Controls the player's faster horizontal travel speed while sprint is held.
var ladder_climb_speed: float = 4.2 # Controls vertical traversal while the player is attached to a generated ladder.
var ground_acceleration: float = 24.0 # Controls how quickly horizontal movement reaches its target speed.
var ground_deceleration: float = 30.0 # Controls how quickly horizontal movement stops after input is released.
var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity")) # Uses the project's configured 3D gravity.
var nearby_ladder: Node3D # Caches the closest usable streamed ladder marker near the player.
var ladder_scan_remaining: float = 0.0 # Throttles semantic ladder-group scans so ordinary movement stays inexpensive.
var ladder_scan_interval: float = 0.10 # Keeps ladder acquisition responsive without searching the group every physics frame.

func _ready() -> void: # Places the player on a verified route beside the central landmark after terrain generation.
    var world: HgssWorldBuilder = get_tree().get_first_node_in_group(&"world_builder") as HgssWorldBuilder # Resolves the generated terrain service.
    if world != null: # Waits for a valid generated world before adjusting the spawn.
        var center: Vector2 = HgssWorldBuilder.BIOME_CENTERS[HgssWorldBuilder.BiomeKind.NORMAL] # Reads the central region anchor used by the active world service.
        global_position = world.get_nearest_walkable_world_position(Vector3(center.x * HgssWorldBuilder.TILE_SIZE, 0.0, (center.y + 7.0) * HgssWorldBuilder.TILE_SIZE)) # Starts on an actual walkable terrain triangle near the plaza.

func _physics_process(delta: float) -> void: # Applies movement, sprinting, ladder traversal, gravity, collision, and sprite animation each physics frame.
    var camera: Camera3D = get_viewport().get_camera_3d() # Reads the currently active 3D camera for camera-relative controls.
    if camera == null: # Guards startup frames where a camera is not yet active.
        return # Waits until the scene has an active camera before processing movement.
    var input_vector: Vector2 = Input.get_vector(&"StickLeft_West", &"StickLeft_East", &"StickLeft_North", &"StickLeft_South") # Reads the named left-stick movement actions.
    _update_nearby_ladder(delta) # Refreshes the closest climbable marker at a low fixed frequency.
    if _try_climb_ladder(input_vector, delta): # Gives explicit ladder traversal priority when the player is pressing vertically beside a ladder.
        visual.update_motion(Vector3(0.0, ladder_climb_speed * -input_vector.y, 0.0), camera) # Keeps the billboard animation responsive during vertical climbing.
        return # Skips ordinary ground physics while the ladder owns movement.
    var desired_direction: Vector3 = _get_camera_relative_direction(input_vector, camera) # Converts 2D input into the world's horizontal plane.
    var current_move_speed: float = sprint_speed if Input.is_action_pressed(&"Button_LeftStick") else move_speed # Selects sprint or normal speed from the named sprint action.
    var target_velocity: Vector3 = desired_direction * current_move_speed # Converts the desired direction into horizontal movement speed.
    var horizontal_rate: float = ground_acceleration if desired_direction != Vector3.ZERO else ground_deceleration # Selects acceleration while moving and deceleration while stopping.
    velocity.x = move_toward(velocity.x, target_velocity.x, horizontal_rate * delta) # Smoothly approaches the desired world-space X velocity.
    velocity.z = move_toward(velocity.z, target_velocity.z, horizontal_rate * delta) # Smoothly approaches the desired world-space Z velocity.
    if is_on_floor(): # Keeps the body snapped to walkable ground and ramps.
        velocity.y = -0.1 # Applies a small downward bias so floor contact remains stable.
    else: # Applies gravity whenever the character is airborne.
        velocity.y -= gravity * delta # Integrates vertical acceleration into the body's velocity.
    move_and_slide() # Moves the CharacterBody3D while resolving walls, slopes, and floor collisions.
    visual.update_motion(get_real_velocity(), camera) # Updates the billboard animation from the movement that actually occurred.

func _update_nearby_ladder(delta: float) -> void: # Finds the closest generated ladder at a bounded frequency instead of scanning every physics frame.
    ladder_scan_remaining -= delta # Advances the lightweight ladder-acquisition timer.
    if ladder_scan_remaining > 0.0 and is_instance_valid(nearby_ladder): # Reuses a still-valid nearby marker between scans.
        return # Avoids unnecessary group iteration while the cached ladder remains available.
    ladder_scan_remaining = ladder_scan_interval # Schedules the next semantic group scan.
    nearby_ladder = null # Clears the previous result before evaluating currently streamed ladders.
    var best_distance_squared: float = 3.24 # Limits acquisition to ladders within roughly one character-width of the player.
    for node: Node in get_tree().get_nodes_in_group(&"world_ladder"): # Examines only lightweight ladder markers maintained by the streamed ladder system.
        var ladder: Node3D = node as Node3D # Narrows the semantic group entry to its expected spatial node type.
        if ladder == null: # Guards unrelated nodes accidentally placed in the same group.
            continue # Skips malformed entries without affecting movement.
        var bottom_position: Vector3 = ladder.get_meta(&"bottom_position", ladder.global_position) # Reads the grounded lower ladder exit.
        var top_position: Vector3 = ladder.get_meta(&"top_position", ladder.global_position) # Reads the grounded upper ladder exit.
        var minimum_y: float = minf(bottom_position.y, top_position.y) - 0.8 # Extends the usable proximity range slightly below the first rung.
        var maximum_y: float = maxf(bottom_position.y, top_position.y) + 0.8 # Extends the usable proximity range slightly above the last rung.
        if global_position.y < minimum_y or global_position.y > maximum_y: # Rejects ladders whose vertical span does not overlap the player.
            continue # Prevents acquisition through floors or distant cliff layers.
        var horizontal_offset: Vector2 = Vector2(global_position.x - ladder.global_position.x, global_position.z - ladder.global_position.z) # Measures only horizontal proximity to the ladder face.
        var distance_squared: float = horizontal_offset.length_squared() # Avoids a square root during candidate comparison.
        if distance_squared < best_distance_squared: # Detects a closer usable ladder marker.
            best_distance_squared = distance_squared # Stores the improved proximity score.
            nearby_ladder = ladder # Caches the closest ladder for climb handling between scans.

func _try_climb_ladder(input_vector: Vector2, delta: float) -> bool: # Moves vertically along a nearby ladder when the player presses the vertical movement axis.
    if nearby_ladder == null or not is_instance_valid(nearby_ladder): # Requires a currently streamed ladder marker.
        return false # Leaves ordinary ground movement in control when no ladder is available.
    if absf(input_vector.y) < 0.20: # Requires deliberate forward or backward movement before attaching to the ladder.
        return false # Allows sideways movement beside a ladder without unwanted climbing.
    var bottom_position: Vector3 = nearby_ladder.get_meta(&"bottom_position", nearby_ladder.global_position) # Reads the lower walk-off point generated with the ladder.
    var top_position: Vector3 = nearby_ladder.get_meta(&"top_position", nearby_ladder.global_position) # Reads the upper walk-off point generated with the ladder.
    var climb_direction: float = -signf(input_vector.y) # Maps forward input to upward climbing and backward input to descending.
    var minimum_y: float = minf(bottom_position.y, top_position.y) # Resolves the lower vertical end independent of metadata ordering.
    var maximum_y: float = maxf(bottom_position.y, top_position.y) # Resolves the upper vertical end independent of metadata ordering.
    if global_position.y < minimum_y - 1.0 or global_position.y > maximum_y + 1.0: # Requires the player to be vertically adjacent to the ladder span.
        return false # Avoids snapping to ladders through unrelated terrain layers.
    velocity = Vector3.ZERO # Removes horizontal and gravity momentum while climbing owns the character.
    var target_horizontal: Vector2 = Vector2(nearby_ladder.global_position.x, nearby_ladder.global_position.z) # Resolves the ladder centre line in the horizontal plane.
    var current_horizontal: Vector2 = Vector2(global_position.x, global_position.z) # Reads the player's current horizontal position.
    var snapped_horizontal: Vector2 = current_horizontal.lerp(target_horizontal, minf(delta * 10.0, 1.0)) # Pulls the character smoothly onto the ladder without a visible teleport.
    global_position.x = snapped_horizontal.x # Applies the ladder-centering correction along world X.
    global_position.z = snapped_horizontal.y # Applies the ladder-centering correction along world Z.
    global_position.y += climb_direction * ladder_climb_speed * delta # Moves vertically along the ladder independently of cliff collision.
    if climb_direction > 0.0 and global_position.y >= maximum_y - 0.08: # Detects reaching the upper walk-off point while climbing upward.
        global_position = top_position # Places the character safely on the high side of the cliff.
        nearby_ladder = null # Releases ladder ownership so ordinary ground movement resumes immediately.
        ladder_scan_remaining = 0.0 # Forces a fresh proximity check after stepping onto the upper ledge.
    elif climb_direction < 0.0 and global_position.y <= minimum_y + 0.08: # Detects reaching the lower walk-off point while descending.
        global_position = bottom_position # Places the character safely on the low side of the cliff.
        nearby_ladder = null # Releases ladder ownership after leaving the bottom rung.
        ladder_scan_remaining = 0.0 # Forces a fresh proximity check after stepping away from the ladder.
    return true # Reports that ladder traversal consumed this physics frame.

func _get_camera_relative_direction(input_vector: Vector2, camera: Camera3D) -> Vector3: # Converts controller input into movement aligned with the visible camera axes.
    if input_vector.length_squared() <= 0.0004: # Detects a centered stick or released keyboard input.
        return Vector3.ZERO # Avoids unnecessary vector work when there is no movement request.
    var camera_right: Vector3 = camera.global_transform.basis.x # Reads the camera's screen-right direction in world space.
    camera_right.y = 0.0 # Projects the right axis onto the ground plane.
    camera_right = camera_right.normalized() # Normalizes the projected right axis before combining movement.
    var camera_forward: Vector3 = -camera.global_transform.basis.z # Reads the camera's view-forward direction in world space.
    camera_forward.y = 0.0 # Projects the forward axis onto the ground plane.
    camera_forward = camera_forward.normalized() # Normalizes the projected forward axis before combining movement.
    var direction: Vector3 = (camera_right * input_vector.x) + (camera_forward * -input_vector.y) # Combines stick axes into a camera-relative world direction.
    return direction.normalized() # Prevents diagonal input from moving faster than cardinal input.

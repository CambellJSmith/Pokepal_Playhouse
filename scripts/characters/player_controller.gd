extends CharacterBody3D # Controls the player as a real 3D physics character.

@onready var visual: BillboardCharacterVisual = $player_visual as BillboardCharacterVisual # References the composed billboard renderer.

var move_speed: float = 4.0 # Controls the player's normal horizontal travel speed.
var sprint_speed: float = 7.0 # Controls the player's faster horizontal travel speed while sprint is held.
var ground_acceleration: float = 24.0 # Controls how quickly horizontal movement reaches its target speed.
var ground_deceleration: float = 30.0 # Controls how quickly horizontal movement stops after input is released.
var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity")) # Uses the project's configured 3D gravity.

func _ready() -> void: # Places the player on a verified route beside the central landmark after terrain generation.
    var world: HgssWorldBuilder = get_tree().get_first_node_in_group(&"world_builder") as HgssWorldBuilder # Resolves the generated terrain service.
    if world != null: # Waits for a valid generated world before adjusting the spawn.
        var center: Vector2 = HgssWorldBuilder.BIOME_CENTERS[HgssWorldBuilder.BiomeKind.NORMAL] # Reads the central region anchor used by the active world service.
        global_position = world.get_nearest_walkable_world_position(Vector3(center.x * HgssWorldBuilder.TILE_SIZE, 0.0, (center.y + 7.0) * HgssWorldBuilder.TILE_SIZE)) # Starts on an actual walkable terrain triangle near the plaza.

func _physics_process(delta: float) -> void: # Applies camera-relative input, sprinting, gravity, collision movement, and sprite animation each physics frame.
    var camera: Camera3D = get_viewport().get_camera_3d() # Reads the currently active 3D camera for camera-relative controls.
    if camera == null: # Guards startup frames where a camera is not yet active.
        return # Waits until the scene has an active camera before processing movement.
    var input_vector: Vector2 = Input.get_vector(&"StickLeft_West", &"StickLeft_East", &"StickLeft_North", &"StickLeft_South") # Reads the named left-stick movement actions.
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

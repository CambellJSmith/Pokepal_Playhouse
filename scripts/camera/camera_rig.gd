extends Node3D # Controls a collision-aware orbit camera around the player.

const DEFAULT_YAW_DEGREES: float = 45.0 # Preserves the original diagonal starting view.
const DEFAULT_PITCH_DEGREES: float = -35.0 # Preserves the original downward starting tilt.
const MIN_PITCH_DEGREES: float = -82.0 # Allows a near top-down view without letting the camera flip beneath the world.
const MAX_PITCH_DEGREES: float = -8.0 # Allows a near-horizontal view while keeping the ground visible.
const MOUSE_ORBIT_SENSITIVITY: float = 0.004 # Converts captured mouse motion into smooth orbit rotation.
const CONTROLLER_YAW_SPEED: float = 1.9 # Sets right-stick horizontal orbit speed in radians per second.
const CONTROLLER_PITCH_SPEED: float = 1.55 # Keeps vertical stick movement slightly more controlled than yaw.
const MIN_SPRING_LENGTH: float = 4.0 # Prevents zooming so close that the camera intersects the character.
const MAX_SPRING_LENGTH: float = 20.0 # Keeps the player readable while allowing a wider exploration view.
const ZOOM_STEP: float = 1.0 # Changes camera distance by one world unit per mouse-wheel step.

@onready var spring_arm: SpringArm3D = %spring_arm # References the collision-aware arm that positions the camera.

var yaw: float = 0.0 # Stores unrestricted horizontal orbit rotation around the player.
var pitch: float = 0.0 # Stores clamped vertical camera tilt.
var mouse_orbit_active: bool = false # Tracks right-mouse drag state while the pointer is captured.

func _ready() -> void: # Initializes the orbit state and excludes the player body from spring-arm collision.
    yaw = deg_to_rad(DEFAULT_YAW_DEGREES)
    pitch = deg_to_rad(DEFAULT_PITCH_DEGREES)
    _apply_rotation()
    var parent_body: CollisionObject3D = get_parent() as CollisionObject3D
    if parent_body != null:
        spring_arm.add_excluded_object(parent_body.get_rid())

func _process(delta: float) -> void: # Applies continuous right-stick orbit while normal gameplay is active.
    if not _camera_controls_enabled():
        if mouse_orbit_active:
            _stop_mouse_orbit()
        return
    var orbit_input: Vector2 = Input.get_vector(&"StickRight_West", &"StickRight_East", &"StickRight_North", &"StickRight_South")
    if orbit_input.length_squared() <= 0.0004:
        return
    yaw = wrapf(yaw - orbit_input.x * CONTROLLER_YAW_SPEED * delta, -PI, PI)
    pitch -= orbit_input.y * CONTROLLER_PITCH_SPEED * delta
    pitch = clampf(pitch, deg_to_rad(MIN_PITCH_DEGREES), deg_to_rad(MAX_PITCH_DEGREES))
    _apply_rotation()

func _unhandled_input(event: InputEvent) -> void: # Handles mouse orbit and zoom without consuming normal movement actions.
    if event is InputEventMouseButton:
        var mouse_button: InputEventMouseButton = event as InputEventMouseButton
        if mouse_button.button_index == MOUSE_BUTTON_RIGHT:
            if mouse_button.pressed and _camera_controls_enabled():
                _start_mouse_orbit()
            elif not mouse_button.pressed:
                _stop_mouse_orbit()
            get_viewport().set_input_as_handled()
            return
        if mouse_button.pressed and _camera_controls_enabled():
            if mouse_button.button_index == MOUSE_BUTTON_WHEEL_UP:
                _change_zoom(-ZOOM_STEP)
                get_viewport().set_input_as_handled()
            elif mouse_button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
                _change_zoom(ZOOM_STEP)
                get_viewport().set_input_as_handled()
        return
    if event is InputEventMouseMotion and mouse_orbit_active and _camera_controls_enabled():
        var mouse_motion: InputEventMouseMotion = event as InputEventMouseMotion
        yaw = wrapf(yaw - mouse_motion.relative.x * MOUSE_ORBIT_SENSITIVITY, -PI, PI)
        pitch -= mouse_motion.relative.y * MOUSE_ORBIT_SENSITIVITY
        pitch = clampf(pitch, deg_to_rad(MIN_PITCH_DEGREES), deg_to_rad(MAX_PITCH_DEGREES))
        _apply_rotation()
        get_viewport().set_input_as_handled()

func _start_mouse_orbit() -> void: # Captures the pointer so one drag can rotate through a full horizontal revolution.
    mouse_orbit_active = true
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _stop_mouse_orbit() -> void: # Releases pointer capture when orbiting stops or another UI takes control.
    mouse_orbit_active = false
    if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _change_zoom(amount: float) -> void: # Adjusts desired spring-arm distance while preserving collision shortening.
    spring_arm.spring_length = clampf(spring_arm.spring_length + amount, MIN_SPRING_LENGTH, MAX_SPRING_LENGTH)

func _apply_rotation() -> void: # Applies yaw and pitch to the pivot that owns the collision-aware spring arm.
    rotation = Vector3(pitch, yaw, 0.0)

func _camera_controls_enabled() -> bool: # Prevents camera input while systems such as the world map freeze player gameplay.
    var parent_node: Node = get_parent()
    if parent_node == null:
        return true
    return parent_node.is_physics_processing()

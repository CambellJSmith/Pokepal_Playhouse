extends Node3D # Controls a collision-aware orbit camera around the player.

const DEFAULT_YAW_DEGREES: float = 45.0 # Preserves the original diagonal starting view.
const DEFAULT_PITCH_DEGREES: float = -28.0 # Frames nearby paths together with the landscape beyond.
const MIN_PITCH_DEGREES: float = -82.0 # Allows a near top-down view without letting the camera flip beneath the world.
const MAX_PITCH_DEGREES: float = -8.0 # Allows a near-horizontal view while keeping the ground visible.
const MOUSE_ORBIT_SENSITIVITY: float = 0.004 # Converts captured mouse motion into smooth orbit rotation.
const CONTROLLER_YAW_SPEED: float = 1.9 # Sets right-stick horizontal orbit speed in radians per second.
const CONTROLLER_PITCH_SPEED: float = 1.55 # Keeps vertical stick movement slightly more controlled than yaw.
const MIN_SPRING_LENGTH: float = 4.0 # Prevents zooming so close that the camera intersects the character.
const MAX_SPRING_LENGTH: float = 32.0 # Allows a wider view over the enlarged landscape.
const ZOOM_STEP: float = 1.0 # Changes camera distance by one world unit per mouse-wheel step.

@onready var spring_arm: SpringArm3D = %spring_arm # References the collision-aware arm that positions the camera.

var yaw: float = 0.0 # Stores unrestricted horizontal orbit rotation around the player.
var pitch: float = 0.0 # Stores clamped vertical camera tilt.
var mouse_orbit_active: bool = false # Tracks right-mouse drag state while the pointer is captured.

func _ready() -> void: # Initializes the orbit state and excludes the player body from spring-arm collision.
    yaw = deg_to_rad(DEFAULT_YAW_DEGREES) # Updates the wrapped horizontal orbit angle.
    pitch = deg_to_rad(DEFAULT_PITCH_DEGREES) # Updates vertical orbit within the allowed viewing range.
    _apply_rotation() # Applies the updated camera orientation.
    var parent_body: CollisionObject3D = get_parent() as CollisionObject3D # Reads the typed camera or input dependency for this operation.
    if parent_body != null: # Checks whether this camera input applies to active gameplay.
        spring_arm.add_excluded_object(parent_body.get_rid()) # Updates the stored camera input state.

func _process(delta: float) -> void: # Applies continuous right-stick orbit while normal gameplay is active.
    if not _camera_controls_enabled(): # Checks whether this camera input applies to active gameplay.
        if mouse_orbit_active: # Checks whether this camera input applies to active gameplay.
            _stop_mouse_orbit() # Updates the stored camera input state.
        return # Ends this input branch after handling its action.
    var orbit_input: Vector2 = Input.get_vector(&"StickRight_West", &"StickRight_East", &"StickRight_North", &"StickRight_South") # Reads the typed camera or input dependency for this operation.
    if orbit_input.length_squared() <= 0.0004: # Checks whether this camera input applies to active gameplay.
        return # Ends this input branch after handling its action.
    yaw = wrapf(yaw - orbit_input.x * CONTROLLER_YAW_SPEED * delta, -PI, PI) # Updates the wrapped horizontal orbit angle.
    pitch -= orbit_input.y * CONTROLLER_PITCH_SPEED * delta # Updates vertical orbit within the allowed viewing range.
    pitch = clampf(pitch, deg_to_rad(MIN_PITCH_DEGREES), deg_to_rad(MAX_PITCH_DEGREES)) # Updates vertical orbit within the allowed viewing range.
    _apply_rotation() # Applies the updated camera orientation.

func _unhandled_input(event: InputEvent) -> void: # Handles mouse orbit and zoom without consuming normal movement actions.
    if event is InputEventMouseButton: # Checks whether this camera input applies to active gameplay.
        var mouse_button: InputEventMouseButton = event as InputEventMouseButton # Reads the typed camera or input dependency for this operation.
        if mouse_button.button_index == MOUSE_BUTTON_RIGHT: # Checks whether this camera input applies to active gameplay.
            if mouse_button.pressed and _camera_controls_enabled(): # Checks whether this camera input applies to active gameplay.
                _start_mouse_orbit() # Updates the stored camera input state.
            elif not mouse_button.pressed: # Checks whether this camera input applies to active gameplay.
                _stop_mouse_orbit() # Updates the stored camera input state.
            get_viewport().set_input_as_handled() # Marks the camera input as handled.
            return # Ends this input branch after handling its action.
        if mouse_button.pressed and _camera_controls_enabled(): # Checks whether this camera input applies to active gameplay.
            if mouse_button.button_index == MOUSE_BUTTON_WHEEL_UP: # Checks whether this camera input applies to active gameplay.
                _change_zoom(-ZOOM_STEP) # Updates the stored camera input state.
                get_viewport().set_input_as_handled() # Marks the camera input as handled.
            elif mouse_button.button_index == MOUSE_BUTTON_WHEEL_DOWN: # Checks whether this camera input applies to active gameplay.
                _change_zoom(ZOOM_STEP) # Updates the stored camera input state.
                get_viewport().set_input_as_handled() # Marks the camera input as handled.
        return # Ends this input branch after handling its action.
    if event is InputEventMouseMotion and mouse_orbit_active and _camera_controls_enabled(): # Checks whether this camera input applies to active gameplay.
        var mouse_motion: InputEventMouseMotion = event as InputEventMouseMotion # Reads the typed camera or input dependency for this operation.
        yaw = wrapf(yaw - mouse_motion.screen_relative.x * MOUSE_ORBIT_SENSITIVITY, -PI, PI) # Updates the wrapped horizontal orbit angle.
        pitch -= mouse_motion.screen_relative.y * MOUSE_ORBIT_SENSITIVITY # Updates vertical orbit within the allowed viewing range.
        pitch = clampf(pitch, deg_to_rad(MIN_PITCH_DEGREES), deg_to_rad(MAX_PITCH_DEGREES)) # Updates vertical orbit within the allowed viewing range.
        _apply_rotation() # Applies the updated camera orientation.
        get_viewport().set_input_as_handled() # Marks the camera input as handled.

func _start_mouse_orbit() -> void: # Captures the pointer so one drag can rotate through a full horizontal revolution.
    mouse_orbit_active = true # Updates the stored camera input state.
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED # Synchronizes pointer capture with the camera drag state.

func _stop_mouse_orbit() -> void: # Releases pointer capture when orbiting stops or another UI takes control.
    mouse_orbit_active = false # Updates the stored camera input state.
    if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED: # Synchronizes pointer capture with the camera drag state.
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE # Synchronizes pointer capture with the camera drag state.

func _change_zoom(amount: float) -> void: # Adjusts desired spring-arm distance while preserving collision shortening.
    spring_arm.spring_length = clampf(spring_arm.spring_length + amount, MIN_SPRING_LENGTH, MAX_SPRING_LENGTH) # Applies the requested zoom within the exploration range.

func _apply_rotation() -> void: # Applies yaw and pitch to the pivot that owns the collision-aware spring arm.
    rotation = Vector3(pitch, yaw, 0.0) # Updates the stored camera input state.

func _camera_controls_enabled() -> bool: # Prevents camera input while systems such as the world map freeze player gameplay.
    var parent_node: Node = get_parent() # Reads the typed camera or input dependency for this operation.
    if parent_node == null: # Checks whether this camera input applies to active gameplay.
        return true # Updates the stored camera input state.
    return parent_node.is_physics_processing() # Matches camera controls to the player gameplay state.

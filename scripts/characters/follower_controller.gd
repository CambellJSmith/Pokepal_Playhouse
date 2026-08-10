extends CharacterBody3D # Moves a follower independently while reusing the same billboard visual component.

@onready var visual: BillboardCharacterVisual = $ditto_visual as BillboardCharacterVisual # References the composed billboard renderer.

var target: Node3D # Stores the character this follower tracks.
var move_speed: float = 3.7 # Controls normal follower travel speed.
var catchup_speed: float = 5.4 # Controls faster travel when the follower falls well behind.
var follow_distance: float = 1.35 # Defines the spacing maintained behind the target.
var catchup_distance: float = 4.0 # Defines when the follower switches to its faster catch-up speed.
var acceleration: float = 18.0 # Controls how smoothly the follower changes horizontal velocity.
var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity")) # Uses the project's configured 3D gravity.

func _ready() -> void: # Resolves the player without tightly coupling this scene to a specific node path.
    target = get_tree().get_first_node_in_group(&"player") as Node3D # Finds the active player through its semantic scene-tree group.

func _physics_process(delta: float) -> void: # Tracks the player using regular CharacterBody3D movement and collision handling.
    var camera: Camera3D = get_viewport().get_camera_3d() # Reads the active camera for matching directional sprite selection.
    if target == null or camera == null: # Guards scenes where the target or camera is temporarily unavailable.
        return # Waits until both required references exist.
    var to_target: Vector3 = target.global_position - global_position # Measures the world-space displacement to the tracked character.
    to_target.y = 0.0 # Keeps following decisions on the horizontal ground plane.
    var distance_squared: float = to_target.length_squared() # Measures follower spacing without an unnecessary square-root operation.
    var target_speed: float = catchup_speed if distance_squared > catchup_distance * catchup_distance else move_speed # Uses extra speed only when the follower has fallen substantially behind.
    var desired_velocity: Vector3 = Vector3.ZERO # Starts with a stationary target velocity inside the desired following radius.
    if distance_squared > follow_distance * follow_distance: # Moves only when spacing exceeds the preferred distance.
        desired_velocity = to_target.normalized() * target_speed # Aims directly toward the target at the appropriate travel speed.
    velocity.x = move_toward(velocity.x, desired_velocity.x, acceleration * delta) # Smoothly adjusts horizontal X velocity toward the follow target.
    velocity.z = move_toward(velocity.z, desired_velocity.z, acceleration * delta) # Smoothly adjusts horizontal Z velocity toward the follow target.
    if is_on_floor(): # Keeps the follower attached to the current floor or ramp.
        velocity.y = -0.1 # Applies a small downward bias for stable floor contact.
    else: # Applies gravity whenever the follower leaves the floor.
        velocity.y -= gravity * delta # Integrates vertical acceleration into the follower velocity.
    move_and_slide() # Moves the follower while respecting world collision and slopes.
    visual.update_motion(get_real_velocity(), camera) # Selects the correct camera-relative HGSS animation from actual motion.

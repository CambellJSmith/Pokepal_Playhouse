class_name BillboardCharacterVisual # Exposes the reusable billboard animation component to character controllers.
extends Node3D # Keeps rendering logic separate from movement and collision logic.

@onready var sprite: AnimatedSprite3D = %sprite # References the AnimatedSprite3D owned by this visual component.

var facing: StringName = &"down" # Stores the last camera-relative facing direction while the character is idle.

func set_sprite_frames(sprite_frames: SpriteFrames) -> void: # Replaces the current character animation library without changing movement code.
    sprite.sprite_frames = sprite_frames # Assigns the requested directional SpriteFrames resource to the renderer.
    facing = &"down" # Resets facing so newly assigned sprites start from a predictable front-facing state.
    sprite.play(&"idle_down") # Displays the front idle frame immediately after the sprite set changes.

func update_motion(world_motion: Vector3, camera: Camera3D) -> void: # Selects a directional walk or idle animation from world-space motion.
    var flat_motion: Vector3 = Vector3(world_motion.x, 0.0, world_motion.z) # Removes vertical physics motion from visual direction selection.
    var is_moving: bool = flat_motion.length_squared() > 0.0004 # Ignores tiny residual movement that would otherwise flicker the animation.
    if is_moving: # Updates facing only while the character is actually travelling across the ground.
        facing = _get_camera_relative_facing(flat_motion.normalized(), camera) # Converts world movement into one of the four available HGSS views.
    var animation_prefix: String = "walk_" if is_moving else "idle_" # Chooses the movement state while preserving the stored direction.
    var animation_name: StringName = StringName(animation_prefix + String(facing)) # Builds the matching SpriteFrames animation name.
    if sprite.sprite_frames == null or not sprite.sprite_frames.has_animation(animation_name): # Guards characters whose animation library has not been assigned yet.
        return # Avoids requesting an animation that is unavailable on the current sprite resource.
    if sprite.animation != animation_name: # Avoids restarting an animation that is already playing.
        sprite.play(animation_name) # Starts the required directional animation.

func face_direction(direction: StringName) -> void: # Forces a visual direction for stationary NPCs or scripted moments.
    if direction != &"up" and direction != &"down" and direction != &"left" and direction != &"right": # Rejects animation directions the visual resource does not contain.
        return # Keeps the existing facing when an invalid direction is supplied.
    facing = direction # Stores the valid direction for subsequent idle and walk animation selection.
    var animation_name: StringName = StringName("idle_" + String(facing)) # Builds the matching idle animation identifier.
    if sprite.sprite_frames == null or not sprite.sprite_frames.has_animation(animation_name): # Guards visuals whose sprite resource is not ready yet.
        return # Leaves the visual unchanged until the expected animation exists.
    sprite.play(animation_name) # Displays the matching idle frame immediately.

func _get_camera_relative_facing(flat_motion: Vector3, camera: Camera3D) -> StringName: # Converts a world-space direction into the closest camera-relative cardinal sprite view.
    var camera_right: Vector3 = camera.global_transform.basis.x # Reads the camera's horizontal screen-right axis in world space.
    camera_right.y = 0.0 # Projects the camera-right axis onto the ground plane.
    camera_right = camera_right.normalized() # Normalizes the projected axis before dot-product comparison.
    var camera_forward: Vector3 = -camera.global_transform.basis.z # Reads the direction the camera looks across the world.
    camera_forward.y = 0.0 # Projects the camera-forward axis onto the ground plane.
    camera_forward = camera_forward.normalized() # Normalizes the projected axis before dot-product comparison.
    var side_amount: float = flat_motion.dot(camera_right) # Measures movement toward screen-left or screen-right.
    var depth_amount: float = flat_motion.dot(camera_forward) # Measures movement away from or toward the camera.
    if absf(side_amount) > absf(depth_amount): # Chooses a horizontal sprite when horizontal screen motion is dominant.
        if side_amount > 0.0: # Detects motion toward screen-right.
            return &"right" # Uses the right-facing HGSS sprite.
        return &"left" # Uses the left-facing HGSS sprite.
    if depth_amount > 0.0: # Detects movement away from the camera into the scene.
        return &"up" # Uses the back-facing HGSS sprite.
    return &"down" # Uses the front-facing HGSS sprite for movement toward the camera.

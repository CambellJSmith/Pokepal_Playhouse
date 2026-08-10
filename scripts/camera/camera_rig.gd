extends Node3D # Configures the fixed HD-2D-style third-person camera rig.

@onready var spring_arm: SpringArm3D = %spring_arm # References the collision-aware spring arm below the camera pivot.

func _ready() -> void: # Excludes the parent character from camera collision when the rig is attached to a physics body.
    var parent_body: CollisionObject3D = get_parent() as CollisionObject3D # Attempts to treat the rig owner as a collision object.
    if parent_body != null: # Confirms the parent exposes a physics RID before adding an exclusion.
        spring_arm.add_excluded_object(parent_body.get_rid()) # Prevents the camera arm from colliding with the character it follows.

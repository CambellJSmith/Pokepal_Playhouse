class_name BottomAnchoredAnimatedSprite3D # Keeps an AnimatedSprite3D image bottom-center aligned to the node origin.
extends AnimatedSprite3D # Preserves the normal AnimatedSprite3D API used by the character visual controller.

var anchored_frames_id: int = 0 # Detects replacement SpriteFrames resources.
var anchored_animation: StringName = &"" # Caches the animation used for the current offset.
var anchored_frame: int = -1 # Caches the frame used for the current offset.

func _ready() -> void: # Removes the old world-space lift and anchors the initial image frame.
    position = Vector3.ZERO # Makes local Y zero the character's ground-contact point.
    _update_bottom_anchor() # Places the displayed image above that point.

func _process(_delta: float) -> void: # Handles animation frames whose image dimensions differ.
    _update_bottom_anchor() # Cached state prevents repeated texture-size work for unchanged frames.

func _update_bottom_anchor() -> void: # Moves the centered image upward by half its current pixel height.
    if sprite_frames == null or not sprite_frames.has_animation(animation):
        offset = Vector2.ZERO
        return
    if frame < 0 or frame >= sprite_frames.get_frame_count(animation):
        return
    var frames_id: int = int(sprite_frames.get_instance_id())
    if frames_id == anchored_frames_id and animation == anchored_animation and frame == anchored_frame:
        return
    var frame_texture: Texture2D = sprite_frames.get_frame_texture(animation, frame)
    if frame_texture == null:
        offset = Vector2.ZERO
    else:
        offset = Vector2(0.0, float(frame_texture.get_height()) * 0.5) # Positive Sprite3D Y offset lifts the centered image so its bottom edge lands on local Y zero.
    anchored_frames_id = frames_id
    anchored_animation = animation
    anchored_frame = frame

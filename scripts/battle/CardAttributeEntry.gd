extends Resource
class_name CardAttributeEntry

## Maps a particular SpriteFrames + frame_index to an attribute.
## This is designed to be edited in the inspector.

@export var sprite_frames: SpriteFrames
@export var frame_index: int = 0
@export_enum("air", "water", "fire") var attribute: String = "fire"


extends Resource
class_name AttributeConfig

## AttributeConfig
## - Holds the editable mapping from (SpriteFrames, frame_index) -> attribute
## - Holds the editable matchup rules (what beats what)

## List of mapping entries editable in the inspector.
## Each entry should be a CardAttributeEntry resource.
@export var entries: Array = []

## Rules: key beats value (e.g. "air" beats "water").
@export var beats: Dictionary = {
	"air": "water",
	"water": "fire",
	"fire": "air",
}

func get_attribute(sprite_frames: SpriteFrames, frame_index: int) -> String:
	if sprite_frames == null:
		return "unknown"
	
	for e in entries:
		if e == null:
			continue
		# Avoid relying on CardAttributeEntry being in global scope at parse time.
		var esf: SpriteFrames = e.get("sprite_frames") if e is Object else null
		var eidx: int = int(e.get("frame_index")) if e is Object else 0
		var eattr: String = String(e.get("attribute")) if e is Object else "unknown"
		if esf == sprite_frames and eidx == frame_index:
			return eattr
	
	return "unknown"

## Returns:
## - "player" if a beats b
## - "opponent" if b beats a
## - "tie" otherwise
func compare(a: String, b: String) -> String:
	if a == "unknown" or b == "unknown":
		return "tie"
	if a == b:
		return "tie"
	
	var a_beats = beats.get(a, null)
	if a_beats == b:
		return "player"
	
	var b_beats = beats.get(b, null)
	if b_beats == a:
		return "opponent"
	
	return "tie"


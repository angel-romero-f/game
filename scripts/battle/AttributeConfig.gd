extends Resource
class_name AttributeConfig

## AttributeConfig
## - Derives card attributes from filename convention: {race}_{attribute}_cards.pxo
## - Holds the editable matchup rules (what beats what)
##
## Naming convention:
##   elf_fire_cards.pxo  -> race: "elf",  attribute: "fire"
##   infernal_water_cards.pxo -> race: "infernal", attribute: "water"
##
## All frames within a file share the same race and attribute.

## Valid attributes for cards.
const VALID_ATTRIBUTES: Array[String] = ["air", "water", "fire"]

## Rules: key beats value (e.g. "air" beats "water").
@export var beats: Dictionary = {
	"air": "water",
	"water": "fire",
	"fire": "air",
}


## Returns the attribute parsed from the SpriteFrames filename.
## Format expected: {race}_{attribute}_cards.pxo or {race}_{attribute}.pxo
## The frame_index is ignored since all frames share the same attribute.
func get_attribute(sprite_frames: SpriteFrames, _frame_index: int = 0) -> String:
	if sprite_frames == null:
		return "unknown"
	
	var path := sprite_frames.resource_path
	if path.is_empty():
		return "unknown"
	
	var filename := path.get_file().get_basename()  # e.g., "elf_fire_cards"
	var parts := filename.to_lower().split("_")
	
	# Format: {race}_{attribute}_cards or {race}_{attribute}
	if parts.size() >= 2:
		var attribute := parts[1]  # Second part is the attribute
		if attribute in VALID_ATTRIBUTES:
			return attribute
	
	return "unknown"


## Returns the race parsed from the SpriteFrames filename.
## Format expected: {race}_{attribute}_cards.pxo or {race}_{attribute}.pxo
func get_race(sprite_frames: SpriteFrames) -> String:
	if sprite_frames == null:
		return "unknown"
	
	var path := sprite_frames.resource_path
	if path.is_empty():
		return "unknown"
	
	var filename := path.get_file().get_basename()  # e.g., "elf_fire_cards"
	var parts := filename.to_lower().split("_")
	
	if parts.size() >= 1:
		return parts[0]  # First part is the race
	
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

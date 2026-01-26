@tool
extends Node2D

## CardSlot - A stationary slot that can display images from .pxo files
## Cards can snap into slots when dragged nearby

## The texture to display on the slot. Set this in the inspector.
## You can use either a Texture2D or a SpriteFrames (.pxo file).
@export var slot_texture: Texture2D:
	set(value):
		_slot_texture_backing = value
		if value != null:
			_slot_sprite_frames_backing = null
		_update_texture()
	get:
		return _slot_texture_backing

## The sprite frames (.pxo file) to display on the slot. 
## If set, this takes priority over slot_texture.
## The first frame of the "default" animation will be used.
@export var slot_sprite_frames: SpriteFrames:
	set(value):
		_slot_sprite_frames_backing = value
		if value != null:
			_slot_texture_backing = null
		_update_texture()
	get:
		return _slot_sprite_frames_backing

## The frame index to use from the sprite frames (if using .pxo file)
@export var frame_index: int = 0:
	set(value):
		frame_index = value
		_update_texture()

## The animation name to use from the sprite frames (if using .pxo file)
@export var animation_name: String = "default":
	set(value):
		animation_name = value
		_update_texture()

## The snap distance - how close a card needs to be to snap to this slot
@export var snap_distance: float = 100.0

## Whether this slot can snap cards. Toggle this off to disable snapping for this slot.
@export var can_snap: bool = true

## Whether this slot currently has a card snapped to it
var has_card: bool = false
var snapped_card: Node2D = null

signal card_snapped(card: Node2D)
signal card_unsnapped(card: Node2D)

var _slot_texture_backing: Texture2D
var _slot_sprite_frames_backing: SpriteFrames

@onready var slot_image: Sprite2D = $SlotImg

func _ready():
	# Set the initial texture if one was assigned in the editor
	if Engine.is_editor_hint():
		_update_texture()
	else:
		_update_texture()

func _enter_tree():
	# Also update in editor when entering the tree
	if Engine.is_editor_hint():
		_update_texture()

func _update_texture():
	# In editor, try to get nodes if they're not ready yet
	if Engine.is_editor_hint() and not slot_image:
		slot_image = get_node_or_null("SlotImg") as Sprite2D
	
	if not slot_image:
		return
	
	var texture: Texture2D = null
	
	if _slot_sprite_frames_backing:
		# Use sprite frames (.pxo file)
		if _slot_sprite_frames_backing.has_animation(animation_name):
			var frames = _slot_sprite_frames_backing.get_frame_count(animation_name)
			if frames > 0 and frame_index < frames:
				texture = _slot_sprite_frames_backing.get_frame_texture(animation_name, frame_index)
				slot_image.texture = texture
	elif _slot_texture_backing:
		# Use regular texture
		texture = _slot_texture_backing
		slot_image.texture = _slot_texture_backing

func get_snap_position() -> Vector2:
	"""Returns the position where cards should snap to (center of slot)."""
	return global_position

func can_snap_cards() -> bool:
	"""Returns whether this slot can snap cards."""
	# Default to true if can_snap is null or not set
	if can_snap == null:
		return true
	return can_snap

func is_card_nearby(card_pos: Vector2) -> bool:
	"""Checks if a card position is within snap distance of this slot."""
	# Check can_snap - if null, default to true
	if can_snap == false:
		return false  # Slot snapping is disabled
	var distance = card_pos.distance_to(global_position)
	return distance <= snap_distance

func snap_card(card: Node2D) -> bool:
	"""Snaps a card to this slot. Returns true if successful."""
	# Check can_snap - if null, default to true
	if can_snap == false:
		return false  # Snapping is disabled for this slot
	if has_card:
		return false  # Slot already occupied
	
	has_card = true
	snapped_card = card
	
	# Move card to slot center
	card.global_position = global_position
	
	card_snapped.emit(card)
	return true

func unsnap_card():
	"""Removes the card from this slot."""
	if snapped_card:
		var card = snapped_card
		snapped_card = null
		has_card = false
		card_unsnapped.emit(card)

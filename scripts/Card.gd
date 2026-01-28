@tool
extends Node2D

## The texture to display on the card. Set this in the inspector.
## You can use either a Texture2D or a SpriteFrames (.pxo file).
@export var card_texture: Texture2D:
	set(value):
		_card_texture_backing = value
		if value != null:
			_card_sprite_frames_backing = null
		_update_texture()
	get:
		return _card_texture_backing

## The sprite frames (.pxo file) to display on the card. 
## If set, this takes priority over card_texture.
## The first frame of the "default" animation will be used.
@export var card_sprite_frames: SpriteFrames:
	set(value):
		_card_sprite_frames_backing = value
		if value != null:
			_card_texture_backing = null
		_update_texture()
	get:
		return _card_sprite_frames_backing

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

## [READ ONLY] The current size of the card image (read-only, for editor reference)
@export var card_size: Vector2:
	get:
		return _get_card_size()

var _card_texture_backing: Texture2D
var _card_sprite_frames_backing: SpriteFrames

@onready var card_image: Sprite2D = $Card_Image
@onready var card_collision_shape: CollisionShape2D = $Card_Collision/Card_Area

func _ready():
	# Set the initial texture if one was assigned in the editor
	_update_texture()

func _enter_tree():
	# Also update in editor when entering the tree
	if Engine.is_editor_hint():
		_update_texture()

func _update_texture():
	# In editor, try to get nodes if they're not ready yet
	if Engine.is_editor_hint() and not card_image:
		card_image = get_node_or_null("Card_Image") as Sprite2D
		card_collision_shape = get_node_or_null("Card_Collision/Card_Area") as CollisionShape2D
	
	if not card_image:
		return
	
	var texture: Texture2D = null
	
	if _card_sprite_frames_backing:
		# Use sprite frames (.pxo file)
		if _card_sprite_frames_backing.has_animation(animation_name):
			var frames = _card_sprite_frames_backing.get_frame_count(animation_name)
			if frames > 0 and frame_index < frames:
				texture = _card_sprite_frames_backing.get_frame_texture(animation_name, frame_index)
				card_image.texture = texture
	elif _card_texture_backing:
		# Use regular texture
		texture = _card_texture_backing
		card_image.texture = _card_texture_backing
	
	# Update collision area size based on texture
	if texture and card_collision_shape:
		_update_collision_size(texture)
	
	# Queue redraw for editor visualization
	if Engine.is_editor_hint():
		queue_redraw()

func _update_collision_size(texture: Texture2D):
	"""Updates the collision shape to match the card image size."""
	if not card_collision_shape or not card_image:
		return
	
	var shape = card_collision_shape.shape as RectangleShape2D
	if not shape:
		return
	
	# Get the texture size
	var texture_size = texture.get_size()
	
	# Account for the Sprite2D's scale
	# -Vector2(0.4,0) is a manual adjustment for aestetics
	var scaled_size = texture_size * (card_image.scale-Vector2(0.4,0))
	
	# Update the collision shape size
	shape.size = scaled_size

func _get_card_size() -> Vector2:
	"""Returns the current size of the card image."""
	# Try to get size from card_image if available
	if card_image and card_image.texture:
		var texture_size = card_image.texture.get_size()
		return texture_size * card_image.scale
	
	# Fallback: try to get texture from backing variables
	var texture: Texture2D = null
	if _card_sprite_frames_backing:
		if _card_sprite_frames_backing.has_animation(animation_name):
			var frames = _card_sprite_frames_backing.get_frame_count(animation_name)
			if frames > 0 and frame_index < frames:
				texture = _card_sprite_frames_backing.get_frame_texture(animation_name, frame_index)
	elif _card_texture_backing:
		texture = _card_texture_backing
	
	if texture:
		var texture_size = texture.get_size()
		# Try to get scale from card_image if available, otherwise use (1, 1)
		var image_scale = card_image.scale if card_image else Vector2.ONE
		return texture_size * image_scale
	
	return Vector2.ZERO

func _draw():
	"""Draws a visual outline in the editor to show card bounds."""
	if not Engine.is_editor_hint():
		return
	
	var size = _get_card_size()
	if size == Vector2.ZERO:
		return
	
	# Get the card_image position relative to this node
	var image_pos = Vector2.ZERO
	if card_image:
		image_pos = card_image.position
	
	# Calculate the rect centered on the card_image position
	var rect = Rect2(image_pos - size / 2.0, size)
	
	# Draw a semi-transparent rectangle outline
	draw_rect(rect, Color.CYAN, false, 2.0)
	
	# Draw size label above the card
	var font = ThemeDB.fallback_font
	var font_size = ThemeDB.fallback_font_size
	var label_text = "%.0f x %.0f" % [size.x, size.y]
	var label_size = font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var label_pos = image_pos + Vector2(-label_size.x / 2.0, -size.y / 2.0 - label_size.y - 5)
	draw_string(font, label_pos, label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.CYAN)

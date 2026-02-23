extends Node

## CardEnlargeOverlay — Shows an enlarged card (by path + frame) with dark overlay.
## Used by GameIntro (claim panel slots/hand, hand display). Click overlay to close.
## Similar behavior to CardManager double-click enlarge in the card battle scene.

var _overlay_layer: CanvasLayer = null
var _overlay_container: Control = null
var _darkening: ColorRect = null
var _card_texture_rect: TextureRect = null

const OVERLAY_LAYER := 100
const ENLARGED_CARD_MAX_SIZE := Vector2(400, 560)
const CARD_OFFSET_RIGHT := 80  # Pixels to shift the card to the right from center


func show_enlarged_card(card_path: String, frame: int) -> void:
	if card_path.is_empty():
		return
	close_overlay()
	var viewport := get_viewport()
	if not viewport:
		return
	var view_size := viewport.get_visible_rect().size
	_overlay_layer = CanvasLayer.new()
	_overlay_layer.layer = OVERLAY_LAYER
	_overlay_layer.name = "CardEnlargeOverlayLayer"
	_overlay_container = Control.new()
	_overlay_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay_container.size = view_size
	_overlay_container.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay_container.gui_input.connect(_on_overlay_input)
	_darkening = ColorRect.new()
	_darkening.color = Color(0, 0, 0, 0.7)
	_darkening.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_darkening.size = view_size
	_darkening.mouse_filter = Control.MOUSE_FILTER_STOP
	_darkening.gui_input.connect(_on_overlay_input)
	_overlay_container.add_child(_darkening)
	var center := CenterContainer.new()
	center.set_custom_minimum_size(view_size)
	center.size = view_size
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", CARD_OFFSET_RIGHT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_texture_rect = TextureRect.new()
	_card_texture_rect.custom_minimum_size = ENLARGED_CARD_MAX_SIZE
	_card_texture_rect.size = ENLARGED_CARD_MAX_SIZE
	_card_texture_rect.expand_mode = TextureRect.EXPAND_FIT_HEIGHT_PROPORTIONAL
	_card_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_card_texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(card_path):
		var sf: SpriteFrames = load(card_path) as SpriteFrames
		if sf and sf.has_animation("default"):
			var fc := sf.get_frame_count("default")
			if frame >= 0 and frame < fc:
				_card_texture_rect.texture = sf.get_frame_texture("default", frame)
	margin.add_child(_card_texture_rect)
	center.add_child(margin)
	_overlay_container.add_child(center)
	_overlay_layer.add_child(_overlay_container)
	add_child(_overlay_layer)


func _on_overlay_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			close_overlay()
			get_viewport().set_input_as_handled()


func close_overlay() -> void:
	if _overlay_layer and is_instance_valid(_overlay_layer):
		if _overlay_layer.get_parent() == self:
			remove_child(_overlay_layer)
		_overlay_layer.queue_free()
	_overlay_layer = null
	_overlay_container = null
	_darkening = null
	_card_texture_rect = null

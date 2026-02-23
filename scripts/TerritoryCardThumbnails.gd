extends Node

## TerritoryCardThumbnails
## Renders small card thumbnails (up to 3 slots) inside/near a TerritoryNode.
## Created at runtime by TerritorySystemUI; one instance per TerritoryNode.
## Security rule: only local player sees face of THEIR own cards. Enemies always see backs.

const THUMB_W: float = 32.0
const THUMB_H: float = 45.0
const THUMB_SPACING: float = 4.0
const CARDBACK_PATH := "res://assets/cardback.pxo"
const PIXEL_FONT_PATH := "res://fonts/m5x7.ttf"

var _territory_node: TerritoryNode = null
var _territory_id: int = -1
var _local_player_id: Variant = null
var _thumb_controls: Array = []

## Pre-loaded card-back texture (shared across instances)
static var _cardback_texture: Texture2D = null

func setup(territory_node: TerritoryNode, territory_id: int, local_player_id: Variant) -> void:
	_territory_node = territory_node
	_territory_id = territory_id
	_local_player_id = local_player_id
	_load_cardback_texture()
	refresh()

func _load_cardback_texture() -> void:
	if _cardback_texture != null:
		return
	if ResourceLoader.exists(CARDBACK_PATH):
		var sf := load(CARDBACK_PATH) as SpriteFrames
		if sf and sf.has_animation("default") and sf.get_frame_count("default") > 0:
			_cardback_texture = sf.get_frame_texture("default", 0)

## Called whenever territory claim state changes — rebuilds thumbnails.
func refresh() -> void:
	_clear_thumbs()
	if _territory_id < 0 or not _territory_node:
		return

	var tcs: Node = _territory_node.get_node_or_null("/root/TerritoryClaimState")
	if not tcs:
		return

	var is_claimed: bool = tcs.call("is_claimed", _territory_id)
	if not is_claimed:
		return

	var owner_id: Variant = tcs.call("get_owner_id", _territory_id)
	var cards: Array = tcs.call("get_cards", _territory_id)
	var is_mine: bool = (_local_player_id != null and owner_id != null
			and int(owner_id) == int(_local_player_id))

	# Count non-null cards
	var slot_count := 0
	for c in cards:
		if c != null:
			slot_count += 1
	if slot_count == 0:
		return

	# Use center of the TerritoryNode's bounding box (size is set to contain the polygon)
	var cx := _territory_node.size.x * 0.5
	var cy := _territory_node.size.y * 0.5

	# Place thumbnails centered horizontally, just above the center
	var total_w := slot_count * THUMB_W + (slot_count - 1) * THUMB_SPACING
	var start_x := cx - total_w * 0.5
	# Position so thumbs are centered vertically at cy (top of thumb = cy - THUMB_H/2)
	var thumb_y := cy - THUMB_H * 0.5 - 4.0

	var slot_index := 0
	for card_data in cards:
		if card_data == null:
			continue
		var thumb := _create_thumb(card_data, is_mine)
		thumb.position = Vector2(start_x + slot_index * (THUMB_W + THUMB_SPACING), thumb_y)
		_territory_node.add_child(thumb)
		_thumb_controls.append(thumb)
		slot_index += 1

	print("[CardThumbnails] Territory %d: %d cards (mine=%s)" % [_territory_id, slot_count, str(is_mine)])

func _create_thumb(card_data: Dictionary, is_mine: bool) -> Control:
	var container := Control.new()
	container.custom_minimum_size = Vector2(THUMB_W, THUMB_H)
	container.size = Vector2(THUMB_W, THUMB_H)
	container.mouse_filter = Control.MOUSE_FILTER_STOP

	# Set z_index so thumbs render on top of territory polygons
	container.z_index = 2

	# Load texture
	var tex: Texture2D = null
	if is_mine:
		var path: String = card_data.get("path", "")
		var frame: int = int(card_data.get("frame", 0))
		if path != "" and ResourceLoader.exists(path):
			var sf := load(path) as SpriteFrames
			if sf and sf.has_animation("default"):
				var fc := sf.get_frame_count("default")
				if frame >= 0 and frame < fc:
					tex = sf.get_frame_texture("default", frame)
	else:
		tex = _cardback_texture

	# TextureRect to show the card — flip_v to match Sprite2D orientation used throughout game
	var tex_rect := TextureRect.new()
	tex_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	tex_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tex_rect.flip_v = true  # Match Sprite2D rendering direction used in the rest of the game

	if tex:
		tex_rect.texture = tex
	else:
		# Fallback: solid dark rect
		var fallback := ColorRect.new()
		fallback.set_anchors_preset(Control.PRESET_FULL_RECT)
		fallback.color = Color(0.15, 0.15, 0.25, 0.85)
		fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
		container.add_child(fallback)

	container.add_child(tex_rect)

	# Thin white border
	var border := Panel.new()
	border.set_anchors_preset(Control.PRESET_FULL_RECT)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.set_border_width_all(1)
	style.border_color = Color(1.0, 1.0, 1.0, 0.6)
	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 2
	style.corner_radius_bottom_left = 2
	style.corner_radius_bottom_right = 2
	border.add_theme_stylebox_override("panel", style)
	container.add_child(border)

	# Double-click to enlarge
	container.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.double_click and mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
				_on_thumb_double_clicked(container, card_data, is_mine)
	)

	return container

func _on_thumb_double_clicked(thumb: Control, card_data: Dictionary, is_mine: bool) -> void:
	if is_mine:
		var path: String = card_data.get("path", "")
		var frame: int = int(card_data.get("frame", 0))
		if path != "" and CardEnlargeOverlay:
			CardEnlargeOverlay.show_enlarged_card(path, frame)
	else:
		if CARDBACK_PATH != "" and CardEnlargeOverlay:
			CardEnlargeOverlay.show_enlarged_card(CARDBACK_PATH, 0)

func _clear_thumbs() -> void:
	for t in _thumb_controls:
		if is_instance_valid(t):
			t.queue_free()
	_thumb_controls.clear()

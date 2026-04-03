extends Node

## TurnOrderBarUI — Mario Party-style bottom bar showing turn order, character sprites, names, and card counts.
## Programmatic component: created with .new(), receives parent Control via initialize().

const UI_FONT := preload("res://fonts/m5x7.ttf")
const CARDBACK_PATH := "res://assets/cardback.pxo"
const TERRITORY_ICON_PATH := "res://assets/territory_indicator.pxo"

const SPRITE_SIZE := Vector2(48, 48)
const SLOT_FIXED_WIDTH := 140.0
const SPRITE_ROW_HEIGHT := 56.0
const NAME_PANEL_HEIGHT := 26.0
const HIGHLIGHT_BORDER := Color(1.0, 0.82, 0.1, 1.0)
const DEFAULT_NAME_BG := Color(0.22, 0.22, 0.26, 1.0)
const ACTIVE_NAME_BG := Color(0.35, 0.3, 0.08, 1.0)
const SPRITE_ROW_BG := Color(0.12, 0.12, 0.16, 0.5)
const ACTIVE_SPRITE_BG := Color(0.22, 0.2, 0.06, 0.7)
const INACTIVE_MODULATE := Color(0.7, 0.7, 0.7, 1.0)

const LOCAL_INDICATOR_SPRITE_SIZE := Vector2(52, 52)
const LOCAL_INDICATOR_BG := Color(0.1, 0.1, 0.14, 0.8)

var _parent_control: Control
var _bar_container: HBoxContainer
var _local_indicator: HBoxContainer
var _player_slots: Dictionary = {}
var _card_icon_texture: Texture2D
var _territory_icon_texture: Texture2D
var _current_highlight_id: int = -1


func initialize(parent: Control) -> void:
	_parent_control = parent
	_load_card_icon()
	_load_territory_icon()
	_build_bar()
	_build_local_indicator()


func _load_card_icon() -> void:
	var frames: SpriteFrames = load(CARDBACK_PATH)
	if frames and frames.has_animation("default") and frames.get_frame_count("default") > 0:
		_card_icon_texture = frames.get_frame_texture("default", 0)


func _load_territory_icon() -> void:
	var frames: SpriteFrames = load(TERRITORY_ICON_PATH)
	if frames and frames.has_animation("default") and frames.get_frame_count("default") > 0:
		_territory_icon_texture = frames.get_frame_texture("default", 0)


func _build_bar() -> void:
	_bar_container = HBoxContainer.new()
	_bar_container.name = "TurnOrderBar"
	_bar_container.visible = false
	_bar_container.anchor_left = 0.5
	_bar_container.anchor_right = 0.5
	_bar_container.anchor_top = 1.0
	_bar_container.anchor_bottom = 1.0
	_bar_container.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_bar_container.offset_top = -110.0
	_bar_container.offset_bottom = -4.0
	_bar_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_bar_container.add_theme_constant_override("separation", 10)
	_bar_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_parent_control.add_child(_bar_container)


func _build_local_indicator() -> void:
	_local_indicator = HBoxContainer.new()
	_local_indicator.name = "LocalPlayerIndicator"
	_local_indicator.visible = false
	_local_indicator.anchor_left = 0.0
	_local_indicator.anchor_top = 0.0
	_local_indicator.offset_left = 10.0
	_local_indicator.offset_top = 10.0
	_local_indicator.add_theme_constant_override("separation", 6)
	_local_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_parent_control.add_child(_local_indicator)


func _populate_local_indicator() -> void:
	for child in _local_indicator.get_children():
		child.queue_free()

	var local_player: Dictionary = {}
	for p in App.game_players:
		if p.get("is_local", false):
			local_player = p
			break
	if local_player.is_empty():
		return

	var race: String = local_player.get("race", "Elf")
	var player_name: String = local_player.get("name", "Player")

	# Background panel
	var panel := PanelContainer.new()
	var bg := StyleBoxFlat.new()
	bg.bg_color = LOCAL_INDICATOR_BG
	bg.set_corner_radius_all(6)
	bg.content_margin_left = 6
	bg.content_margin_right = 10
	bg.content_margin_top = 4
	bg.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", bg)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(hbox)

	# Character sprite
	var sprite := TextureRect.new()
	var texture = load(App.get_race_texture_path(race))
	if texture:
		sprite.texture = texture
	sprite.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sprite.custom_minimum_size = LOCAL_INDICATOR_SPRITE_SIZE
	sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(sprite)

	# Player name
	var name_label := Label.new()
	name_label.text = player_name
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.add_theme_font_override("font", UI_FONT)
	name_label.add_theme_font_size_override("font_size", 24)
	name_label.add_theme_color_override("font_color", App.get_race_color(race))
	name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	name_label.add_theme_constant_override("outline_size", 3)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(name_label)

	_local_indicator.add_child(panel)
	_local_indicator.visible = true


func build_turn_order(turn_order: Array) -> void:
	for child in _bar_container.get_children():
		child.queue_free()
	_player_slots.clear()
	_current_highlight_id = -1

	# Seed card counts if not yet populated
	var local_count := App.player_card_collection.size()
	for p in turn_order:
		var pid: int = int(p.get("id", -1))
		if not PhaseController.player_card_counts.has(pid):
			PhaseController.player_card_counts[pid] = local_count

	for i in range(turn_order.size()):
		var player: Dictionary = turn_order[i]
		var slot := _create_player_slot(player, i)
		_bar_container.add_child(slot)

	_bar_container.visible = true
	_populate_local_indicator()

	update_territory_counts()

	if turn_order.size() > 0:
		highlight_current_turn(int(turn_order[0].get("id", -1)))


func clear_highlight() -> void:
	_current_highlight_id = -1
	for pid in _player_slots:
		var slot_data: Dictionary = _player_slots[pid]
		var name_bg: StyleBoxFlat = slot_data.get("name_bg")
		var sprite_bg: StyleBoxFlat = slot_data.get("sprite_bg")
		var slot_root: VBoxContainer = slot_data.get("slot_root")
		var race_color: Color = slot_data.get("race_color", Color.WHITE)
		if name_bg:
			name_bg.bg_color = _darken_color(race_color, 0.45)
			name_bg.border_color = Color(0.3, 0.3, 0.35, 1.0)
			name_bg.set_border_width_all(1)
		if sprite_bg:
			sprite_bg.bg_color = SPRITE_ROW_BG
			sprite_bg.border_color = Color(0.2, 0.2, 0.25, 0.0)
			sprite_bg.set_border_width_all(0)
		if slot_root:
			slot_root.modulate = Color.WHITE


func highlight_current_turn(player_id: int) -> void:
	if _current_highlight_id == player_id:
		return
	_current_highlight_id = player_id

	for pid in _player_slots:
		var slot_data: Dictionary = _player_slots[pid]
		var name_bg: StyleBoxFlat = slot_data.get("name_bg")
		var sprite_bg: StyleBoxFlat = slot_data.get("sprite_bg")
		var slot_root: VBoxContainer = slot_data.get("slot_root")
		var race_color: Color = slot_data.get("race_color", Color.WHITE)
		var is_active: bool = (pid == player_id)

		if name_bg:
			if is_active:
				name_bg.bg_color = _darken_color(race_color, 0.65)
				name_bg.border_color = HIGHLIGHT_BORDER
				name_bg.set_border_width_all(2)
			else:
				name_bg.bg_color = _darken_color(race_color, 0.45)
				name_bg.border_color = Color(0.3, 0.3, 0.35, 1.0)
				name_bg.set_border_width_all(1)

		if sprite_bg:
			if is_active:
				sprite_bg.bg_color = ACTIVE_SPRITE_BG
				sprite_bg.border_color = HIGHLIGHT_BORDER
				sprite_bg.set_border_width_all(2)
			else:
				sprite_bg.bg_color = SPRITE_ROW_BG
				sprite_bg.border_color = Color(0.2, 0.2, 0.25, 0.0)
				sprite_bg.set_border_width_all(0)

		if slot_root:
			slot_root.modulate = Color.WHITE if is_active else INACTIVE_MODULATE


func update_card_count() -> void:
	for pid in _player_slots:
		var slot_data: Dictionary = _player_slots[pid]
		var card_label: Label = slot_data.get("card_label")
		if not card_label:
			continue
		var count: int = PhaseController.player_card_counts.get(pid, -1)
		if count >= 0:
			card_label.text = str(count)
		else:
			card_label.text = str(App.player_card_collection.size())


func update_territory_counts() -> void:
	for pid in _player_slots:
		var slot_data: Dictionary = _player_slots[pid]
		var territory_label: Label = slot_data.get("territory_label")
		if not territory_label:
			continue
		var count: int = _get_player_territory_count(pid)
		territory_label.text = str(count)


func _get_player_territory_count(player_id: int) -> int:
	var tcs: Node = get_node_or_null("/root/TerritoryClaimState")
	if not tcs:
		return 0
	var claims_dict: Variant = tcs.get("claims")
	if not (claims_dict is Dictionary):
		return 0
	var total := 0
	for tid in claims_dict:
		var claim: Dictionary = (claims_dict as Dictionary)[tid]
		var owner_id: Variant = claim.get("owner_player_id", null)
		if owner_id != null and int(owner_id) == int(player_id):
			total += 1
	return total


func set_visible(v: bool) -> void:
	if _bar_container:
		_bar_container.visible = v


func _create_player_slot(player: Dictionary, index: int) -> VBoxContainer:
	var player_id: int = int(player.get("id", -1))
	var player_name: String = player.get("name", "Player")
	var race: String = player.get("race", "Elf")
	var is_local: bool = player.get("is_local", false)

	var slot := VBoxContainer.new()
	slot.custom_minimum_size.x = SLOT_FIXED_WIDTH
	slot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	slot.add_theme_constant_override("separation", 0)
	slot.alignment = BoxContainer.ALIGNMENT_END

	# -- Sprite + card row (lighter gray background) --
	var sprite_panel := PanelContainer.new()
	sprite_panel.custom_minimum_size = Vector2(SLOT_FIXED_WIDTH, SPRITE_ROW_HEIGHT)

	var sprite_bg := StyleBoxFlat.new()
	sprite_bg.bg_color = SPRITE_ROW_BG
	sprite_bg.border_color = Color(0.2, 0.2, 0.25, 0.3)
	sprite_bg.set_border_width_all(0)
	sprite_bg.corner_radius_top_left = 5
	sprite_bg.corner_radius_top_right = 5
	sprite_bg.corner_radius_bottom_left = 0
	sprite_bg.corner_radius_bottom_right = 0
	sprite_bg.content_margin_left = 6
	sprite_bg.content_margin_right = 6
	sprite_bg.content_margin_top = 4
	sprite_bg.content_margin_bottom = 4
	sprite_panel.add_theme_stylebox_override("panel", sprite_bg)

	var sprite_row := HBoxContainer.new()
	sprite_row.alignment = BoxContainer.ALIGNMENT_CENTER
	sprite_row.add_theme_constant_override("separation", 8)
	sprite_panel.add_child(sprite_row)

	# Character sprite
	var sprite := TextureRect.new()
	var texture_path: String = App.get_race_texture_path(race)
	var texture = load(texture_path)
	if texture:
		sprite.texture = texture
	sprite.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sprite.custom_minimum_size = SPRITE_SIZE
	sprite_row.add_child(sprite)

	# Stats column: two rows stacked vertically (Mario Party style: icon + count side by side per row)
	var stats_col := VBoxContainer.new()
	stats_col.alignment = BoxContainer.ALIGNMENT_CENTER
	stats_col.add_theme_constant_override("separation", 0)
	sprite_row.add_child(stats_col)

	# Row 1: card icon + card count
	var card_row := HBoxContainer.new()
	card_row.alignment = BoxContainer.ALIGNMENT_CENTER
	card_row.add_theme_constant_override("separation", 2)
	stats_col.add_child(card_row)

	if _card_icon_texture:
		var card_icon := TextureRect.new()
		card_icon.texture = _card_icon_texture
		card_icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		card_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		card_icon.custom_minimum_size = Vector2(16, 22)
		card_icon.modulate = App.get_race_color(race)
		card_row.add_child(card_icon)

	var card_label := Label.new()
	var initial_count: int = PhaseController.player_card_counts.get(player_id, -1)
	card_label.text = str(initial_count) if initial_count >= 0 else str(App.player_card_collection.size())
	card_label.add_theme_font_override("font", UI_FONT)
	card_label.add_theme_font_size_override("font_size", 22)
	card_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.9))
	card_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	card_label.add_theme_constant_override("outline_size", 2)
	card_row.add_child(card_label)

	# Row 2: territory icon + territory count (same size/style as card row)
	var territory_row := HBoxContainer.new()
	territory_row.alignment = BoxContainer.ALIGNMENT_CENTER
	territory_row.add_theme_constant_override("separation", 2)
	stats_col.add_child(territory_row)

	if _territory_icon_texture:
		var territory_icon := TextureRect.new()
		territory_icon.texture = _territory_icon_texture
		territory_icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		territory_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		territory_icon.custom_minimum_size = Vector2(16, 22)
		territory_icon.modulate = App.get_race_color(race)
		territory_row.add_child(territory_icon)

	var territory_label := Label.new()
	territory_label.text = str(_get_player_territory_count(player_id))
	territory_label.add_theme_font_override("font", UI_FONT)
	territory_label.add_theme_font_size_override("font_size", 22)
	territory_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.9))
	territory_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	territory_label.add_theme_constant_override("outline_size", 2)
	territory_row.add_child(territory_label)

	slot.add_child(sprite_panel)

	# -- Name panel (darker gray background, fixed size) --
	var name_panel := PanelContainer.new()
	name_panel.custom_minimum_size = Vector2(SLOT_FIXED_WIDTH, NAME_PANEL_HEIGHT)

	var name_bg := StyleBoxFlat.new()
	name_bg.bg_color = DEFAULT_NAME_BG
	name_bg.border_color = Color(0.3, 0.3, 0.35, 1.0)
	name_bg.set_border_width_all(1)
	name_bg.corner_radius_top_left = 0
	name_bg.corner_radius_top_right = 0
	name_bg.corner_radius_bottom_left = 5
	name_bg.corner_radius_bottom_right = 5
	name_bg.content_margin_left = 5
	name_bg.content_margin_right = 5
	name_bg.content_margin_top = 2
	name_bg.content_margin_bottom = 2
	name_panel.add_theme_stylebox_override("panel", name_bg)

	var name_label := Label.new()
	name_label.text = player_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.add_theme_font_override("font", UI_FONT)
	name_label.add_theme_font_size_override("font_size", 22)
	name_label.add_theme_color_override("font_color", Color.WHITE)
	name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	name_label.add_theme_constant_override("outline_size", 2)
	name_panel.add_child(name_label)

	slot.add_child(name_panel)

	var race_color := App.get_race_color(race)
	name_bg.bg_color = _darken_color(race_color, 0.45)

	_player_slots[player_id] = {
		"name_bg": name_bg,
		"sprite_bg": sprite_bg,
		"slot_root": slot,
		"card_label": card_label,
		"territory_label": territory_label,
		"is_local": is_local,
		"race_color": race_color,
	}

	_make_pass_through(slot)
	return slot


func _make_pass_through(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_make_pass_through(child)


func _darken_color(c: Color, factor: float) -> Color:
	return Color(c.r * factor, c.g * factor, c.b * factor, 1.0)


func _ordinal(n: int) -> String:
	match n:
		1: return "1st"
		2: return "2nd"
		3: return "3rd"
		_: return str(n) + "th"

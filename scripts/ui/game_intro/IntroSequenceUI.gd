extends Node

## IntroSequenceUI — Manages the intro sequence: player showcase, D20 rolling, turn order display.
## Programmatic component: created with .new(), receives node refs via initialize().

signal intro_completed

const UI_FONT := preload("res://fonts/m5x7.ttf")
const D20_SPRITESHEET_PATH := "res://pictures/d20_roll_sprite.png"
const D20_FRAME_SIZE := Vector2i(450, 450)
const D20_COLS := 5
const D20_ROWS := 11
const D20_FPS := 24.0

enum Phase { SHOWCASE, ROLLING, SHOW_PLAYER_ROLL, SHOW_ORDER, GAME_READY }
var current_phase: Phase = Phase.SHOWCASE

# Node references (set via initialize)
var showcase_container: CenterContainer
var showcase_race_image: TextureRect
var showcase_name_label: Label
var d20_container: CenterContainer
var d20_sprite: Panel
var d20_anim: TextureRect
var roll_result_label: Label
var rolling_label: Label
var player_roll_container: CenterContainer
var order_center_container: CenterContainer
var order_list_center: VBoxContainer
var order_corner_container: VBoxContainer
var map_overlay: ColorRect

# Animation state
var showcase_timer: float = 0.0
var roll_animation_timer: float = 0.0
var roll_duration: float = 2.5
var current_rolling_player_idx: int = 0
var roll_display_value: int = 1
var roll_tick_timer: float = 0.0

# D20 spritesheet animation
var _d20_frames: Array[Texture2D] = []
var _d20_frame_idx: int = 0
var _d20_frame_timer: float = 0.0

# Order display items
var order_items_center: Array = []
var order_items_corner: Array = []

func initialize(nodes: Dictionary) -> void:
	showcase_container = nodes.get("showcase_container")
	showcase_race_image = nodes.get("showcase_race_image")
	showcase_name_label = nodes.get("showcase_name_label")
	d20_container = nodes.get("d20_container")
	d20_sprite = nodes.get("d20_sprite")
	d20_anim = nodes.get("d20_anim")
	roll_result_label = nodes.get("roll_result_label")
	rolling_label = nodes.get("rolling_label")
	player_roll_container = nodes.get("player_roll_container")
	order_center_container = nodes.get("order_center_container")
	order_list_center = nodes.get("order_list_center")
	order_corner_container = nodes.get("order_corner_container")
	map_overlay = nodes.get("map_overlay")

func start_intro() -> void:
	_load_d20_spritesheet_frames()
	_setup_showcase()
	current_phase = Phase.SHOWCASE
	showcase_timer = 0.0

func skip_intro() -> void:
	## Skip all intro animations — just build corner order display.
	showcase_container.visible = false
	d20_container.visible = false
	order_center_container.visible = false
	map_overlay.modulate.a = 0.0
	var corner_parent = order_corner_container.get_parent()
	corner_parent.visible = true
	for child in order_corner_container.get_children():
		if child.name != "TitleLabel":
			child.queue_free()
	for i in range(App.turn_order.size()):
		var player = App.turn_order[i]
		var item := _create_order_item(player, i + 1, false)
		order_corner_container.add_child(item)
	current_phase = Phase.GAME_READY

func process_frame(delta: float) -> void:
	match current_phase:
		Phase.SHOWCASE:
			_process_showcase(delta)
		Phase.ROLLING:
			_process_rolling(delta)
		Phase.SHOW_PLAYER_ROLL:
			pass
		Phase.SHOW_ORDER:
			pass
		Phase.GAME_READY:
			pass

# ---------- SHOWCASE ----------

func _setup_showcase() -> void:
	var local_player: Dictionary = {}
	for p in App.game_players:
		if p.get("is_local", false):
			local_player = p
			break
	if local_player.is_empty():
		return
	var texture_path: String = App.get_race_texture_path(String(local_player.get("race", "Elf")))
	var texture = load(texture_path)
	if texture:
		showcase_race_image.texture = texture
	showcase_name_label.text = local_player.get("name", "Player")

func _process_showcase(delta: float) -> void:
	showcase_timer += delta
	if showcase_timer >= 2.5 and showcase_container.modulate.a >= 1.0:
		var tween := create_tween()
		tween.tween_property(showcase_container, "modulate:a", 0.0, 0.8)
		tween.tween_callback(_start_rolling_phase)

func _start_rolling_phase() -> void:
	showcase_container.visible = false
	d20_container.visible = true
	d20_container.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(d20_container, "modulate:a", 1.0, 0.5)
	tween.tween_callback(_begin_rolling_sequence)

# ---------- ROLLING ----------

func _begin_rolling_sequence() -> void:
	current_phase = Phase.ROLLING
	current_rolling_player_idx = 0
	_start_d20_anim()

	if App.is_multiplayer:
		rolling_label.text = "Rolling for turn order..."
		rolling_label.visible = true
		roll_result_label.visible = false
		if not PlayerDataSync.player_rolls_updated.is_connected(_on_rolls_synced):
			PlayerDataSync.player_rolls_updated.connect(_on_rolls_synced)
		PlayerDataSync.request_roll_generation()
	else:
		_roll_for_player(current_rolling_player_idx)

func _on_rolls_synced() -> void:
	if PlayerDataSync.player_rolls_updated.is_connected(_on_rolls_synced):
		PlayerDataSync.player_rolls_updated.disconnect(_on_rolls_synced)
	_display_multiplayer_rolls()

func _display_multiplayer_rolls() -> void:
	for i in range(App.game_players.size()):
		var player = App.game_players[i]
		var player_name: String = player.get("name", "Player")
		var roll_value: int = player.get("roll", 0)
		roll_animation_timer = 0.0
		roll_tick_timer = 0.0
		var anim_duration := 0.8
		_start_d20_anim()
		rolling_label.text = player_name + " rolling..."
		rolling_label.visible = true
		while roll_animation_timer < anim_duration:
			await get_tree().process_frame
			var delta := get_process_delta_time()
			roll_animation_timer += delta
			roll_tick_timer += delta
			_advance_d20_anim(delta)
			if roll_tick_timer >= 0.06:
				roll_tick_timer = 0.0
				roll_result_label.text = str(randi_range(1, 20))
				roll_result_label.visible = true
		roll_result_label.text = str(roll_value)
		rolling_label.text = player_name + " rolled " + str(roll_value) + "!"
		await get_tree().create_timer(0.8).timeout
	_finalize_turn_order()

func _roll_for_player(idx: int) -> void:
	if idx >= App.game_players.size():
		_finalize_turn_order()
		return
	var player = App.game_players[idx]
	rolling_label.text = player.get("name", "Player") + " rolling..."
	rolling_label.visible = true
	roll_result_label.visible = false
	_start_d20_anim()
	roll_animation_timer = 0.0
	roll_tick_timer = 0.0
	roll_display_value = randi_range(1, 20)

func _process_rolling(delta: float) -> void:
	roll_animation_timer += delta
	roll_tick_timer += delta
	_advance_d20_anim(delta)
	if roll_tick_timer >= 0.08:
		roll_tick_timer = 0.0
		roll_display_value = randi_range(1, 20)
		roll_result_label.text = str(roll_display_value)
		roll_result_label.visible = true
	if roll_animation_timer >= roll_duration:
		_finish_current_roll()

func _finish_current_roll() -> void:
	if current_rolling_player_idx >= App.game_players.size():
		push_warning("Invalid rolling player index: ", current_rolling_player_idx)
		_finalize_turn_order()
		return
	var final_roll := randi_range(1, 20)
	App.game_players[current_rolling_player_idx]["roll"] = final_roll
	var player_name: String = App.game_players[current_rolling_player_idx].get("name", "Player")
	roll_result_label.text = str(final_roll)
	rolling_label.text = player_name + " rolled " + str(final_roll) + "!"
	await get_tree().create_timer(1.2).timeout
	current_rolling_player_idx += 1
	if current_rolling_player_idx < App.game_players.size():
		_roll_for_player(current_rolling_player_idx)
	else:
		_finalize_turn_order()

# ---------- TURN ORDER ----------

func _finalize_turn_order() -> void:
	PlayerDataSync.finalize_turn_order()
	current_phase = Phase.SHOW_PLAYER_ROLL
	_display_player_roll()

func _display_player_roll() -> void:
	d20_container.visible = false
	var local_player: Dictionary = {}
	for p in App.game_players:
		if p.get("is_local", false):
			local_player = p
			break
	if local_player.is_empty():
		_display_center_order()
		return
	player_roll_container.visible = true
	player_roll_container.modulate.a = 0.0
	var roll_value_label = player_roll_container.get_node_or_null("Panel/VBoxContainer/RollValueLabel")
	var roll_text_label = player_roll_container.get_node_or_null("Panel/VBoxContainer/RollTextLabel")
	if roll_value_label:
		roll_value_label.text = str(local_player.get("roll", 0))
	if roll_text_label:
		roll_text_label.text = "Your Roll"
	var tween := create_tween()
	tween.tween_property(player_roll_container, "modulate:a", 1.0, 0.5)
	tween.tween_interval(2.0)
	tween.tween_property(player_roll_container, "modulate:a", 0.0, 0.3)
	tween.tween_callback(_show_turn_order_after_player_roll)

func _show_turn_order_after_player_roll() -> void:
	player_roll_container.visible = false
	current_phase = Phase.SHOW_ORDER
	_display_center_order()

func _display_center_order() -> void:
	rolling_label.visible = false
	roll_result_label.visible = false
	d20_container.visible = false
	order_center_container.visible = true
	order_center_container.modulate.a = 0.0
	for child in order_list_center.get_children():
		child.queue_free()
	order_items_center.clear()
	for i in range(App.turn_order.size()):
		var player = App.turn_order[i]
		var item := _create_order_item(player, i + 1, true)
		order_list_center.add_child(item)
		order_items_center.append(item)
	var tween := create_tween()
	tween.tween_property(order_center_container, "modulate:a", 1.0, 0.5)
	tween.tween_interval(3.0)
	tween.tween_callback(_minimize_to_corner)

func _minimize_to_corner() -> void:
	var tween := create_tween()
	tween.tween_property(order_center_container, "modulate:a", 0.0, 0.3)
	tween.tween_callback(_show_corner_order)

func _show_corner_order() -> void:
	order_center_container.visible = false
	var corner_parent = order_corner_container.get_parent()
	corner_parent.visible = true
	corner_parent.modulate.a = 0.0
	for child in order_corner_container.get_children():
		if child.name != "TitleLabel":
			child.queue_free()
	order_items_corner.clear()
	for i in range(App.turn_order.size()):
		var player = App.turn_order[i]
		var item := _create_order_item(player, i + 1, false)
		order_corner_container.add_child(item)
		order_items_corner.append(item)
	var map_tween := create_tween()
	map_tween.set_parallel(true)
	map_tween.tween_property(map_overlay, "modulate:a", 0.0, 0.8)
	map_tween.tween_property(corner_parent, "modulate:a", 1.0, 0.5)
	await map_tween.finished
	current_phase = Phase.GAME_READY
	intro_completed.emit()

func _create_order_item(player: Dictionary, order_position: int, is_center: bool) -> HBoxContainer:
	var container := HBoxContainer.new()
	container.add_theme_constant_override("separation", 10)
	var pos_label := Label.new()
	pos_label.text = str(order_position) + "."
	pos_label.add_theme_font_override("font", UI_FONT)
	pos_label.add_theme_font_size_override("font_size", 24 if is_center else 16)
	pos_label.add_theme_color_override("font_color", Color.WHITE)
	pos_label.custom_minimum_size.x = 30 if is_center else 20
	container.add_child(pos_label)
	var race_icon := TextureRect.new()
	var texture_path: String = App.get_race_texture_path(String(player.get("race", "Elf")))
	var texture = load(texture_path)
	if texture:
		race_icon.texture = texture
	race_icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	race_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	race_icon.custom_minimum_size = Vector2(40, 40) if is_center else Vector2(24, 24)
	container.add_child(race_icon)
	var name_label := Label.new()
	name_label.text = player.get("name", "Player")
	name_label.add_theme_font_override("font", UI_FONT)
	name_label.add_theme_font_size_override("font_size", 22 if is_center else 14)
	name_label.add_theme_color_override("font_color", App.get_race_color(player.get("race", "Elf")))
	container.add_child(name_label)
	if is_center:
		var roll_label := Label.new()
		roll_label.text = "(" + str(player.get("roll", 0)) + ")"
		roll_label.add_theme_font_override("font", UI_FONT)
		roll_label.add_theme_font_size_override("font_size", 18)
		roll_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		container.add_child(roll_label)
	if player.get("is_local", false):
		var you_label := Label.new()
		you_label.text = " (You)" if is_center else "*"
		you_label.add_theme_font_override("font", UI_FONT)
		you_label.add_theme_font_size_override("font_size", 18 if is_center else 12)
		you_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))
		container.add_child(you_label)
	return container

# ---------- D20 SPRITESHEET ----------

func _load_d20_spritesheet_frames() -> void:
	_d20_frames.clear()
	var img := Image.new()
	var err := img.load(D20_SPRITESHEET_PATH)
	if err != OK:
		push_warning("Could not load d20 spritesheet: ", D20_SPRITESHEET_PATH, " (err=", err, ")")
		return
	var atlas: Texture2D = ImageTexture.create_from_image(img)
	for y in range(D20_ROWS):
		for x in range(D20_COLS):
			var rect := Rect2i(x * D20_FRAME_SIZE.x, y * D20_FRAME_SIZE.y, D20_FRAME_SIZE.x, D20_FRAME_SIZE.y)
			if not _d20_frame_has_content(img, rect):
				continue
			var frame := AtlasTexture.new()
			frame.atlas = atlas
			frame.region = rect
			_d20_frames.append(frame)
	if d20_anim and not _d20_frames.is_empty():
		d20_anim.texture = _d20_frames[0]

func _d20_frame_has_content(img: Image, rect: Rect2i) -> bool:
	var step := 16
	for y in range(rect.position.y, rect.position.y + rect.size.y, step):
		for x in range(rect.position.x, rect.position.x + rect.size.x, step):
			var c := img.get_pixel(x, y)
			if (c.r + c.g + c.b) > 0.06:
				return true
	return false

func _start_d20_anim() -> void:
	if d20_anim == null or _d20_frames.is_empty():
		return
	var label := d20_sprite.get_node_or_null("D20Label")
	if label is CanvasItem:
		label.visible = false
	_d20_frame_idx = 0
	_d20_frame_timer = 0.0
	d20_anim.texture = _d20_frames[_d20_frame_idx]

func _advance_d20_anim(delta: float) -> void:
	if d20_anim == null or _d20_frames.is_empty():
		return
	_d20_frame_timer += delta
	var frame_time := 1.0 / D20_FPS
	while _d20_frame_timer >= frame_time:
		_d20_frame_timer -= frame_time
		_d20_frame_idx = (_d20_frame_idx + 1) % _d20_frames.size()
		d20_anim.texture = _d20_frames[_d20_frame_idx]

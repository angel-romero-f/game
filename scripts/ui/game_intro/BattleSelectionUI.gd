extends Node

## BattleSelectionUI — Multiplayer battle territory selector UI.
## Programmatic component: created with .new(), receives node refs via initialize().

const UI_FONT := preload("res://fonts/m5x7.ttf")

var battle_button: Button
var battle_button_right: Button
var left_battle_selectors: VBoxContainer
var right_battle_selectors: VBoxContainer
var current_decider_label: Label
var skip_battle_decision_button: Button

func initialize(nodes: Dictionary) -> void:
	battle_button = nodes.get("battle_button")
	battle_button_right = nodes.get("battle_button_right")
	left_battle_selectors = nodes.get("left_battle_selectors")
	right_battle_selectors = nodes.get("right_battle_selectors")
	current_decider_label = nodes.get("current_decider_label")
	skip_battle_decision_button = nodes.get("skip_battle_decision_button")

	if battle_button:
		battle_button.pressed.connect(_on_left_battle_pressed)
	if battle_button_right:
		battle_button_right.pressed.connect(_on_right_battle_pressed)
	if skip_battle_decision_button:
		skip_battle_decision_button.pressed.connect(_on_skip_pressed)

func hide_all() -> void:
	if battle_button_right:
		battle_button_right.visible = false
	if left_battle_selectors:
		left_battle_selectors.visible = false
	if right_battle_selectors:
		right_battle_selectors.visible = false
	if current_decider_label:
		current_decider_label.visible = false
	if skip_battle_decision_button:
		skip_battle_decision_button.visible = false

func is_battle_in_progress() -> bool:
	return BattleSync.battle_in_progress

func get_decider_name() -> String:
	return _get_player_name_by_id(BattleSync.battle_decider_peer_id)

func update_ui() -> void:
	if not App.is_multiplayer:
		return
	if not multiplayer.has_multiplayer_peer():
		return

	var my_id := multiplayer.get_unique_id()
	var is_my_turn := (my_id == BattleSync.battle_decider_peer_id)
	var decider_name := get_decider_name()

	current_decider_label.text = "Current decider: %s" % decider_name
	current_decider_label.visible = true
	if battle_button:
		battle_button.visible = true
	battle_button_right.visible = true
	left_battle_selectors.visible = true
	right_battle_selectors.visible = true

	_update_selector_list(left_battle_selectors, BattleSync.left_queue)
	_update_selector_list(right_battle_selectors, BattleSync.right_queue)

	var left_full := BattleSync.left_queue.size() >= 2
	var right_full := BattleSync.right_queue.size() >= 2

	if is_my_turn:
		if battle_button:
			battle_button.disabled = left_full
			battle_button.text = "Left Battle (FULL)" if left_full else "Left Battle"
		battle_button_right.disabled = right_full
		battle_button_right.text = "Right Battle (FULL)" if right_full else "Right Battle"
		skip_battle_decision_button.visible = true
		skip_battle_decision_button.disabled = false
	else:
		if battle_button:
			battle_button.disabled = true
		battle_button_right.disabled = true
		skip_battle_decision_button.visible = false

func _update_selector_list(container: VBoxContainer, queue: Array) -> void:
	for child in container.get_children():
		child.queue_free()
	for pid in queue:
		var player_data := _get_player_data_by_id(pid)
		if player_data.is_empty():
			continue
		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", 5)
		var race: String = String(player_data.get("race", "Elf"))
		var icon := TextureRect.new()
		var texture = load(App.get_race_texture_path(race))
		if texture:
			icon.texture = texture
		icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(20, 20)
		item.add_child(icon)
		var name_label := Label.new()
		name_label.text = player_data.get("name", "Player")
		name_label.add_theme_font_override("font", UI_FONT)
		name_label.add_theme_font_size_override("font_size", 16)
		name_label.add_theme_color_override("font_color", App.get_race_color(race))
		item.add_child(name_label)
		container.add_child(item)

func _on_left_battle_pressed() -> void:
	if App.is_multiplayer and multiplayer.has_multiplayer_peer():
		BattleSync.request_battle_choice("LEFT")
	else:
		if BattleStateManager:
			BattleStateManager.set_current_territory("default")
		App.go("res://scenes/card_battle.tscn")

func _on_right_battle_pressed() -> void:
	if App.is_multiplayer and multiplayer.has_multiplayer_peer():
		BattleSync.request_battle_choice("RIGHT")

func _on_skip_pressed() -> void:
	if App.is_multiplayer and multiplayer.has_multiplayer_peer():
		BattleSync.request_battle_choice("SKIP")

func _get_player_name_by_id(peer_id: int) -> String:
	for player in App.game_players:
		if player.get("id", -1) == peer_id:
			return player.get("name", "Player")
	return "Player"

func _get_player_data_by_id(peer_id: int) -> Dictionary:
	for player in App.game_players:
		if player.get("id", -1) == peer_id:
			return player
	return {}

extends Control

var title_label: Label
var name_label: Label
var code_label: Label
var slots_label: Label
var add_bot_button: Button
var remove_bot_button: Button
var bot_difficulty_container: VBoxContainer
var players_list: ItemList
var start_button: Button
var back_button: Button
var _difficulty_sliders: Dictionary = {} # bot_id -> HSlider

func _ready() -> void:
	title_label = get_node_or_null("Card/Margin/VBoxContainer/TitleLabel")
	name_label = get_node_or_null("Card/Margin/VBoxContainer/NameLabel")
	code_label = get_node_or_null("Card/Margin/VBoxContainer/CodeLabel")
	slots_label = get_node_or_null("Card/Margin/VBoxContainer/SlotsLabel")
	add_bot_button = get_node_or_null("Card/Margin/VBoxContainer/BotHBox/AddBotButton")
	remove_bot_button = get_node_or_null("Card/Margin/VBoxContainer/BotHBox/RemoveBotButton")
	bot_difficulty_container = get_node_or_null("Card/Margin/VBoxContainer/BotDifficultyContainer")
	players_list = get_node_or_null("Card/Margin/VBoxContainer/PlayersList")
	start_button = get_node_or_null("Card/Margin/VBoxContainer/StartButton")
	back_button = get_node_or_null("Card/Margin/VBoxContainer/BackButton")

	if title_label:
		title_label.text = "Host Lobby"

	if name_label:
		var display_name := App.player_name if not App.player_name.is_empty() else "Player"
		name_label.text = "Name: " + display_name

	if start_button:
		start_button.pressed.connect(_on_start_pressed)
	if back_button:
		back_button.pressed.connect(_on_back_pressed)
	if add_bot_button:
		add_bot_button.pressed.connect(_on_add_bot_pressed)
	if remove_bot_button:
		remove_bot_button.pressed.connect(_on_remove_bot_pressed)

	# Host the game
	var host_ok := NetworkManager.host_game()
	if not host_ok:
		if code_label:
			code_label.text = "ERROR: Could not start server on port %d.\nAnother instance may already be running,\nor the port is blocked by your firewall." % NetworkManager.PORT
		if start_button:
			start_button.disabled = true
		if add_bot_button:
			add_bot_button.disabled = true
		if remove_bot_button:
			remove_bot_button.disabled = true
		return

	PlayerDataSync.submit_player_name(App.player_name)

	if code_label:
		code_label.text = "Share this code with others:\n" + NetworkManager.get_host_code()

	# Connect to multiplayer signals to update player list
	if multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.disconnect(_on_peer_connected)
	if multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.disconnect(_on_peer_disconnected)
	if PlayerDataSync.player_names_updated.is_connected(_on_player_data_updated):
		PlayerDataSync.player_names_updated.disconnect(_on_player_data_updated)
	if PlayerDataSync.player_races_updated.is_connected(_on_player_data_updated):
		PlayerDataSync.player_races_updated.disconnect(_on_player_data_updated)
	if PlayerDataSync.bot_difficulties_updated.is_connected(_on_player_data_updated):
		PlayerDataSync.bot_difficulties_updated.disconnect(_on_player_data_updated)

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	PlayerDataSync.player_names_updated.connect(_on_player_data_updated)
	PlayerDataSync.player_races_updated.connect(_on_player_data_updated)
	PlayerDataSync.bot_difficulties_updated.connect(_on_player_data_updated)

	_refresh_all()


func _on_player_data_updated() -> void:
	_refresh_all()


func _refresh_all() -> void:
	_refresh_players_list()
	_refresh_bot_controls()
	_refresh_bot_difficulty_controls()


func _refresh_bot_controls() -> void:
	if slots_label:
		var total: int = PlayerDataSync.get_total_participant_count()
		var bots: int = PlayerDataSync.get_bot_count()
		slots_label.text = "Players: %d / 4  (%d bot%s)" % [total, bots, "s" if bots != 1 else ""]
	if add_bot_button:
		add_bot_button.disabled = PlayerDataSync.get_total_participant_count() >= PlayerDataSync.TARGET_PLAYER_COUNT
	if remove_bot_button:
		remove_bot_button.disabled = PlayerDataSync.get_bot_count() <= 0


func _on_add_bot_pressed() -> void:
	if not multiplayer.is_server():
		return
	if PlayerDataSync.host_add_bot():
		_refresh_all()


func _on_remove_bot_pressed() -> void:
	if not multiplayer.is_server():
		return
	if PlayerDataSync.host_remove_bot():
		_refresh_all()


func _refresh_bot_difficulty_controls() -> void:
	if not bot_difficulty_container:
		return
	for c in bot_difficulty_container.get_children():
		c.queue_free()
	_difficulty_sliders.clear()

	var bot_ids: Array[int] = []
	for pid in PlayerDataSync.player_names.keys():
		if PlayerDataSync.is_bot_id(int(pid)):
			bot_ids.append(int(pid))
	bot_ids.sort()

	for bid in bot_ids:
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var bot_name := String(PlayerDataSync.player_names.get(bid, "Bot"))
		var label := Label.new()
		label.text = "%s Difficulty" % bot_name
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)

		var slider := HSlider.new()
		slider.min_value = 0
		slider.max_value = 5
		slider.step = 1
		slider.value = float(PlayerDataSync.get_bot_difficulty(bid))
		slider.custom_minimum_size = Vector2(140, 0)
		row.add_child(slider)

		var value_label := Label.new()
		value_label.text = str(int(slider.value))
		value_label.custom_minimum_size = Vector2(20, 0)
		slider.value_changed.connect(func(v: float) -> void:
			value_label.text = str(int(v))
		)
		# Commit to sync only when dragging ends to avoid rebuilding controls mid-drag.
		slider.drag_ended.connect(_on_bot_difficulty_drag_ended.bind(bid, slider))
		row.add_child(value_label)

		_difficulty_sliders[bid] = slider
		bot_difficulty_container.add_child(row)


func _on_bot_difficulty_drag_ended(value_changed: bool, bot_id: int, slider: HSlider) -> void:
	if not value_changed:
		return
	if not multiplayer.is_server():
		return
	if slider == null:
		return
	PlayerDataSync.host_set_bot_difficulty(bot_id, int(slider.value))


func _on_peer_connected(_id: int) -> void:
	_refresh_all()


func _on_peer_disconnected(_id: int) -> void:
	_refresh_all()


func _refresh_players_list() -> void:
	if not players_list:
		return

	players_list.clear()

	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
		return

	var host_id := multiplayer.get_unique_id()
	var human_ids: Array[int] = []
	human_ids.append(host_id)
	for p in multiplayer.get_peers():
		human_ids.append(int(p))
	human_ids.sort()

	for hid in human_ids:
		var n: String = String(PlayerDataSync.player_names.get(hid, "Player"))
		if hid == host_id:
			n += " (Host)"
		players_list.add_item(n)

	var bot_ids: Array[int] = []
	for pid in PlayerDataSync.player_names.keys():
		if PlayerDataSync.is_bot_id(int(pid)):
			bot_ids.append(int(pid))
	bot_ids.sort()

	for bid in bot_ids:
		var bn: String = String(PlayerDataSync.player_names.get(bid, "Bot"))
		var br: String = String(PlayerDataSync.player_races.get(bid, ""))
		if br.is_empty():
			br = "pending (at start)"
		players_list.add_item("%s — %s  [Bot]" % [bn, br])


func _on_start_pressed() -> void:
	if multiplayer.is_server():
		PhaseSync.start_race_select.rpc()


func _on_back_pressed() -> void:
	NetworkManager.disconnect_from_game()
	App.go("res://scenes/ui/PlayMenu.tscn")

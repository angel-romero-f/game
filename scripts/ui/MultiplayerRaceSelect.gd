extends Control

const RACES := ["Elf", "Orc", "Fairy", "Infernal"]

var title_label: Label
var info_label: Label
var players_list: ItemList

var start_button: Button
var back_button: Button

var race_buttons: Dictionary = {} # race_name -> Button
var race_button_default_styles: Dictionary = {} # race_name -> StyleBox

func _ready() -> void:
	title_label = get_node_or_null("Card/Margin/VBoxContainer/TitleLabel")
	info_label = get_node_or_null("Card/Margin/VBoxContainer/InfoLabel")
	players_list = get_node_or_null("Card/Margin/VBoxContainer/PlayersList")

	start_button = get_node_or_null("Card/Margin/VBoxContainer/StartButton")
	back_button = get_node_or_null("Card/Margin/VBoxContainer/BackButton")

	race_buttons["Elf"] = get_node_or_null("Card/Margin/VBoxContainer/ElfButton")
	race_buttons["Orc"] = get_node_or_null("Card/Margin/VBoxContainer/OrcButton")
	race_buttons["Fairy"] = get_node_or_null("Card/Margin/VBoxContainer/FairyButton")
	race_buttons["Infernal"] = get_node_or_null("Card/Margin/VBoxContainer/InfernalButton")

	if title_label:
		title_label.text = "Select Race"
	if info_label:
		info_label.text = "One race per player."

	for race in RACES:
		var b: Button = race_buttons.get(race)
		if b:
			b.pressed.connect(_on_race_pressed.bind(race))

	if start_button:
		start_button.pressed.connect(_on_start_pressed)
	if back_button:
		back_button.pressed.connect(_on_back_pressed)

	# Signals
	if Net.player_names_updated.is_connected(_refresh_all):
		Net.player_names_updated.disconnect(_refresh_all)
	if Net.player_races_updated.is_connected(_refresh_all):
		Net.player_races_updated.disconnect(_refresh_all)
	Net.player_names_updated.connect(_refresh_all)
	Net.player_races_updated.connect(_refresh_all)

	if multiplayer.peer_connected.is_connected(_on_peer_changed):
		multiplayer.peer_connected.disconnect(_on_peer_changed)
	if multiplayer.peer_disconnected.is_connected(_on_peer_changed):
		multiplayer.peer_disconnected.disconnect(_on_peer_changed)
	multiplayer.peer_connected.connect(_on_peer_changed)
	multiplayer.peer_disconnected.connect(_on_peer_changed)

	_refresh_all()

func _on_peer_changed(_id: int) -> void:
	_refresh_all()

func _my_id() -> int:
	return multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1

func _my_race() -> String:
	var r := String(Net.player_races.get(_my_id(), ""))
	return r

func _owner_of(race: String) -> int:
	for pid in Net.player_races.keys():
		if String(Net.player_races[pid]) == race:
			return int(pid)
	return 0

func _on_race_pressed(race: String) -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	if _my_race() == race:
		Net.submit_player_race("")
	else:
		Net.submit_player_race(race)

func _on_start_pressed() -> void:
	if multiplayer.is_server():
		Net.start_game.rpc()

func _on_back_pressed() -> void:
	Net.disconnect_from_game()
	App.go("res://scenes/ui/PlayMenu.tscn")

func _refresh_all() -> void:
	_refresh_buttons()
	_refresh_players_list()
	_refresh_start_button()

func _refresh_buttons() -> void:
	var my_id := _my_id()
	var my_race := _my_race()

	for race in RACES:
		var b: Button = race_buttons.get(race)
		if not b:
			continue
		var owner_id := _owner_of(race)
		if owner_id != 0 and owner_id != my_id:
			var owner_name := String(Net.player_names.get(owner_id, "Player"))
			b.disabled = true
			b.text = "%s (Taken by %s)" % [race, owner_name]
			# Reset to default style when disabled/taken
			b.remove_theme_stylebox_override("normal")
			b.remove_theme_stylebox_override("hover")
			b.remove_theme_stylebox_override("pressed")
		else:
			b.disabled = false
			b.text = race
			
			# Apply visual feedback for selected race
			if my_race == race:
				# Create a green style for the selected button
				var selected_style = StyleBoxFlat.new()
				selected_style.bg_color = Color(0.2, 0.7, 0.2, 1.0)  # Green background
				selected_style.border_width_left = 2
				selected_style.border_width_top = 2
				selected_style.border_width_right = 2
				selected_style.border_width_bottom = 2
				selected_style.border_color = Color(0.1, 0.5, 0.1, 1.0)  # Darker green border
				
				b.add_theme_stylebox_override("normal", selected_style)
				b.add_theme_stylebox_override("hover", selected_style)
				b.add_theme_stylebox_override("pressed", selected_style)
			else:
				# Reset to default style
				b.remove_theme_stylebox_override("normal")
				b.remove_theme_stylebox_override("hover")
				b.remove_theme_stylebox_override("pressed")

func _refresh_players_list() -> void:
	if not players_list or not multiplayer.has_multiplayer_peer():
		return

	players_list.clear()

	var ids: Array[int] = []
	ids.append(_my_id())
	for peer_id in multiplayer.get_peers():
		ids.append(int(peer_id))
	ids.sort()

	for id in ids:
		var player_name := String(Net.player_names.get(id, "Player"))
		if id == _my_id():
			player_name += " (You)"
		var race := String(Net.player_races.get(id, "—"))
		if race.is_empty():
			race = "—"
		players_list.add_item("%s — %s" % [player_name, race])

func _refresh_start_button() -> void:
	if not start_button:
		return
	start_button.visible = multiplayer.is_server()

extends Control

const RACES := ["Elf", "Orc", "Fairy", "Infernal"]

var title_label: Label
var info_label: Label
var players_list: ItemList

var start_button: Button
var back_button: Button

var race_buttons: Dictionary = {} # race_name -> Button
var race_cards: Dictionary = {} # race_name -> PanelContainer
var race_card_default_styles: Dictionary = {} # race_name -> StyleBox
var race_taken_overlays: Dictionary = {} # race_name -> ColorRect

func _ready() -> void:
	title_label = get_node_or_null("MainContainer/TopMargin/TitleLabel")
	info_label = get_node_or_null("MainContainer/InfoLabel")
	players_list = get_node_or_null("MainContainer/BottomSection/Margin/VBoxContainer/PlayersList")

	start_button = get_node_or_null("MainContainer/BottomSection/Margin/VBoxContainer/ButtonContainer/StartButton")
	back_button = get_node_or_null("MainContainer/BottomSection/Margin/VBoxContainer/ButtonContainer/BackButton")

	race_cards["Elf"] = get_node_or_null("MainContainer/CardsMargin/CardsContainer/ElfCard")
	race_cards["Orc"] = get_node_or_null("MainContainer/CardsMargin/CardsContainer/OrcCard")
	race_cards["Fairy"] = get_node_or_null("MainContainer/CardsMargin/CardsContainer/FairyCard")
	race_cards["Infernal"] = get_node_or_null("MainContainer/CardsMargin/CardsContainer/InfernalCard")

	race_taken_overlays["Elf"] = get_node_or_null("MainContainer/CardsMargin/CardsContainer/ElfCard/TakenOverlay")
	race_taken_overlays["Orc"] = get_node_or_null("MainContainer/CardsMargin/CardsContainer/OrcCard/TakenOverlay")
	race_taken_overlays["Fairy"] = get_node_or_null("MainContainer/CardsMargin/CardsContainer/FairyCard/TakenOverlay")
	race_taken_overlays["Infernal"] = get_node_or_null("MainContainer/CardsMargin/CardsContainer/InfernalCard/TakenOverlay")

	race_buttons["Elf"] = get_node_or_null("MainContainer/CardsMargin/CardsContainer/ElfCard/ElfButton")
	race_buttons["Orc"] = get_node_or_null("MainContainer/CardsMargin/CardsContainer/OrcCard/OrcButton")
	race_buttons["Fairy"] = get_node_or_null("MainContainer/CardsMargin/CardsContainer/FairyCard/FairyButton")
	race_buttons["Infernal"] = get_node_or_null("MainContainer/CardsMargin/CardsContainer/InfernalCard/InfernalButton")

	if title_label:
		title_label.text = "Select Race"
	if info_label:
		info_label.text = "One race per player."

	# Store default card styles
	for race in RACES:
		var card: PanelContainer = race_cards.get(race)
		if card:
			var style = card.get_theme_stylebox("panel")
			if style:
				race_card_default_styles[race] = style

	for race in RACES:
		var b: Button = race_buttons.get(race)
		if b:
			b.pressed.connect(_on_race_pressed.bind(race))
			b.mouse_entered.connect(_on_card_hover_enter.bind(race))
			b.mouse_exited.connect(_on_card_hover_exit.bind(race))

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

func _all_players_have_race_selected() -> bool:
	if not multiplayer.has_multiplayer_peer():
		return false

	var ids: Array[int] = []
	ids.append(_my_id())
	for peer_id in multiplayer.get_peers():
		ids.append(int(peer_id))

	for id in ids:
		var race := String(Net.player_races.get(id, ""))
		if race.is_empty():
			return false

	return true

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
		App.set_selected_race("")
	else:
		Net.submit_player_race(race)
		App.set_selected_race(race)

func _on_start_pressed() -> void:
	if multiplayer.is_server():
		Net.start_game.rpc()

func _on_back_pressed() -> void:
	Net.disconnect_from_game()
	App.go("res://scenes/ui/PlayMenu.tscn")

func _on_card_hover_enter(race: String) -> void:
	var card: PanelContainer = race_cards.get(race)
	if not card:
		return
	
	# Don't show hover effect if card is disabled
	var b: Button = race_buttons.get(race)
	if b and b.disabled:
		return
	
	# Don't override selected state
	if _my_race() == race:
		return
	
	# Create hover style with white border
	var hover_style = _create_hover_style(race)
	card.add_theme_stylebox_override("panel", hover_style)

func _on_card_hover_exit(race: String) -> void:
	# Refresh to restore proper state
	_refresh_buttons()

func _refresh_all() -> void:
	_refresh_buttons()
	_refresh_players_list()
	_refresh_start_button()

func _refresh_buttons() -> void:
	var my_id := _my_id()
	var my_race := _my_race()

	for race in RACES:
		var b: Button = race_buttons.get(race)
		var card: PanelContainer = race_cards.get(race)
		var overlay: ColorRect = race_taken_overlays.get(race)
		if not b or not card:
			continue
		
		var owner_id := _owner_of(race)
		if owner_id != 0 and owner_id != my_id:
			# Race is taken by another player
			b.disabled = true
			if overlay:
				overlay.visible = true
			# Reset to default card style
			var default_style = race_card_default_styles.get(race)
			if default_style:
				card.add_theme_stylebox_override("panel", default_style)
		else:
			b.disabled = false
			if overlay:
				overlay.visible = false
			
			# Apply visual feedback for selected race
			if my_race == race:
				# Create highlighted style with vibrant border
				var selected_style = _create_selected_style(race)
				card.add_theme_stylebox_override("panel", selected_style)
			else:
				# Reset to default style
				var default_style = race_card_default_styles.get(race)
				if default_style:
					card.add_theme_stylebox_override("panel", default_style)

func _create_selected_style(race: String) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	
	# Set background color based on race
	match race:
		"Elf":
			style.bg_color = Color(1, 0.9, 0.2, 1)  # Yellow
			style.border_color = Color(0.6, 0.5, 0.1, 1)  # Darker yellow border
		"Orc":
			style.bg_color = Color(0.2, 0.8, 0.2, 1)  # Green
			style.border_color = Color(0.1, 0.4, 0.1, 1)  # Darker green border
		"Fairy":
			style.bg_color = Color(0.7, 0.3, 0.9, 1)  # Purple
			style.border_color = Color(0.4, 0.15, 0.5, 1)  # Darker purple border
		"Infernal":
			style.bg_color = Color(0.9, 0.2, 0.2, 1)  # Red
			style.border_color = Color(0.5, 0.1, 0.1, 1)  # Darker red border
	
	# Thicker border for selected state (increased from 6 to 10)
	style.border_width_left = 10
	style.border_width_top = 10
	style.border_width_right = 10
	style.border_width_bottom = 10
	
	return style

func _create_hover_style(race: String) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	
	# Set background color based on race (same as default)
	match race:
		"Elf":
			style.bg_color = Color(1, 0.9, 0.2, 1)  # Yellow
		"Orc":
			style.bg_color = Color(0.2, 0.8, 0.2, 1)  # Green
		"Fairy":
			style.bg_color = Color(0.7, 0.3, 0.9, 1)  # Purple
		"Infernal":
			style.bg_color = Color(0.9, 0.2, 0.2, 1)  # Red
	
	# White border for hover state
	style.border_color = Color(1, 1, 1, 1)
	style.border_width_left = 5
	style.border_width_top = 5
	style.border_width_right = 5
	style.border_width_bottom = 5
	
	return style

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
	if start_button.visible:
		start_button.disabled = not _all_players_have_race_selected()
	else:
		start_button.disabled = true
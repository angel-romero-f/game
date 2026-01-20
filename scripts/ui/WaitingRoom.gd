extends Control

var title_label: Label
var name_label: Label
var info_label: Label
var players_list: ItemList
var back_button: Button

func _ready() -> void:
	title_label = get_node_or_null("Card/Margin/VBoxContainer/TitleLabel")
	name_label = get_node_or_null("Card/Margin/VBoxContainer/NameLabel")
	info_label = get_node_or_null("Card/Margin/VBoxContainer/InfoLabel")
	players_list = get_node_or_null("Card/Margin/VBoxContainer/PlayersList")
	back_button = get_node_or_null("Card/Margin/VBoxContainer/BackButton")
	
	if title_label:
		title_label.text = "Waiting"
	
	if name_label:
		var display_name := App.player_name if not App.player_name.is_empty() else "Player"
		name_label.text = "Name: " + display_name
	
	if info_label:
		info_label.text = "Waiting for host to start..."
	
	if back_button:
		back_button.pressed.connect(_on_back_pressed)
	
	# Connect to multiplayer signals to update player list
	if multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.disconnect(_on_peer_connected)
	if multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.disconnect(_on_peer_disconnected)
	if Net.player_names_updated.is_connected(_on_player_names_updated):
		Net.player_names_updated.disconnect(_on_player_names_updated)
	
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	Net.player_names_updated.connect(_on_player_names_updated)
	
	_refresh_players_list()

func _on_peer_connected(id: int) -> void:
	_refresh_players_list()

func _on_peer_disconnected(id: int) -> void:
	_refresh_players_list()

func _on_player_names_updated() -> void:
	_refresh_players_list()

func _refresh_players_list() -> void:
	if not players_list:
		return
	
	players_list.clear()
	
	if multiplayer.has_multiplayer_peer():
		# Add self
		var my_id := multiplayer.get_unique_id()
		var my_name: String = String(Net.player_names.get(my_id, "You"))
		players_list.add_item("%s - ID: %d" % [my_name, my_id])
		
		# Add other peers
		var peers := multiplayer.get_peers()
		for peer_id in peers:
			if peer_id != my_id:
				var peer_name: String = String(Net.player_names.get(peer_id, "Player"))
				players_list.add_item("%s - ID: %d" % [peer_name, peer_id])

func _on_back_pressed() -> void:
	Net.disconnect_from_game()
	App.go("res://scenes/ui/PlayMenu.tscn")

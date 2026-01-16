extends Control

var title_label: Label
var info_label: Label
var players_list: ItemList
var back_button: Button

func _ready() -> void:
	title_label = get_node_or_null("Card/Margin/VBoxContainer/TitleLabel")
	info_label = get_node_or_null("Card/Margin/VBoxContainer/InfoLabel")
	players_list = get_node_or_null("Card/Margin/VBoxContainer/PlayersList")
	back_button = get_node_or_null("Card/Margin/VBoxContainer/BackButton")
	
	if title_label:
		title_label.text = "Waiting"
	
	if info_label:
		info_label.text = "Waiting for host to start..."
	
	if back_button:
		back_button.pressed.connect(_on_back_pressed)
	
	# Connect to multiplayer signals to update player list
	if multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.disconnect(_on_peer_connected)
	if multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.disconnect(_on_peer_disconnected)
	
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	
	_refresh_players_list()

func _on_peer_connected(id: int) -> void:
	_refresh_players_list()

func _on_peer_disconnected(id: int) -> void:
	_refresh_players_list()

func _refresh_players_list() -> void:
	if not players_list:
		return
	
	players_list.clear()
	
	if multiplayer.has_multiplayer_peer():
		# Add self
		var my_id := multiplayer.get_unique_id()
		players_list.add_item("You - ID: %d" % my_id)
		
		# Add other peers
		var peers := multiplayer.get_peers()
		for peer_id in peers:
			if peer_id != my_id:
				players_list.add_item("Player - ID: %d" % peer_id)

func _on_back_pressed() -> void:
	Net.disconnect_from_game()
	App.go("res://scenes/ui/PlayMenu.tscn")

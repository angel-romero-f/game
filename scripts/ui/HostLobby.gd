extends Control

var title_label: Label
var code_label: Label
var players_list: ItemList
var start_button: Button
var back_button: Button

func _ready() -> void:
	title_label = get_node_or_null("Card/Margin/VBoxContainer/TitleLabel")
	code_label = get_node_or_null("Card/Margin/VBoxContainer/CodeLabel")
	players_list = get_node_or_null("Card/Margin/VBoxContainer/PlayersList")
	start_button = get_node_or_null("Card/Margin/VBoxContainer/StartButton")
	back_button = get_node_or_null("Card/Margin/VBoxContainer/BackButton")
	
	if title_label:
		title_label.text = "Host Lobby"
	
	if start_button:
		start_button.pressed.connect(_on_start_pressed)
	if back_button:
		back_button.pressed.connect(_on_back_pressed)
	
	# Host the game
	Net.host_game()
	
	if code_label:
		code_label.text = "Host code: " + Net.get_host_code()
	
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
	
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		# Add host
		var host_id := multiplayer.get_unique_id()
		players_list.add_item("Host (you) - ID: %d" % host_id)
		
		# Add connected peers
		var peers := multiplayer.get_peers()
		for peer_id in peers:
			players_list.add_item("Player - ID: %d" % peer_id)

func _on_start_pressed() -> void:
	if multiplayer.is_server():
		# Call RPC on Net autoload (available to all peers)
		Net.start_game.rpc()

func _on_back_pressed() -> void:
	Net.disconnect_from_game()
	App.go("res://scenes/ui/PlayMenu.tscn")

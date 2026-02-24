extends Control

var title_label: Label
var code_input: LineEdit
var join_button: Button
var status_label: Label
var back_button: Button

func _ready() -> void:
	title_label = get_node_or_null("Card/Margin/VBoxContainer/TitleLabel")
	code_input = get_node_or_null("Card/Margin/VBoxContainer/CodeInput")
	join_button = get_node_or_null("Card/Margin/VBoxContainer/JoinButton")
	status_label = get_node_or_null("Card/Margin/VBoxContainer/StatusLabel")
	back_button = get_node_or_null("Card/Margin/VBoxContainer/BackButton")
	
	if title_label:
		title_label.text = "Join"
	
	if status_label:
		status_label.text = ""
	
	if code_input:
		code_input.placeholder_text = "Enter host code (e.g. 192.168.1.12)"
	
	if join_button:
		join_button.pressed.connect(_on_join_pressed)
	if back_button:
		back_button.pressed.connect(_on_back_pressed)
	
	# Allow Enter key to trigger join
	if code_input:
		code_input.text_submitted.connect(_on_code_submitted)

func _on_code_submitted(text: String) -> void:
	_on_join_pressed()

func _on_join_pressed() -> void:
	if not code_input:
		return
	
	var code := code_input.text.strip_edges()
	if code.is_empty():
		if status_label:
			status_label.text = "Enter a code"
		return
	
	if status_label:
		status_label.text = "Joining %s..." % code
	
	NetworkManager.join_game(code)
	
	var mp := multiplayer.multiplayer_peer
	if not mp:
		if status_label:
			status_label.text = "Could not connect to %s.\nMake sure the host is running and the code is their IP address (e.g. 192.168.1.5), not a player ID number." % code
		return
	var timeout_sec := 8.0
	var step := 0.2
	var waited := 0.0
	while waited < timeout_sec:
		await get_tree().create_timer(step).timeout
		waited += step
		if mp.get_connection_status() == ENetMultiplayerPeer.CONNECTION_CONNECTED:
			break
		if mp.get_connection_status() == ENetMultiplayerPeer.CONNECTION_DISCONNECTED:
			break
		if status_label:
			status_label.text = "Connecting to %s... (%.0fs)" % [code, waited]
	if mp.get_connection_status() != ENetMultiplayerPeer.CONNECTION_CONNECTED:
		if status_label:
			status_label.text = "Could not reach %s after %.0fs.\nCheck that:\n- The host game is running\n- Both devices are on the same Wi-Fi\n- Windows Firewall allows Godot/the game" % [code, waited]
		return
	PlayerDataSync.submit_player_name(App.player_name)
	App.go("res://scenes/ui/WaitingRoom.tscn")

func _on_back_pressed() -> void:
	App.go("res://scenes/ui/PlayMenu.tscn")

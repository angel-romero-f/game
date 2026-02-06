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
		status_label.text = "Connecting to %s..." % code
	
	print("[JoinScreen] Attempting to join: %s" % code)
	Net.join_game(code)
	
	# Wait for connection with timeout - check connection status properly
	var max_wait_time := 5.0  # 5 seconds timeout
	var elapsed := 0.0
	var check_interval := 0.2  # Check every 200ms
	
	while elapsed < max_wait_time:
		await get_tree().create_timer(check_interval).timeout
		elapsed += check_interval
		
		if not multiplayer.has_multiplayer_peer():
			print("[JoinScreen] No peer - connection likely failed")
			break
		
		var status := multiplayer.multiplayer_peer.get_connection_status()
		print("[JoinScreen] Connection status: %d (0=disconnected, 1=connecting, 2=connected)" % status)
		
		if status == MultiplayerPeer.CONNECTION_CONNECTED:
			print("[JoinScreen] Successfully connected!")
			Net.submit_player_name(App.player_name)
			App.go("res://scenes/ui/WaitingRoom.tscn")
			return
		elif status == MultiplayerPeer.CONNECTION_DISCONNECTED:
			print("[JoinScreen] Connection was rejected or failed")
			break
		
		# Still connecting, update status
		if status_label:
			status_label.text = "Connecting to %s... (%.1fs)" % [code, elapsed]
	
	# If we get here, connection failed
	print("[JoinScreen] Connection timed out or failed")
	if status_label:
		status_label.text = "Failed to connect to %s\nCheck IP and ensure host is running" % code
	
	# Print troubleshooting info
	Net.print_network_status()

func _on_back_pressed() -> void:
	App.go("res://scenes/ui/PlayMenu.tscn")

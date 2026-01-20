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
		code_input.placeholder_text = "Enter host code (e.g. 192.168.1.12:9999)"
	
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
	
	Net.join_game(code)
	
	# Wait a moment then transition
	await get_tree().create_timer(0.5).timeout
	if multiplayer.has_multiplayer_peer():
		Net.submit_player_name(App.player_name)
		App.go("res://scenes/ui/WaitingRoom.tscn")
	else:
		if status_label:
			status_label.text = "Failed to join %s" % code

func _on_back_pressed() -> void:
	App.go("res://scenes/ui/PlayMenu.tscn")

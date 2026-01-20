extends Control

var title_label: Label
var name_input: LineEdit
var status_label: Label
var continue_button: Button
var back_button: Button

func _ready() -> void:
	title_label = get_node_or_null("Card/Margin/VBoxContainer/TitleLabel")
	name_input = get_node_or_null("Card/Margin/VBoxContainer/NameInput")
	status_label = get_node_or_null("Card/Margin/VBoxContainer/StatusLabel")
	continue_button = get_node_or_null("Card/Margin/VBoxContainer/ContinueButton")
	back_button = get_node_or_null("Card/Margin/VBoxContainer/BackButton")
	
	if title_label:
		title_label.text = "Player Name"
	
	if status_label:
		status_label.text = ""
	
	if name_input:
		name_input.placeholder_text = "Enter your name"
		name_input.text_submitted.connect(_on_name_submitted)
	
	if continue_button:
		continue_button.pressed.connect(_on_continue_pressed)
	if back_button:
		back_button.pressed.connect(_on_back_pressed)

func _on_name_submitted(_text: String) -> void:
	_on_continue_pressed()

func _on_continue_pressed() -> void:
	if not name_input:
		return
	
	var name := name_input.text.strip_edges()
	if name.is_empty():
		if status_label:
			status_label.text = "Enter a name"
		return
	
	App.set_player_name(name)
	var target := App.next_scene
	if target.is_empty():
		target = "res://scenes/ui/PlayMenu.tscn"
	App.go(target)

func _on_back_pressed() -> void:
	App.go("res://scenes/ui/PlayMenu.tscn")

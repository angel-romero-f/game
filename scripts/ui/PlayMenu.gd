extends Control

var title_label: Label
var host_button: Button
var join_button: Button
var back_button: Button

func _ready() -> void:
	App.reset_session_state_for_menu_return()

	title_label = get_node_or_null("Card/Margin/VBoxContainer/TitleLabel")
	host_button = get_node_or_null("Card/Margin/VBoxContainer/HostButton")
	join_button = get_node_or_null("Card/Margin/VBoxContainer/JoinButton")
	back_button = get_node_or_null("Card/Margin/VBoxContainer/BackButton")
	
	if title_label:
		title_label.text = "Play"
	
	if host_button:
		host_button.pressed.connect(_on_host_pressed)
	if join_button:
		join_button.pressed.connect(_on_join_pressed)
	if back_button:
		back_button.pressed.connect(_on_back_pressed)

func _on_host_pressed() -> void:
	App.set_next_scene("res://scenes/ui/HostLobby.tscn")
	App.go("res://scenes/ui/NameEntry.tscn")

func _on_join_pressed() -> void:
	App.set_next_scene("res://scenes/ui/JoinScreen.tscn")
	App.go("res://scenes/ui/NameEntry.tscn")

func _on_back_pressed() -> void:
	App.go("res://scenes/ui/MainMenu.tscn")

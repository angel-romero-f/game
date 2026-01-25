extends Control

var title_label: Label
var play_button: Button
var settings_button: Button
var credits_button: Button
var status_label: Label

func _ready() -> void:
	title_label = get_node_or_null("Card/Margin/VBoxContainer/TitleLabel")
	play_button = get_node_or_null("Card/Margin/VBoxContainer/PlayButton")
	settings_button = get_node_or_null("Card/Margin/VBoxContainer/SettingsButton")
	credits_button = get_node_or_null("Card/Margin/VBoxContainer/CreditsButton")
	status_label = get_node_or_null("Card/Margin/VBoxContainer/StatusLabel")
	
	if title_label:
		title_label.text = "Main Menu"
	
	if status_label:
		status_label.text = ""
	
	if play_button:
		play_button.pressed.connect(_on_play_pressed)
	if settings_button:
		settings_button.pressed.connect(_on_settings_pressed)
	if credits_button:
		credits_button.pressed.connect(_on_credits_pressed)

func _on_play_pressed() -> void:
	App.go("res://scenes/ui/PlayMenu.tscn")

func _on_settings_pressed() -> void:
	App.go("res://scenes/ui/Settings.tscn")

func _on_credits_pressed() -> void:
	App.go("res://scenes/ui/Credits.tscn")

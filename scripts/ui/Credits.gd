extends Control

var back_button: Button

func _ready() -> void:
	back_button = get_node_or_null("Card/Margin/VBoxContainer/BackButton")
	if back_button:
		back_button.pressed.connect(_on_back_pressed)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_back_pressed()

func _on_back_pressed() -> void:
	App.go("res://scenes/ui/MainMenu.tscn")


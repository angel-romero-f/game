extends Node2D

## Card Battle scene controller
## Currently provides basic navigation back to the map

@onready var return_button: Button = $UI/Control/ReturnButton

func _ready() -> void:
	if return_button:
		return_button.pressed.connect(_on_return_pressed)

func _on_return_pressed() -> void:
	App.switch_to_main_music()
	App.go("res://scenes/ui/GameIntro.tscn")

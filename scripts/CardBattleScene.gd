extends Node2D

## Card Battle Scene controller
## Manages music playback for the battle scene

func _ready() -> void:
	# Switch to battle music when entering the battle
	App.switch_to_battle_music()
	print("Switched to battle music")

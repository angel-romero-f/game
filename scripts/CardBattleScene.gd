extends Node2D

## Card Battle Scene controller
## - Manages music playback for the battle scene
## - Exposes a territory_id so designers can give each territory a unique name

@export var territory_id: String = ""

func _ready() -> void:
	# Ensure the battle state manager knows which territory this scene represents.
	if BattleStateManager:
		if not territory_id.is_empty():
			BattleStateManager.set_current_territory(territory_id)
		elif BattleStateManager.current_territory_id != "":
			# If territory was set before scene load (from GameIntro), reuse it.
			territory_id = BattleStateManager.current_territory_id
	
	# Switch to battle music when entering the battle
	App.switch_to_battle_music()
	print("Switched to battle music for territory: ", territory_id)

extends Node2D

## Card Battle Scene controller
## - Manages music playback for the battle scene
## - Exposes a territory_id so designers can give each territory a unique name
## - Delegates full-screen territory background to CardSceneUI

@export var territory_id: String = ""

func _ready() -> void:
	# Ensure the battle state manager knows which territory this scene represents.
	if BattleStateManager:
		if not territory_id.is_empty():
			BattleStateManager.set_current_territory(territory_id)
		elif BattleStateManager.current_territory_id != "":
			# If territory was set before scene load (from GameIntro), reuse it.
			territory_id = BattleStateManager.current_territory_id

	var card_scene_ui: Node = get_node_or_null("CardSceneUI")
	if card_scene_ui and card_scene_ui.has_method("apply_territory_background"):
		card_scene_ui.apply_territory_background(territory_id, self)

	# Switch to battle music when entering the battle
	App.switch_to_battle_music()
	print("Switched to battle music for territory: ", territory_id)

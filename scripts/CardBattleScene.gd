extends Node2D

## Card Battle Scene controller
## - Manages music playback for the battle scene
## - Exposes a territory_id so designers can give each territory a unique name
## - Sets full-screen territory background from territory ID (darkened)

@export var territory_id: String = ""

const TERRITORY_BG_PATHS: Dictionary = {
	1: "res://assets/territory_battle_bg/glacier_forest_territory.pxo",
	2: "res://assets/territory_battle_bg/elevated_village_territory.pxo",
	3: "res://assets/territory_battle_bg/snowy_mountain_cave_territory.pxo",
	4: "res://assets/territory_battle_bg/elevated_forest_territory.pxo",
	5: "res://assets/territory_battle_bg/mountains_territory.pxo",
	6: "res://assets/territory_battle_bg/moss_rock_territory.pxo",
	7: "res://assets/territory_battle_bg/burnt_town_territory.pxo",
	8: "res://assets/territory_battle_bg/river_boat_territory.pxo",
	9: "res://assets/territory_battle_bg/river_forest_territory.pxo",
	10: "res://assets/territory_battle_bg/log_cabin_river_territory.pxo",
	11: "res://assets/territory_battle_bg/burnt_fort_territory.pxo",
	12: "res://assets/territory_battle_bg/cloud_territory.pxo",
}

func _ready() -> void:
	# Ensure the battle state manager knows which territory this scene represents.
	if BattleStateManager:
		if not territory_id.is_empty():
			BattleStateManager.set_current_territory(territory_id)
		elif BattleStateManager.current_territory_id != "":
			# If territory was set before scene load (from GameIntro), reuse it.
			territory_id = BattleStateManager.current_territory_id

	_apply_territory_background()

	# Switch to battle music when entering the battle
	App.switch_to_battle_music()
	print("Switched to battle music for territory: ", territory_id)


func _apply_territory_background() -> void:
	var tid_num := _territory_id_to_int(territory_id)
	if tid_num <= 0 or not TERRITORY_BG_PATHS.has(tid_num):
		return
	var path: String = TERRITORY_BG_PATHS[tid_num]
	var sf: SpriteFrames = load(path) as SpriteFrames
	if sf == null or not sf.has_animation("default"):
		return
	var fc := sf.get_frame_count("default")
	if fc <= 0:
		return
	var tex: Texture2D = sf.get_frame_texture("default", 0)
	var bg: TextureRect = get_node_or_null("BackgroundLayer/BackgroundContainer/TerritoryBackground") as TextureRect
	if bg and tex:
		bg.texture = tex


func _territory_id_to_int(tid: String) -> int:
	if tid.is_empty():
		return 0
	var s := tid
	if s.begins_with("battle_"):
		s = s.trim_prefix("battle_")
	return int(s)

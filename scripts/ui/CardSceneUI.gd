extends Node

## CardSceneUI
## Handles display of text to the player, opponent/player sprites, territory background, and race/spectator UI.
## Used by BattleManager for race textures, spectator layout, and winner name/color.
## Used by CardBattleScene for territory background.

signal leave_pressed

enum DefaultRace { USE_GAME, ELF, ORC, INFERNAL, FAIRY }

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


func apply_race_textures(
	player_sprite: Sprite2D,
	opponent_sprite: Sprite2D,
	player_default_race: int,
	opponent_default_race: int
) -> void:
	## Set Player and Opponent Sprite2D textures and race-based scale. USE_GAME = use race from code; specific race = editor override.
	var local_race := _get_local_player_race()
	var game_opponent_race := _get_opponent_race()
	var player_race: String = _default_race_to_string(player_default_race) if player_default_race != DefaultRace.USE_GAME else local_race
	var opponent_race: String = _default_race_to_string(opponent_default_race) if opponent_default_race != DefaultRace.USE_GAME else game_opponent_race
	var player_base_scale: Vector2 = player_sprite.scale if player_sprite else Vector2.ONE
	var opponent_base_scale: Vector2 = opponent_sprite.scale if opponent_sprite else Vector2.ONE
	_set_sprite_from_race(player_sprite, player_race, 1, player_default_race, player_base_scale)
	_set_sprite_from_race(opponent_sprite, opponent_race, 0, opponent_default_race, opponent_base_scale)


func apply_spectator_race_textures(player_sprite: Sprite2D, opponent_sprite: Sprite2D) -> void:
	## Spectator: top sprite = Defender (back facing), bottom sprite = Attacker (front facing).
	var attacker_id := App.pending_territory_battle_attacker_id
	var defender_id := App.pending_territory_battle_defender_id
	var attacker_race := "Fairy"
	var defender_race := "Fairy"
	for p in App.game_players:
		if int(p.get("id", -1)) == attacker_id:
			var r: String = p.get("race", "")
			attacker_race = r if r and r != "Unknown" else "Fairy"
		if int(p.get("id", -1)) == defender_id:
			var r: String = p.get("race", "")
			defender_race = r if r and r != "Unknown" else "Fairy"
	var player_base_scale: Vector2 = player_sprite.scale if player_sprite else Vector2.ONE
	var opponent_base_scale: Vector2 = opponent_sprite.scale if opponent_sprite else Vector2.ONE
	_set_sprite_from_race(player_sprite, attacker_race, 1, DefaultRace.USE_GAME, player_base_scale)
	_set_sprite_from_race(opponent_sprite, defender_race, 0, DefaultRace.USE_GAME, opponent_base_scale)


func setup_spectator_ui(
	timer_label: Control,
	timer_sub_label: Control,
	continue_label: Control,
	leave_button: BaseButton,
	debug_add_card_button: Control,
	result_label: Label,
	player_slot_nodes: Array,
	opponent_slot_nodes: Array,
	scene_root: Node
) -> void:
	## Spectator UI: hide timer, hide cards/slots, show battle status text.
	if timer_label:
		timer_label.visible = false
	if timer_sub_label:
		timer_sub_label.visible = false
	if continue_label:
		continue_label.visible = false
	if leave_button:
		leave_button.visible = true
		if not leave_button.pressed.is_connected(_on_leave_button_pressed):
			leave_button.pressed.connect(_on_leave_button_pressed)
	if debug_add_card_button:
		debug_add_card_button.visible = false

	for slot in player_slot_nodes:
		if slot:
			slot.visible = false
	for slot in opponent_slot_nodes:
		if slot:
			slot.visible = false

	if scene_root:
		var hand_container := scene_root.get_node_or_null("HandCardsLayer/HandCardsContainer") as Node2D
		if hand_container:
			hand_container.visible = false

	var attacker_name := get_player_name(App.pending_territory_battle_attacker_id)
	var defender_name := get_player_name(App.pending_territory_battle_defender_id)

	if result_label:
		result_label.text = "%s and %s are battling" % [defender_name, attacker_name]
		result_label.add_theme_font_size_override("font_size", 48)
		result_label.add_theme_color_override("font_color", Color.WHITE)
		result_label.visible = true


func get_player_name(peer_id: int) -> String:
	for p in App.game_players:
		if int(p.get("id", -1)) == peer_id:
			return str(p.get("name", "Player"))
	return "Player"


func get_player_race(peer_id: int) -> String:
	for p in App.game_players:
		if int(p.get("id", -1)) == peer_id:
			var r: String = p.get("race", "")
			if r and r != "Unknown":
				return r
	return ""


func get_race_color(race: String) -> Color:
	match race:
		"Elf":
			return Color(1, 0.9, 0.2, 1)
		"Orc":
			return Color(0.2, 0.8, 0.2, 1)
		"Fairy":
			return Color(0.7, 0.3, 0.9, 1)
		"Infernal":
			return Color(0.9, 0.2, 0.2, 1)
	return Color.WHITE


func apply_territory_background(territory_id: String, scene_root: Node) -> void:
	## Set the full-screen territory background from territory_id. Finds TerritoryBackground under scene_root.
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
	var bg: TextureRect = scene_root.get_node_or_null("BackgroundLayer/BackgroundContainer/TerritoryBackground") as TextureRect
	if bg and tex:
		bg.texture = tex


func _territory_id_to_int(tid: String) -> int:
	if tid.is_empty():
		return 0
	var s := tid
	if s.begins_with("battle_"):
		s = s.trim_prefix("battle_")
	return int(s)


func _on_leave_button_pressed() -> void:
	leave_pressed.emit()


func _get_local_player_race() -> String:
	if not App:
		return "Fairy"
	for p in App.game_players:
		if p.get("is_local", false):
			var r: String = p.get("race", "")
			return r if r and r != "Unknown" else "Fairy"
	return App.selected_race if (App.selected_race and App.selected_race != "Unknown") else "Fairy"


func _get_opponent_race() -> String:
	if not App:
		return "Fairy"
	var r: String = App.current_battle_metadata.get("opponent_race", "Fairy")
	return r if r and r != "Unknown" else "Fairy"


func _default_race_to_string(r: int) -> String:
	match r:
		DefaultRace.USE_GAME: return "fairy"
		DefaultRace.ELF: return "elf"
		DefaultRace.ORC: return "orc"
		DefaultRace.INFERNAL: return "infernal"
		DefaultRace.FAIRY: return "fairy"
	return "fairy"


func _race_scale_multiplier(race: String) -> float:
	var r := race.to_lower()
	if r == "elf":
		return 1.1
	if r == "fairy":
		return 1.0 / 1.5
	return 1.0


func _set_sprite_from_race(sprite: Sprite2D, race: String, frame_index: int, default_race: int, base_scale: Vector2) -> void:
	if sprite == null:
		return
	var path := "res://assets/%s_fb.pxo" % race.to_lower()
	var sf: SpriteFrames = load(path) as SpriteFrames
	if sf == null or not sf.has_animation("default"):
		path = "res://assets/%s_fb.pxo" % _default_race_to_string(default_race)
		sf = load(path) as SpriteFrames
	if sf and sf.has_animation("default"):
		var fc := sf.get_frame_count("default")
		var idx := clampi(frame_index, 0, maxi(0, fc - 1))
		sprite.texture = sf.get_frame_texture("default", idx)
	var mult: float = _race_scale_multiplier(race)
	sprite.scale = base_scale * mult

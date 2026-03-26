extends Node

## BotController (glue logic)
## Coordinates bot collect, command, and battle behaviors.

const BotCollectBehaviorScript := preload("res://scripts/bots/BotCollectBehavior.gd")
const BotCommandBehaviorScript := preload("res://scripts/bots/BotCommandBehavior.gd")
const BotBattleBehaviorScript := preload("res://scripts/bots/BotBattleBehavior.gd")
const BOT_TURN_DELAY_SEC := 0.6

var _collect_behavior: RefCounted
var _command_behavior: RefCounted
var _battle_behavior: RefCounted
var _last_collect_phase_key: String = ""
var _bot_turn_cooldown: float = 0.0


func _ready() -> void:
	_collect_behavior = BotCollectBehaviorScript.new()
	_command_behavior = BotCommandBehaviorScript.new()
	_battle_behavior = BotBattleBehaviorScript.new()


func initialize_single_player_bots() -> void:
	if App.is_multiplayer:
		return
	_initialize_bot_hands_if_needed()
	# Start turn tracking for single-player command flow.
	if App.turn_order.size() > 0 and App.current_turn_player_id == -1:
		App.current_turn_index = 0
		App.current_turn_player_id = int(App.turn_order[0].get("id", -1))


func process_single_player_frame(delta: float) -> void:
	if App.is_multiplayer:
		return
	if _bot_turn_cooldown > 0.0:
		_bot_turn_cooldown = maxf(0.0, _bot_turn_cooldown - delta)
		if _bot_turn_cooldown > 0.0:
			return
	_maybe_run_collect_behavior()
	_maybe_run_bot_command_turn()


func on_local_command_done() -> void:
	## Called when local player presses "Done Placing Cards" in single-player.
	if App.is_multiplayer:
		return
	if App.current_game_phase != App.GamePhase.CONTEST_COMMAND:
		return

	_advance_to_next_turn_or_phase()
	# Do not chain all bot turns here. Bot turns are processed one-at-a-time
	# by process_single_player_frame() so turn order progression stays consistent.


func on_battle_started_for_bots() -> void:
	if App.is_multiplayer:
		return
	for p in App.game_players:
		if not bool(p.get("is_local", false)):
			_battle_behavior.on_battle_started(int(p.get("id", -1)))


func _initialize_bot_hands_if_needed() -> void:
	for p in App.game_players:
		if bool(p.get("is_local", false)):
			continue
		var bot_id := int(p.get("id", -1))
		if bot_id < 0:
			continue
		if App.bot_card_collections.has(bot_id) and not App.bot_card_collections[bot_id].is_empty():
			continue
		App.bot_card_collections[bot_id] = []
		for _i in range(4):
			var card := _random_card_for_bot_race(bot_id)
			if not card.is_empty():
				App.bot_card_collections[bot_id].append(card)
		print("[BotController] Initialized bot %d with %d cards." % [bot_id, App.bot_card_collections[bot_id].size()])


func _random_card_for_bot_race(bot_player_id: int) -> Dictionary:
	var race := "Elf"
	for p in App.game_players:
		if int(p.get("id", -1)) == bot_player_id:
			race = str(p.get("race", "Elf"))
			break
	var pool: Array = []
	match race:
		"Elf":
			pool = App.ELF_CARDS
		"Orc":
			pool = App.ORC_CARDS
		"Fairy":
			pool = App.FAIRY_CARDS
		"Infernal":
			pool = App.INFERNAL_CARDS
		_:
			pool = App.MIXED_CARD_POOL
	if pool.is_empty():
		return {}
	for _i in range(pool.size()):
		var c: Dictionary = pool[randi() % pool.size()]
		var path: String = String(c.get("sprite_frames", ""))
		if not path.is_empty():
			return {"path": path, "frame": int(c.get("frame_index", 0))}
	return {}


func _is_current_turn_bot() -> bool:
	if App.current_turn_player_id == -1:
		return false
	for p in App.game_players:
		if int(p.get("id", -1)) == App.current_turn_player_id:
			return not bool(p.get("is_local", false))
	return false


func _maybe_run_bot_command_turn() -> void:
	if App.current_game_phase != App.GamePhase.CONTEST_COMMAND:
		return
	if not _is_current_turn_bot():
		return
	_initialize_bot_hands_if_needed()
	var attacked_claimed_territory: bool = _command_behavior.run_command_turn(App.current_turn_player_id)
	_refresh_territory_visuals()
	App._notify_card_count_changed()
	_advance_to_next_turn_or_phase()
	if attacked_claimed_territory:
		var pending_battles_now: Array = BattleStateManager.get_territory_ids_with_battle() if BattleStateManager else []
		if pending_battles_now.size() > 0:
			App.pending_territory_battle_ids = pending_battles_now.duplicate()
			App.territory_battle_resume_mode = "command"
			print("[BotController] Bot turn ended with battles pending: ", App.pending_territory_battle_ids)
			App.on_battle_completed()
			return
	# Add delay only when another bot turn follows (between bot turns).
	if _is_current_turn_bot() and App.current_game_phase == App.GamePhase.CONTEST_COMMAND:
		_bot_turn_cooldown = BOT_TURN_DELAY_SEC


func _advance_to_next_turn_or_phase() -> void:
	App.current_turn_index += 1
	if App.current_turn_index >= App.turn_order.size():
		# Command round finished.
		# If any territories have both defending+attacking cards, run battles first.
		# Otherwise go directly to collect phase.
		App.current_turn_index = 0
		App.current_turn_player_id = int(App.turn_order[0].get("id", -1)) if App.turn_order.size() > 0 else -1
		var pending_battles: Array = BattleStateManager.get_territory_ids_with_battle() if BattleStateManager else []
		if pending_battles.size() > 0:
			App.pending_territory_battle_ids = pending_battles.duplicate()
			# Single-player local user drives the battle sequence.
			App.is_territory_battle_attacker = true
			App.territory_battle_resume_mode = "collect"
			print("[BotController] Starting territory battle sequence: ", App.pending_territory_battle_ids)
			App.on_battle_completed()
		else:
			App.enter_collect_phase()
			_refresh_phase_ui()
		return
	App.current_turn_player_id = int(App.turn_order[App.current_turn_index].get("id", -1))
	_refresh_phase_ui()


func _refresh_phase_ui() -> void:
	var scene_root := get_tree().current_scene
	if not scene_root:
		return
	var phase_ui := scene_root.get_node_or_null("PhaseSystemUI")
	if phase_ui and phase_ui.has_method("apply_phase_ui"):
		phase_ui.apply_phase_ui()


func _refresh_territory_visuals() -> void:
	var scene_root := get_tree().current_scene
	if not scene_root:
		return
	var territory_ui := scene_root.get_node_or_null("TerritorySystemUI")
	if territory_ui and territory_ui.has_method("refresh_territory_claimed_visuals"):
		territory_ui.refresh_territory_claimed_visuals()


func _maybe_run_collect_behavior() -> void:
	# Trigger collect rewards once per relevant phase/sub-phase transition.
	var in_collect_context := (
		App.current_game_phase == App.GamePhase.COLLECT
		or (App.current_game_phase == App.GamePhase.CONTEST_CLAIM and PhaseController.map_sub_phase == PhaseController.MapSubPhase.RESOURCE_COLLECTION)
	)
	if not in_collect_context:
		_last_collect_phase_key = ""
		return

	var phase_key := "%d_%d" % [int(App.current_game_phase), int(PhaseController.map_sub_phase)]
	if phase_key == _last_collect_phase_key:
		return
	_last_collect_phase_key = phase_key

	_initialize_bot_hands_if_needed()
	for p in App.game_players:
		if bool(p.get("is_local", false)):
			continue
		_collect_behavior.run_collect_for_bot(int(p.get("id", -1)))
	App._notify_card_count_changed()

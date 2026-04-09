extends Node
const DEBUG_LOGS := false

## BotController (glue logic)
## Coordinates bot collect, command, and battle behaviors.

const BotCollectBehaviorScript := preload("res://scripts/bots/BotCollectBehavior.gd")
const BotCommandBehaviorScript := preload("res://scripts/bots/BotCommandBehavior.gd")
const BotBattleBehaviorScript := preload("res://scripts/bots/BotBattleBehavior.gd")
const BOT_PLACEMENT_DELAY_SEC := 1.0

var _collect_behavior: RefCounted
var _command_behavior: RefCounted
var _battle_behavior: RefCounted
## Bots simulate at most one "collect round" per human minigame cycle (2 minigames max, see BotCollectBehavior).
var _bot_collect_ran_for_current_zero_window: bool = false
var _bot_turn_cooldown: float = 0.0
## Multiplayer: wall-clock delay between bot actions (frame delta is unreliable for visible pacing).
var _mp_bot_placement_timer: Timer

# Step-by-step placement state (shared by SP and MP paths).
var _placing_active: bool = false
var _placing_attacked: bool = false


func _ready() -> void:
	_collect_behavior = BotCollectBehaviorScript.new()
	_command_behavior = BotCommandBehaviorScript.new()
	_battle_behavior = BotBattleBehaviorScript.new()
	_mp_bot_placement_timer = Timer.new()
	_mp_bot_placement_timer.name = "MPBotPlacementDelay"
	_mp_bot_placement_timer.wait_time = BOT_PLACEMENT_DELAY_SEC
	_mp_bot_placement_timer.one_shot = true
	add_child(_mp_bot_placement_timer)


func _get_mp() -> MultiplayerAPI:
	var tree := get_tree()
	if tree == null:
		return null
	return tree.get_multiplayer()


func initialize_single_player_bots() -> void:
	var mp := _get_mp()
	if App.is_multiplayer and not (mp and mp.has_multiplayer_peer() and mp.is_server()):
		return
	_initialize_bot_hands_if_needed()
	if not App.is_multiplayer and App.turn_order.size() > 0 and App.current_turn_player_id == -1:
		App.current_turn_index = 0
		App.current_turn_player_id = int(App.turn_order[0].get("id", -1))


func process_single_player_frame(delta: float) -> void:
	var mp := _get_mp()
	if App.is_multiplayer and not (mp and mp.has_multiplayer_peer() and mp.is_server()):
		return
	# Block bot actions while a phase transition overlay is animating
	if App.phase_transition_animating:
		return
	if App.is_multiplayer:
		if _mp_bot_placement_timer != null and not _mp_bot_placement_timer.is_stopped():
			return
	else:
		if _bot_turn_cooldown > 0.0:
			_bot_turn_cooldown = maxf(0.0, _bot_turn_cooldown - delta)
			if _bot_turn_cooldown > 0.0:
				return
	_maybe_run_collect_behavior()
	if App.is_multiplayer:
		_maybe_run_multiplayer_bot_command_turn()
	else:
		_maybe_run_bot_command_turn()


func _start_mp_bot_placement_delay() -> void:
	if _mp_bot_placement_timer:
		_mp_bot_placement_timer.start()


func on_local_command_done() -> void:
	if App.is_multiplayer:
		return
	if App.current_game_phase != App.GamePhase.CONTEST_COMMAND:
		return
	_advance_to_next_turn_or_phase()


func on_battle_started_for_bots() -> void:
	var mp := _get_mp()
	if App.is_multiplayer and not (mp and mp.has_multiplayer_peer() and mp.is_server()):
		return
	for p in App.game_players:
		if bool(p.get("is_bot", false)):
			_battle_behavior.on_battle_started(int(p.get("id", -1)))


# ---------- BOT HAND INIT ----------

func _initialize_bot_hands_if_needed() -> void:
	## Deal the opening 4 cards once per bot per match. Do not refill when the hand is empty later
	## (cards spent on territories / battles stay gone until collect phase adds more).
	for p in App.game_players:
		if not bool(p.get("is_bot", false)):
			continue
		var bot_id := int(p.get("id", -1))
		if bot_id == -1:
			continue
		if bool(App.bot_initial_hand_dealt.get(bot_id, false)):
			continue
		App.bot_initial_hand_dealt[bot_id] = true
		if not App.bot_card_collections.has(bot_id):
			App.bot_card_collections[bot_id] = []
		if not App.bot_card_collections[bot_id].is_empty():
			if DEBUG_LOGS: print("[BotController] Bot %d already has %d cards; skipping opening deal." % [bot_id, App.bot_card_collections[bot_id].size()])
			continue
		for _i in range(4):
			var card := _random_card_for_bot_race(bot_id)
			if not card.is_empty():
				App.bot_card_collections[bot_id].append(card)
		if DEBUG_LOGS: print("[BotController] Opening hand: bot %d dealt %d cards." % [bot_id, App.bot_card_collections[bot_id].size()])
	var mp_h := _get_mp()
	if App.is_multiplayer and mp_h and mp_h.has_multiplayer_peer() and mp_h.is_server():
		PhaseSync.host_sync_bot_card_counts()


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


# ---------- TURN DETECTION ----------

func _is_current_turn_bot() -> bool:
	var current_id: int = App.current_turn_player_id if not App.is_multiplayer else PhaseController.current_turn_peer_id
	if current_id == -1:
		return false
	for p in App.game_players:
		if int(p.get("id", -1)) == current_id:
			return bool(p.get("is_bot", false))
	return false


# ---------- SINGLE-PLAYER COMMAND ----------

func _maybe_run_bot_command_turn() -> void:
	if App.current_game_phase != App.GamePhase.CONTEST_COMMAND:
		return
	if not _is_current_turn_bot():
		return

	if not _placing_active:
		_initialize_bot_hands_if_needed()
		var bot_id_sp: int = App.current_turn_player_id
		var diff_sp: int = int(PlayerDataSync.get_bot_difficulty(bot_id_sp))
		_command_behavior.prepare_turn(bot_id_sp, diff_sp)
		_placing_active = true
		_placing_attacked = false
		# Ensure a visible delay before the first placement too.
		_bot_turn_cooldown = BOT_PLACEMENT_DELAY_SEC
		return

	var result: Dictionary = _command_behavior.place_next()
	_placing_attacked = _placing_attacked or result.get("attacked", false)
	_refresh_territory_visuals()
	App._notify_card_count_changed()

	if result.get("done", true):
		_placing_active = false
		_advance_to_next_turn_or_phase()
		if _placing_attacked or _command_behavior.did_attack_claimed():
			var pending_battles_now: Array = BattleStateManager.get_territory_ids_with_battle() if BattleStateManager else []
			if pending_battles_now.size() > 0:
				App.pending_territory_battle_ids = pending_battles_now.duplicate()
				App.territory_battle_resume_mode = "command"
				if DEBUG_LOGS: print("[BotController] Bot turn ended with battles pending: ", App.pending_territory_battle_ids)
				App.on_battle_completed()
				return
		if _is_current_turn_bot() and App.current_game_phase == App.GamePhase.CONTEST_COMMAND:
			_bot_turn_cooldown = BOT_PLACEMENT_DELAY_SEC
	else:
		_bot_turn_cooldown = BOT_PLACEMENT_DELAY_SEC


# ---------- MULTIPLAYER COMMAND ----------

func _maybe_run_multiplayer_bot_command_turn() -> void:
	var mp := _get_mp()
	if not mp or not mp.has_multiplayer_peer() or not mp.is_server():
		return
	if PhaseController.current_phase != 0:
		_placing_active = false
		if _mp_bot_placement_timer:
			_mp_bot_placement_timer.stop()
		return
	if not _is_current_turn_bot():
		_placing_active = false
		if _mp_bot_placement_timer:
			_mp_bot_placement_timer.stop()
		return

	# Start a new bot turn: prepare, then do the first placement.
	if not _placing_active:
		var bot_id: int = PhaseController.current_turn_peer_id
		_initialize_bot_hands_if_needed()
		var diff_mp: int = int(PlayerDataSync.get_bot_difficulty(bot_id))
		_command_behavior.prepare_turn(bot_id, diff_mp)
		_placing_active = true
		_placing_attacked = false
		# Ensure a visible delay before the first placement too.
		_start_mp_bot_placement_delay()
		return

	var result: Dictionary = _command_behavior.place_next()
	_placing_attacked = _placing_attacked or result.get("attacked", false)
	_refresh_territory_visuals()
	PhaseSync.host_sync_bot_card_counts()

	if result.get("done", true):
		_placing_active = false
		var attacked: bool = _placing_attacked or _command_behavior.did_attack_claimed()
		# Check for battles BEFORE advancing the turn.
		if attacked:
			var raw_battles: Array = BattleStateManager.get_territory_ids_with_battle() if BattleStateManager else []
			var pending_battles_now: Array = []
			for tid_str in raw_battles:
				if App.territory_pending_attackers.has(int(tid_str)):
					pending_battles_now.append(tid_str)
				elif BattleStateManager:
					BattleStateManager.clear_attacking_slots(str(tid_str))
			if pending_battles_now.size() > 0:
				App.pending_territory_battle_ids = pending_battles_now.duplicate()
				App.territory_battle_resume_mode = "mp_command"
				App.is_territory_battle_attacker = true
				if DEBUG_LOGS: print("[BotController] MP bot turn ended with battles pending: ", App.pending_territory_battle_ids)
				App.on_battle_completed()
				return
		# No battles — advance the turn now.
		PhaseSync.host_advance_bot_command_turn()
		if _is_current_turn_bot() and PhaseController.current_phase == 0:
			_start_mp_bot_placement_delay()
	else:
		## More placements this turn — wait 1s (wall clock) before next territory.
		_start_mp_bot_placement_delay()


# ---------- TURN ADVANCEMENT (SINGLE-PLAYER) ----------

func _advance_to_next_turn_or_phase() -> void:
	App.current_turn_index += 1
	if App.current_turn_index >= App.turn_order.size():
		App.current_turn_index = 0
		App.current_turn_player_id = int(App.turn_order[0].get("id", -1)) if App.turn_order.size() > 0 else -1
		var raw_battles: Array = BattleStateManager.get_territory_ids_with_battle() if BattleStateManager else []
		var pending_battles: Array = []
		for tid_str in raw_battles:
			if App.territory_pending_attackers.has(int(tid_str)):
				pending_battles.append(tid_str)
			elif BattleStateManager:
				BattleStateManager.clear_attacking_slots(str(tid_str))
		if pending_battles.size() > 0:
			App.pending_territory_battle_ids = pending_battles.duplicate()
			App.is_territory_battle_attacker = true
			App.territory_battle_resume_mode = "collect"
			if DEBUG_LOGS: print("[BotController] Starting territory battle sequence: ", App.pending_territory_battle_ids)
			App.on_battle_completed()
		else:
			App.enter_collect_phase()
			_refresh_phase_ui()
		return
	App.current_turn_player_id = int(App.turn_order[App.current_turn_index].get("id", -1))
	_refresh_phase_ui()


# ---------- UI REFRESH HELPERS ----------

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


# ---------- COLLECT PHASE ----------

func _maybe_run_collect_behavior() -> void:
	## Match GameIntro._is_collect_phase(): COLLECT always, or claim phase only during resource collection.
	var in_collect_context := (
		App.current_game_phase == App.GamePhase.COLLECT
		or (
			App.current_game_phase == App.GamePhase.CONTEST_CLAIM
			and PhaseController.map_sub_phase == PhaseController.MapSubPhase.RESOURCE_COLLECTION
		)
	)
	if not in_collect_context:
		_bot_collect_ran_for_current_zero_window = false
		return

	## One bot collect pass per "round" while no one has used a minigame slot yet (avoids firing every map_sub change).
	if _any_minigame_started_this_collect_round():
		_bot_collect_ran_for_current_zero_window = false
		return
	if _bot_collect_ran_for_current_zero_window:
		return
	_bot_collect_ran_for_current_zero_window = true

	## Do NOT call _initialize_bot_hands_if_needed() here: an empty bot hand would get 4 "starter"
	## cards plus up to 4 collect cards in the same pass (e.g. 5+ total). Refill happens at command turn.
	for p in App.game_players:
		if not bool(p.get("is_bot", false)):
			continue
		_collect_behavior.run_collect_for_bot(int(p.get("id", -1)))
	var mp_c := _get_mp()
	if App.is_multiplayer and mp_c and mp_c.has_multiplayer_peer() and mp_c.is_server():
		PhaseSync.host_sync_bot_card_counts()
	else:
		App._notify_card_count_changed()


func _any_minigame_started_this_collect_round() -> bool:
	if App.minigames_completed_this_phase > 0:
		return true
	for _pid in PhaseController.player_minigame_counts.keys():
		if int(PhaseController.player_minigame_counts[_pid]) > 0:
			return true
	return false

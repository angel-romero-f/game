extends Node

## PhaseController — Local phase state machine (autoload singleton).
## Holds phase/turn/done state and emits signals on changes.
## Contains NO networking logic — pure local state + signals.
##
## phase=0  CONTEST_COMMAND (turn-ordered card placement)
## phase=1  CONTEST_CLAIM (sub=CLAIMING/RESOURCE_COLLECTION/BATTLE_READY)
## phase=2  COLLECT

enum MapSubPhase { CLAIMING = 0, RESOURCE_COLLECTION = 1, BATTLE_READY = 2 }

# Current game phase (see comments above)
var current_phase: int = 0
# Map sub-phase (used within phase=1 CONTEST_CLAIM)
var map_sub_phase: int = MapSubPhase.CLAIMING
# Per-player done state: {peer_id: bool}
var player_done_state: Dictionary = {}
# Per-player minigame counts: {peer_id: int}
var player_minigame_counts: Dictionary = {}
# Per-player card counts: {peer_id: int}
var player_card_counts: Dictionary = {}
# Active turn peer and position
var current_turn_peer_id: int = -1
var current_turn_index: int = 0

signal phase_changed(phase_id: int)
signal turn_changed(peer_id: int)
signal card_counts_updated
@warning_ignore("unused_signal")
signal done_counts_updated(done_count: int, total: int)
signal map_sub_phase_changed(sub_phase: int)
signal claiming_turn_finished(has_battles: bool)

## Set phase and emit signal
func set_phase(phase_id: int) -> void:
	current_phase = phase_id
	phase_changed.emit(phase_id)

## Set current turn and emit signal
func set_turn(peer_id: int) -> void:
	current_turn_peer_id = peer_id
	turn_changed.emit(peer_id)

## Set map sub-phase and emit signal — ONLY when value actually changes.
func set_map_sub_phase(sub_phase: int) -> void:
	if map_sub_phase == sub_phase:
		return
	map_sub_phase = sub_phase
	map_sub_phase_changed.emit(sub_phase)

## Initialize done state for all players at phase start
func init_done_state(peer_ids: Array) -> void:
	player_done_state.clear()
	player_minigame_counts.clear()
	for pid in peer_ids:
		player_done_state[pid] = false
		player_minigame_counts[pid] = 0

## Apply done state received from server
func apply_done_state(done_state: Dictionary, minigame_counts: Dictionary) -> void:
	player_done_state = done_state.duplicate()
	player_minigame_counts = minigame_counts.duplicate()

## Mark a player as done
func mark_done(peer_id: int) -> void:
	player_done_state[peer_id] = true

## Increment a player's minigame count and return new count
func increment_minigame(peer_id: int) -> int:
	var count: int = player_minigame_counts.get(peer_id, 0) + 1
	player_minigame_counts[peer_id] = count
	return count

## Count how many players are done (among provided peer IDs)
func count_done_players(peer_ids: Array) -> int:
	var count := 0
	for pid in peer_ids:
		if player_done_state.get(pid, false):
			count += 1
	return count

## Finish the CLAIMING turn: check for pending battles or request end-turn.
## Only valid in CONTEST_CLAIM + CLAIMING. In MP, only active turn player may execute.
func finish_claiming_turn() -> void:
	# Must only run during claim-conquer claiming turn, never during command/collect.
	if current_phase != 1 or map_sub_phase != MapSubPhase.CLAIMING:
		print("[DEBUG] Finish Claiming skipped — invalid phase/sub (phase=%d sub=%d)" % [current_phase, map_sub_phase])
		return

	var has_battles := false
	if BattleStateManager:
		App.pending_territory_battle_ids = BattleStateManager.get_territory_ids_with_battle()
		print("[DEBUG] Finish Claiming. Pending Battle IDs: ", App.pending_territory_battle_ids)

	if App.is_multiplayer and App.get_tree().get_multiplayer().has_multiplayer_peer():
		var my_id := App.get_tree().get_multiplayer().get_unique_id()
		if my_id != current_turn_peer_id:
			print("[DEBUG] Finish Claiming ignored — not my turn (my_id=%d turn=%d)" % [my_id, current_turn_peer_id])
			return

	if App.pending_territory_battle_ids.size() > 0:
		has_battles = true
		App.is_territory_battle_attacker = true
		if App.is_multiplayer and App.get_tree().get_multiplayer().has_multiplayer_peer():
			print("[DEBUG] Battles found! Starting battle sequence.")
			App.on_battle_completed()  # Pops first battle and starts it
		else:
			print("[DEBUG] Battles found! calling App.on_battle_completed() to start first battle.")
			App.on_battle_completed()
	else:
		if App.is_multiplayer and App.get_tree().get_multiplayer().has_multiplayer_peer():
			print("[DEBUG] No battles, active player requesting end claiming turn")
			PhaseSync.request_end_claiming_turn()
		else:
			print("[DEBUG] No battles found (Single Player).")
	claiming_turn_finished.emit(has_battles)

## Map PhaseController.current_phase -> App.current_game_phase + phase_transition_text.
func sync_app_game_phase() -> void:
	match current_phase:
		0:
			App.current_game_phase = App.GamePhase.CONTEST_COMMAND
			App.phase_transition_text = "Contest"
		1:
			App.current_game_phase = App.GamePhase.CONTEST_CLAIM
			# The sub-phase controls whether this feels like claiming or collecting.
			if map_sub_phase == MapSubPhase.RESOURCE_COLLECTION:
				App.phase_transition_text = "Collect"
			else:
				App.phase_transition_text = "Contest"
		2:
			App.current_game_phase = App.GamePhase.COLLECT
			App.phase_transition_text = "Collect"
		_:
			App.current_game_phase = App.GamePhase.CONTEST_COMMAND
			App.phase_transition_text = "Contest"

## Transition to RESOURCE_COLLECTION sub-phase (reset minigame count)
func enter_resource_collection() -> void:
	App.minigames_completed_this_phase = 0
	App.region_bonus_used_this_phase.clear()
	set_map_sub_phase(MapSubPhase.RESOURCE_COLLECTION)

## Transition to next CLAIMING round (reset minigame count)
func enter_next_claiming_round() -> void:
	App.minigames_completed_this_phase = 0
	set_map_sub_phase(MapSubPhase.CLAIMING)

## Apply card counts received from server
func apply_card_counts(counts: Dictionary) -> void:
	player_card_counts = counts.duplicate()
	card_counts_updated.emit()

## Update a single player's card count
func set_card_count(peer_id: int, count: int) -> void:
	player_card_counts[peer_id] = count
	card_counts_updated.emit()

## Reset phase state for a new round (preserves card counts)
func reset() -> void:
	current_phase = 0
	map_sub_phase = MapSubPhase.CLAIMING
	player_done_state.clear()
	player_minigame_counts.clear()
	current_turn_peer_id = -1
	current_turn_index = 0

## Full reset for a brand new game
func full_reset() -> void:
	reset()
	player_card_counts.clear()

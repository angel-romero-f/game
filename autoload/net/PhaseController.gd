extends Node

## PhaseController — Local phase state machine.
## Holds phase/turn/done state and emits signals on changes.
## Contains NO networking logic — pure local state management.

# Current game phase: 0 = CARD_COMMAND, 1 = CLAIM_CONQUER, 2 = CARD_COLLECTION
var current_phase: int = 0
# Map sub-phase within CLAIM_CONQUER: 0 = CLAIMING, 1 = RESOURCE_COLLECTION, 2 = BATTLE_READY
var map_sub_phase: int = 0
# Per-player done state in current phase: {peer_id: bool}
var player_done_state: Dictionary = {}
# Per-player minigame counts for Card Collection phase: {peer_id: int}
var player_minigame_counts: Dictionary = {}
# Current player's turn (peer_id)
var current_turn_peer_id: int = -1
# Current position in turn order
var current_turn_index: int = 0

signal phase_changed(phase_id: int)
signal turn_changed(peer_id: int)
@warning_ignore("unused_signal")
signal done_counts_updated(done_count: int, total: int)
signal map_sub_phase_changed(sub_phase: int)

## Set phase and emit signal
func set_phase(phase_id: int) -> void:
	current_phase = phase_id
	phase_changed.emit(phase_id)

## Set current turn and emit signal
func set_turn(peer_id: int) -> void:
	current_turn_peer_id = peer_id
	turn_changed.emit(peer_id)

## Set map sub-phase and emit signal
func set_map_sub_phase(sub_phase: int) -> void:
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

## Reset all phase-related state for a new game
func reset() -> void:
	current_phase = 0
	map_sub_phase = 0
	player_done_state.clear()
	player_minigame_counts.clear()
	current_turn_peer_id = -1
	current_turn_index = 0

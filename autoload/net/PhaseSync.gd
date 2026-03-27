extends Node

## PhaseSync — Network synchronization for game phases and turns.
## Server-authoritative RPCs that delegate state updates to PhaseController.
## Also contains game flow RPCs (start_race_select, start_game).

# ---------- GAME FLOW RPCs ----------

## RPC: Start the multiplayer race selection screen (called by host).
@rpc("authority", "call_local", "reliable")
func start_race_select() -> void:
	if multiplayer.is_server():
		PlayerDataSync._sync_player_races()
	App.go("res://scenes/ui/MultiplayerRaceSelect.tscn")

## RPC: Start the game (called by host, transitions everyone to GameIntro scene).
## Host passes the complete names/races dicts and bot ID list so clients get bot entries atomically.
@rpc("authority", "call_local", "reliable")
func start_game(all_names: Dictionary = {}, all_races: Dictionary = {}, bot_ids: Array = []) -> void:
	if not all_names.is_empty():
		PlayerDataSync.player_names = all_names.duplicate(true)
	if not all_races.is_empty():
		PlayerDataSync.player_races = all_races.duplicate(true)
	if not bot_ids.is_empty():
		PlayerDataSync.register_bot_ids(bot_ids)
	App.setup_multiplayer_game()
	App.go("res://scenes/ui/game_intro.tscn")

# ---------- CONTEST COMMAND PHASE ----------

## Host: Initialize Contest Command phase for all participants
func host_init_contest_command_phase() -> void:
	if not multiplayer.is_server():
		return

	PhaseController.reset()
	BattleSync.reset_battle_state()
	if BattleStateManager:
		BattleStateManager.clear_all_attacking_slots()
	PhaseController.current_phase = 0  # CONTEST_COMMAND
	PhaseController.init_done_state(NetworkManager.get_all_peer_ids())

	# Set first player's turn based on turn order
	if App.turn_order.size() > 0:
		var first_player = App.turn_order[0]
		PhaseController.current_turn_peer_id = first_player.get("id", -1)
		PhaseController.current_turn_index = 0
	else:
		PhaseController.current_turn_peer_id = multiplayer.get_unique_id()
		PhaseController.current_turn_index = 0

	var all_peers := NetworkManager.get_all_peer_ids()
	var total := all_peers.size()
	print("[PhaseSync] Host init Contest Command phase with ", total, " participants. First turn: ", PhaseController.current_turn_peer_id)

	# IMPORTANT: Sync turn and done state BEFORE phase change, because phase_changed
	# signal triggers UI update which reads current_turn_peer_id
	rpc_set_current_turn.rpc(PhaseController.current_turn_peer_id)
	rpc_sync_done_state.rpc(PhaseController.player_done_state.duplicate(), PhaseController.player_minigame_counts.duplicate())
	rpc_sync_done_counts.rpc(0, total)
	rpc_map_sub_phase.rpc(0)  # Reset map sub-phase to CLAIMING
	if not PhaseController.player_card_counts.is_empty():
		rpc_sync_card_counts.rpc(PhaseController.player_card_counts.duplicate())
	rpc_set_phase.rpc(0)  # Must be last - triggers UI update

## Host: Initialize Collect phase (after all players finish their turns)
func host_init_collect_phase() -> void:
	if not multiplayer.is_server():
		return

	PhaseController.current_phase = 2  # COLLECT
	PhaseController.init_done_state(NetworkManager.get_all_peer_ids())

	var all_peers := NetworkManager.get_all_peer_ids()
	var total := all_peers.size()
	print("[PhaseSync] Host init Collect phase with ", total, " participants")

	# Sync done state BEFORE phase change (phase_changed triggers UI update)
	rpc_sync_done_state.rpc(PhaseController.player_done_state.duplicate(), PhaseController.player_minigame_counts.duplicate())
	rpc_sync_done_counts.rpc(0, total)
	rpc_set_phase.rpc(2)  # Must be last - triggers UI update

# ---------- TURN MANAGEMENT ----------

## Authority broadcasts current turn player
@rpc("authority", "call_local", "reliable")
func rpc_set_current_turn(peer_id: int) -> void:
	PhaseController.set_turn(peer_id)
	if multiplayer.is_server():
		print("[HOST PhaseSync] Turn → peer %d" % peer_id)

## Client requests to end their Contest Command turn
func request_end_contest_command_turn() -> void:
	if multiplayer.is_server():
		_server_advance_contest_command_turn(multiplayer.get_unique_id())
	else:
		server_end_contest_command_turn.rpc_id(1)

@rpc("any_peer", "reliable")
func server_end_contest_command_turn() -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = multiplayer.get_unique_id()
	_server_advance_contest_command_turn(id)

func _server_advance_contest_command_turn(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	if peer_id != PhaseController.current_turn_peer_id:
		print("[PhaseSync] REJECTED turn end from ", peer_id, " (not their turn, current: ", PhaseController.current_turn_peer_id, ")")
		return

	print("[PhaseSync] Player ", peer_id, " finished Contest Command turn (index ", PhaseController.current_turn_index, ")")

	PhaseController.player_done_state[peer_id] = true

	PhaseController.current_turn_index += 1
	if PhaseController.current_turn_index >= App.turn_order.size():
		var pending_battles: Array = BattleStateManager.get_territory_ids_with_battle() if BattleStateManager else []
		if pending_battles.size() > 0:
			print("[PhaseSync] All command turns done — %d territory battles pending. Starting battle sequence." % pending_battles.size())
			App.pending_territory_battle_ids = pending_battles.duplicate()
			App.territory_battle_resume_mode = "mp_collect"
			App.is_territory_battle_attacker = true
			App.on_battle_completed()
			return
		print("[PhaseSync] All players finished Contest Command - entering Contest Claim")
		_server_enter_contest_claim_phase()
	else:
		var next_player = App.turn_order[PhaseController.current_turn_index]
		PhaseController.current_turn_peer_id = next_player.get("id", -1)
		print("[PhaseSync] Next Contest Command turn: ", PhaseController.current_turn_peer_id, " (index ", PhaseController.current_turn_index, ")")
		rpc_set_current_turn.rpc(PhaseController.current_turn_peer_id)
		rpc_sync_done_state.rpc(PhaseController.player_done_state.duplicate(), PhaseController.player_minigame_counts.duplicate())

func host_advance_bot_command_turn() -> void:
	if not multiplayer.is_server():
		return
	if PhaseController.current_phase != 0:
		return
	var current_id: int = PhaseController.current_turn_peer_id
	for p in App.game_players:
		if int(p.get("id", -1)) == current_id and bool(p.get("is_bot", false)):
			_server_advance_contest_command_turn(current_id)
			return

func host_sync_bot_card_counts() -> void:
	if not multiplayer.is_server():
		return
	for p in App.game_players:
		if not bool(p.get("is_bot", false)):
			continue
		var pid: int = int(p.get("id", -1))
		PhaseController.player_card_counts[pid] = int(App.bot_card_collections.get(pid, []).size())
	rpc_sync_card_counts.rpc(PhaseController.player_card_counts.duplicate())

# ---------- CLAIMING TURNS ----------

func request_end_claiming_turn() -> void:
	if multiplayer.is_server():
		_server_advance_claiming_turn(multiplayer.get_unique_id())
	else:
		server_end_claiming_turn.rpc_id(1)

@rpc("any_peer", "reliable")
func server_end_claiming_turn() -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = multiplayer.get_unique_id()
	_server_advance_claiming_turn(id)

func _server_advance_claiming_turn(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	if peer_id != PhaseController.current_turn_peer_id:
		print("[PhaseSync] REJECTED claiming turn end from ", peer_id, " (not their turn)")
		return
	PhaseController.current_turn_index += 1
	if PhaseController.current_turn_index >= App.turn_order.size():
		# All players have had their claiming turn - advance to RESOURCE_COLLECTION
		PhaseController.init_done_state(NetworkManager.get_all_peer_ids())
		rpc_sync_done_state.rpc(PhaseController.player_done_state.duplicate(), PhaseController.player_minigame_counts.duplicate())
		rpc_map_sub_phase.rpc(1)
	else:
		var next_player = App.turn_order[PhaseController.current_turn_index]
		PhaseController.current_turn_peer_id = next_player.get("id", -1)
		rpc_set_current_turn.rpc(PhaseController.current_turn_peer_id)

# ---------- DONE STATE / MINIGAME TRACKING ----------

## Client requests to increment their minigame count
func request_increment_minigame() -> void:
	if multiplayer.is_server():
		_server_increment_minigame(multiplayer.get_unique_id())
	else:
		server_increment_minigame.rpc_id(1)

@rpc("any_peer", "reliable")
func server_increment_minigame() -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = multiplayer.get_unique_id()
	_server_increment_minigame(id)

func _server_increment_minigame(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	# Minigames only count during Contest Claim resource collection.
	if PhaseController.current_phase != 1 or PhaseController.map_sub_phase != PhaseController.MapSubPhase.RESOURCE_COLLECTION:
		print("[PhaseSync] REJECTED minigame increment from ", peer_id, " (phase=", PhaseController.current_phase, " sub=", PhaseController.map_sub_phase, ")")
		return
	if PhaseController.player_done_state.get(peer_id, false):
		print("[PhaseSync] REJECTED minigame increment from ", peer_id, " (already done)")
		return
	var current_count: int = PhaseController.player_minigame_counts.get(peer_id, 0)
	if current_count >= 2:
		print("[PhaseSync] REJECTED minigame increment from ", peer_id, " (already at 2)")
		return

	var count: int = PhaseController.increment_minigame(peer_id)
	print("[PhaseSync] Player ", peer_id, " minigame count: ", count)

	if count >= 2:
		PhaseController.mark_done(peer_id)
		print("[PhaseSync] Player ", peer_id, " auto-marked done (2 minigames)")

	_check_all_done_and_advance()

## Client requests to skip (mark done early)
func request_skip_to_done() -> void:
	if multiplayer.is_server():
		_server_mark_done(multiplayer.get_unique_id())
	else:
		server_skip_to_done.rpc_id(1)

@rpc("any_peer", "reliable")
func server_skip_to_done() -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = multiplayer.get_unique_id()
	_server_mark_done(id)

func _server_mark_done(peer_id: int) -> void:
	PhaseController.mark_done(peer_id)
	print("[PhaseSync] Player ", peer_id, " marked done (skip)")
	_check_all_done_and_advance()

## Check if all players are done and advance phase if so
func _check_all_done_and_advance() -> void:
	if not multiplayer.is_server():
		return
	var all_peers := NetworkManager.get_all_peer_ids()
	var done_count := PhaseController.count_done_players(all_peers)
	var total := all_peers.size()

	rpc_sync_done_state.rpc(PhaseController.player_done_state.duplicate(), PhaseController.player_minigame_counts.duplicate())
	rpc_sync_done_counts.rpc(done_count, total)

	if total > 0 and done_count >= total:
		if PhaseController.current_phase == 0:  # CONTEST_COMMAND -> CONTEST_CLAIM
			_server_enter_contest_claim_phase()
		elif PhaseController.current_phase == 1:  # CONTEST_CLAIM
			if PhaseController.map_sub_phase == 1:  # RESOURCE_COLLECTION done → advance to CONTEST_COMMAND
				host_init_contest_command_phase()
			else:  # CLAIMING or BATTLE_READY done → loop back to contest claim
				server_enter_contest_claim_from_battles()
		elif PhaseController.current_phase == 2:  # COLLECT -> CONTEST_COMMAND (loop)
			host_init_contest_command_phase()

# ---------- PHASE TRANSITION RPCs ----------

## Authority broadcasts new phase
@rpc("authority", "call_local", "reliable")
func rpc_set_phase(phase_id: int) -> void:
	PhaseController.set_phase(phase_id)
	if multiplayer.is_server():
		print("[HOST PhaseSync] Phase → %d ('%s')" % [phase_id, App.phase_transition_text])

## Authority broadcasts done state dictionaries to clients
@rpc("authority", "call_local", "reliable")
func rpc_sync_done_state(done_state: Dictionary, minigame_counts: Dictionary) -> void:
	PhaseController.apply_done_state(done_state, minigame_counts)

## Authority broadcasts done counts
@rpc("authority", "call_local", "reliable")
func rpc_sync_done_counts(done: int, total: int) -> void:
	PhaseController.done_counts_updated.emit(done, total)

## Authority broadcasts map sub-phase change
@rpc("authority", "call_local", "reliable")
func rpc_map_sub_phase(sub_phase: int) -> void:
	PhaseController.set_map_sub_phase(sub_phase)

# ---------- CARD COUNT SYNC ----------

## Client reports its card count to the server; server broadcasts all counts.
func report_card_count() -> void:
	var count := App.player_card_collection.size()
	if not multiplayer.has_multiplayer_peer():
		return
	if multiplayer.is_server():
		_server_receive_card_count(multiplayer.get_unique_id(), count)
	else:
		server_receive_card_count.rpc_id(1, count)

@rpc("any_peer", "reliable")
func server_receive_card_count(count: int) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = multiplayer.get_unique_id()
	_server_receive_card_count(id, count)

func _server_receive_card_count(peer_id: int, count: int) -> void:
	PhaseController.player_card_counts[peer_id] = count
	rpc_sync_card_counts.rpc(PhaseController.player_card_counts.duplicate())

@rpc("authority", "call_local", "reliable")
func rpc_sync_card_counts(counts: Dictionary) -> void:
	PhaseController.apply_card_counts(counts)

# ---------- CLAIM & CONQUER PHASE TRANSITIONS ----------

## Server enters Contest Claim phase (from CONTEST_COMMAND, skips CLAIMING)
func _server_enter_contest_claim_phase() -> void:
	if not multiplayer.is_server():
		return
	PhaseController.current_phase = 1  # CONTEST_CLAIM
	BattleSync.init_battle_phase()
	PhaseController.init_done_state(NetworkManager.get_all_peer_ids())
	App.minigames_completed_this_phase = 0
	rpc_sync_done_state.rpc(PhaseController.player_done_state.duplicate(), PhaseController.player_minigame_counts.duplicate())
	rpc_set_phase.rpc(1)
	rpc_map_sub_phase.rpc(1)  # RESOURCE_COLLECTION

## Server enters Contest Claim from battles (loop back)
func server_enter_contest_claim_from_battles() -> void:
	if not multiplayer.is_server():
		return
	PhaseController.current_phase = 1  # CONTEST_CLAIM
	BattleSync.init_battle_phase()
	PhaseController.current_turn_index = 0
	if App.turn_order.size() > 0:
		PhaseController.current_turn_peer_id = App.turn_order[0].get("id", -1)
	else:
		PhaseController.current_turn_peer_id = multiplayer.get_unique_id()
	PhaseController.init_done_state(NetworkManager.get_all_peer_ids())
	App.minigames_completed_this_phase = 0
	rpc_set_current_turn.rpc(PhaseController.current_turn_peer_id)
	rpc_sync_done_state.rpc(PhaseController.player_done_state.duplicate(), PhaseController.player_minigame_counts.duplicate())
	rpc_sync_done_counts.rpc(0, NetworkManager.get_all_peer_ids().size())
	rpc_set_phase.rpc(1)
	rpc_map_sub_phase.rpc(0)  # CLAIMING first

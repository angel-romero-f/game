extends Node

## BattleSync — Battle card placement, ready state, decision system, and territory battles.
## Server-authoritative: clients send requests, server validates and broadcasts.

# ---------- CARD BATTLE STATE ----------
# peer_id -> { slot_index (0-2) -> { "path": String, "frame": int } }
var battle_placed_cards: Dictionary = {}
# peer_id -> true when that player has pressed Start Battle
var battle_ready_peers: Dictionary = {}

signal battle_cards_updated
signal battle_start_requested
signal battle_player_left(peer_id: int)

# ---------- BATTLE DECISION STATE ----------
var battle_decision_index: int = 0
var battle_decider_peer_id: int = -1
# Each player's battle choice: {peer_id: "LEFT"/"RIGHT"/"SKIP"/"UNDECIDED"}
var battle_choices: Dictionary = {}
# Queues for each battle option (max 2 each)
var left_queue: Array = []
var right_queue: Array = []
# Whether a battle is currently in progress
var battle_in_progress: bool = false
# The 2 participants in the active battle
var active_battle_participants: Array = []
# Which side the active battle is for
var active_battle_side: String = ""
# Reports from participants that they finished the battle
var battle_finished_reports: Dictionary = {}

# Territory battle: participant ids (set when start_territory_battle runs)
var territory_battle_attacker_id: int = -1
var territory_battle_defender_id: int = -1

signal battle_decider_changed(peer_id: int)
signal battle_choices_updated(snapshot: Dictionary)
signal battle_started(p1_id: int, p2_id: int, side: String)
signal battle_finished_broadcast()

# ---------- STATE MANAGEMENT ----------

## Clear card battle state when leaving battle scene
func clear_battle_state() -> void:
	var caller_role := "SERVER" if multiplayer.is_server() else "CLIENT"
	var old_keys: Array = battle_placed_cards.keys()
	print("[BattleSync] clear_battle_state() called by %s (peer %d). Clearing peer keys: %s" % [caller_role, multiplayer.get_unique_id(), str(old_keys)])
	battle_placed_cards.clear()
	battle_ready_peers.clear()

## Reset all battle decision state for a new phase
func reset_battle_state() -> void:
	battle_decision_index = 0
	battle_decider_peer_id = -1
	battle_choices.clear()
	left_queue.clear()
	right_queue.clear()
	battle_in_progress = false
	active_battle_participants.clear()
	active_battle_side = ""
	battle_finished_reports.clear()

# ---------- CARD PLACEMENT RPCs ----------

## Request to place a card (client -> server)
func request_place_battle_card(slot_index: int, sprite_frames_path: String, frame_index: int) -> void:
	if multiplayer.is_server():
		_server_place_battle_card(multiplayer.get_unique_id(), slot_index, sprite_frames_path, frame_index)
	else:
		place_battle_card.rpc_id(1, slot_index, sprite_frames_path, frame_index)

## Request to remove a card from a slot
func request_remove_battle_card(slot_index: int) -> void:
	if multiplayer.is_server():
		_server_remove_battle_card(multiplayer.get_unique_id(), slot_index)
	else:
		remove_battle_card.rpc_id(1, slot_index)

## Request to clear all of the calling peer's battle cards (e.g. after losing). Removes slots 0, 1, 2.
func request_clear_my_battle_cards() -> void:
	for slot_index in range(3):
		request_remove_battle_card(slot_index)

@rpc("any_peer", "reliable")
func place_battle_card(slot_index: int, sprite_frames_path: String, frame_index: int) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = multiplayer.get_unique_id()
	_server_place_battle_card(id, slot_index, sprite_frames_path, frame_index)

func _server_place_battle_card(peer_id: int, slot_index: int, sprite_frames_path: String, frame_index: int) -> void:
	if slot_index < 0 or slot_index > 2:
		return
	if not battle_placed_cards.has(peer_id):
		battle_placed_cards[peer_id] = {}
	battle_placed_cards[peer_id][slot_index] = {"path": sprite_frames_path, "frame": frame_index}
	print("[BattleSync] _server_place_battle_card: peer=%d slot=%d path=%s. Current peers in dict: %s" % [peer_id, slot_index, sprite_frames_path.get_file(), str(battle_placed_cards.keys())])
	sync_battle_cards.rpc(battle_placed_cards)

@rpc("any_peer", "reliable")
func remove_battle_card(slot_index: int) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = multiplayer.get_unique_id()
	_server_remove_battle_card(id, slot_index)

func _server_remove_battle_card(peer_id: int, slot_index: int) -> void:
	if battle_placed_cards.has(peer_id) and battle_placed_cards[peer_id].has(slot_index):
		battle_placed_cards[peer_id].erase(slot_index)
		sync_battle_cards.rpc(battle_placed_cards)

@rpc("authority", "call_local", "reliable")
func sync_battle_cards(cards: Dictionary) -> void:
	battle_placed_cards = cards.duplicate(true)
	var summary: Array[String] = []
	for pid in battle_placed_cards:
		var slots: Dictionary = battle_placed_cards[pid]
		summary.append("peer %s: %d cards" % [str(pid), slots.size()])
	print("[BattleSync] sync_battle_cards received (peer %d): {%s}" % [multiplayer.get_unique_id(), ", ".join(summary)])
	battle_cards_updated.emit()

## Client requests the server to re-broadcast the full battle_placed_cards state.
## Ensures the client has the latest data after scene load.
func request_full_sync() -> void:
	if multiplayer.is_server():
		_server_full_sync()
	else:
		_rpc_request_full_sync.rpc_id(1)

@rpc("any_peer", "reliable")
func _rpc_request_full_sync() -> void:
	if not multiplayer.is_server():
		return
	_server_full_sync()

func _server_full_sync() -> void:
	print("[BattleSync] _server_full_sync: re-broadcasting battle_placed_cards (peers: %s)" % str(battle_placed_cards.keys()))
	sync_battle_cards.rpc(battle_placed_cards)

# ---------- BATTLE READY ----------

## Request to mark self as ready for battle
func request_battle_ready() -> void:
	if multiplayer.is_server():
		_server_set_battle_ready(multiplayer.get_unique_id())
	else:
		set_battle_ready.rpc_id(1)

@rpc("any_peer", "reliable")
func set_battle_ready() -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = multiplayer.get_unique_id()
	_server_set_battle_ready(id)

func _server_set_battle_ready(peer_id: int) -> void:
	## Battle starts only when all players in the card battle scene have pressed Ready (not when Attack is pressed in GameIntro).
	## For territory battles only the attacker and defender are in the scene; for 3+ players we must not wait for the third.
	battle_ready_peers[peer_id] = true
	var all_ready := false
	if territory_battle_attacker_id >= 0 and territory_battle_defender_id >= 0:
		# Territory battle: only the two participants need to be ready (third player is still on map)
		all_ready = battle_ready_peers.get(territory_battle_attacker_id, false) and battle_ready_peers.get(territory_battle_defender_id, false)
	else:
		# Non-territory (e.g. queue battle): all peers must be ready
		var all_peers: Array = []
		all_peers.append(multiplayer.get_unique_id())
		for pid in multiplayer.get_peers():
			all_peers.append(pid)
		all_ready = true
		for pid in all_peers:
			if not battle_ready_peers.get(pid, false):
				all_ready = false
				break
	if all_ready:
		start_battle.rpc()

@rpc("authority", "call_local", "reliable")
func start_battle() -> void:
	var summary: Array[String] = []
	for pid in battle_placed_cards:
		var slots: Dictionary = battle_placed_cards[pid]
		summary.append("peer %s: %d cards" % [str(pid), slots.size()])
	print("[BattleSync] start_battle RPC on peer %d. battle_placed_cards: {%s}" % [multiplayer.get_unique_id(), ", ".join(summary)])
	battle_start_requested.emit()

# ---------- BATTLE LEFT / PERSISTENCE ----------

## Notify server that local player is leaving the battle
func notify_battle_left() -> void:
	var my_id := multiplayer.get_unique_id()
	battle_player_left.emit(my_id)
	# Persist cards to BattleStateManager for restoration when returning
	if BattleStateManager:
		var territory_id := BattleStateManager.current_territory_id
		BattleStateManager.clear_local_slots(territory_id)
		if battle_placed_cards.has(my_id):
			var placed: Dictionary = battle_placed_cards[my_id]
			for slot_idx in placed:
				var data: Dictionary = placed[slot_idx]
				var path: String = data.get("path", "")
				var frame: int = int(data.get("frame", 0))
				if not path.is_empty():
					BattleStateManager.set_local_slot(int(slot_idx), path, frame, territory_id)


# ---------- TERRITORY BATTLE INITIATION ----------

## Request to start a territory battle (Attacker -> Server)
func request_start_territory_battle(territory_id: int) -> void:
	if multiplayer.is_server():
		_server_handle_start_territory_battle(multiplayer.get_unique_id(), territory_id)
	else:
		server_handle_start_territory_battle.rpc_id(1, territory_id)

@rpc("any_peer", "reliable")
func server_handle_start_territory_battle(territory_id: int) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = multiplayer.get_unique_id()
	_server_handle_start_territory_battle(id, territory_id)

func _server_handle_start_territory_battle(attacker_id: int, territory_id: int) -> void:
	# Use TerritoryClaimState (persists across scenes); App.territory_manager is null when we're in card battle scene.
	var tcs: Node = get_node_or_null("/root/TerritoryClaimState")
	if not tcs or not tcs.has_method("is_claimed"):
		print("[BattleSync] request_start_territory_battle: TerritoryClaimState not available!")
		return
	if not tcs.call("is_claimed", territory_id):
		print("[BattleSync] request_start_territory_battle: Territory ", territory_id, " is not claimed (no defender).")
		return

	var owner_val: Variant = tcs.call("get_owner_id", territory_id)
	var defender_id: int = -1
	if owner_val != null:
		defender_id = int(owner_val)
	else:
		print("[BattleSync] request_start_territory_battle: Territory ", territory_id, " has no owner!")
		return

	print("[BattleSync] Starting Territory Battle: ID=", territory_id, " Attacker=", attacker_id, " Defender=", defender_id)
	clear_battle_state()
	start_territory_battle.rpc(territory_id, attacker_id, defender_id)

@rpc("authority", "call_local", "reliable")
func start_territory_battle(territory_id: int, attacker_id: int, defender_id: int) -> void:
	print("[BattleSync] Received start_territory_battle: ", territory_id)
	territory_battle_attacker_id = attacker_id
	territory_battle_defender_id = defender_id
	battle_ready_peers.clear()
	App.enter_territory_battle(territory_id, attacker_id, defender_id)

# ---------- BATTLE DECISION SYSTEM ----------

## Initialize battle phase state
func init_battle_phase() -> void:
	battle_decision_index = 0
	battle_choices.clear()
	left_queue.clear()
	right_queue.clear()
	battle_in_progress = false
	active_battle_participants.clear()
	active_battle_side = ""
	battle_finished_reports.clear()

	# Initialize all players as UNDECIDED
	for pid in NetworkManager.get_all_peer_ids():
		battle_choices[pid] = "UNDECIDED"

	# Set first decider based on turn order
	_advance_decider_to_next_eligible()

## Advance to the next eligible decider
func _advance_decider_to_next_eligible() -> void:
	if not multiplayer.is_server():
		return
	if battle_in_progress:
		return
	if App.turn_order.is_empty():
		return

	# Check if both queues are full - auto-skip remaining UNDECIDED
	if left_queue.size() >= 2 and right_queue.size() >= 2:
		for pid in battle_choices.keys():
			if battle_choices[pid] == "UNDECIDED":
				battle_choices[pid] = "SKIP"
				print("[BattleSync] Auto-skipped player ", pid, " (both queues full)")
		_sync_battle_state()
		_check_battle_phase_complete()
		return

	# Find next eligible player
	var found := false
	var start_idx := battle_decision_index
	var order_size: int = App.turn_order.size()

	for i in range(order_size):
		var idx: int = (start_idx + i) % order_size
		var player = App.turn_order[idx]
		var pid: int = player.get("id", -1)

		if battle_choices.get(pid, "UNDECIDED") != "UNDECIDED":
			continue
		if active_battle_participants.has(pid):
			continue

		battle_decision_index = idx
		battle_decider_peer_id = pid
		found = true
		break

	if found:
		print("[BattleSync] Battle decider set to: ", battle_decider_peer_id)
		rpc_set_battle_decider.rpc(battle_decider_peer_id)
		_sync_battle_state()
	else:
		_check_battle_phase_complete()

## Check if battle phase is complete
func _check_battle_phase_complete() -> void:
	if battle_in_progress:
		return

	var all_decided := true
	for pid in battle_choices.keys():
		if battle_choices[pid] == "UNDECIDED":
			all_decided = false
			break

	if all_decided:
		print("[BattleSync] Battles complete, entering next round (Claim -> Minigames -> Battle)")
		PhaseSync.server_enter_contest_claim_from_battles()

@rpc("authority", "call_local", "reliable")
func rpc_set_battle_decider(peer_id: int) -> void:
	battle_decider_peer_id = peer_id
	battle_decider_changed.emit(peer_id)

## Client submits their battle choice
func request_battle_choice(choice: String) -> void:
	if multiplayer.is_server():
		_server_process_battle_choice(multiplayer.get_unique_id(), choice)
	else:
		server_battle_choice.rpc_id(1, choice)

@rpc("any_peer", "reliable")
func server_battle_choice(choice: String) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = multiplayer.get_unique_id()
	_server_process_battle_choice(id, choice)

func _server_process_battle_choice(peer_id: int, choice: String) -> void:
	if peer_id != battle_decider_peer_id:
		print("[BattleSync] Rejected choice from ", peer_id, " (not their turn)")
		return

	if choice not in ["LEFT", "RIGHT", "SKIP"]:
		print("[BattleSync] Invalid choice: ", choice)
		return

	if choice == "LEFT" and left_queue.size() >= 2:
		print("[BattleSync] Left queue full, rejecting")
		return
	if choice == "RIGHT" and right_queue.size() >= 2:
		print("[BattleSync] Right queue full, rejecting")
		return

	battle_choices[peer_id] = choice
	print("[BattleSync] Player ", peer_id, " chose: ", choice)

	if choice == "LEFT":
		left_queue.append(peer_id)
	elif choice == "RIGHT":
		right_queue.append(peer_id)

	_sync_battle_state()

	# Check if a battle should start (2 players in same queue)
	if left_queue.size() == 2:
		_start_paired_battle(left_queue[0], left_queue[1], "LEFT")
	elif right_queue.size() == 2:
		_start_paired_battle(right_queue[0], right_queue[1], "RIGHT")
	else:
		battle_decision_index += 1
		_advance_decider_to_next_eligible()

## Sync battle state to all clients
func _sync_battle_state() -> void:
	var snapshot := {
		"choices": battle_choices.duplicate(),
		"left_queue": left_queue.duplicate(),
		"right_queue": right_queue.duplicate(),
		"battle_in_progress": battle_in_progress,
		"active_participants": active_battle_participants.duplicate(),
		"active_side": active_battle_side,
	}
	rpc_sync_battle_state.rpc(snapshot)

@rpc("authority", "call_local", "reliable")
func rpc_sync_battle_state(snapshot: Dictionary) -> void:
	battle_choices = snapshot.get("choices", {}).duplicate()
	left_queue = snapshot.get("left_queue", []).duplicate()
	right_queue = snapshot.get("right_queue", []).duplicate()
	battle_in_progress = snapshot.get("battle_in_progress", false)
	active_battle_participants = snapshot.get("active_participants", []).duplicate()
	active_battle_side = snapshot.get("active_side", "")
	battle_choices_updated.emit(snapshot)

## Start a paired battle between two players
func _start_paired_battle(p1_id: int, p2_id: int, side: String) -> void:
	if not multiplayer.is_server():
		return

	print("[BattleSync] Starting paired battle: ", p1_id, " vs ", p2_id, " on ", side)
	clear_battle_state()
	battle_in_progress = true
	active_battle_participants = [p1_id, p2_id]
	active_battle_side = side
	battle_finished_reports.clear()

	_sync_battle_state()
	rpc_start_paired_battle.rpc(p1_id, p2_id, side)

@rpc("authority", "call_local", "reliable")
func rpc_start_paired_battle(p1_id: int, p2_id: int, side: String) -> void:
	battle_started.emit(p1_id, p2_id, side)

# ---------- BATTLE FINISHED ----------

## Called by battle participants when they finish the battle
func notify_battle_finished() -> void:
	if multiplayer.is_server():
		_server_battle_finished_report(multiplayer.get_unique_id())
	else:
		server_battle_finished.rpc_id(1)

@rpc("any_peer", "reliable")
func server_battle_finished() -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = multiplayer.get_unique_id()
	_server_battle_finished_report(id)

func _server_battle_finished_report(peer_id: int) -> void:
	if not active_battle_participants.has(peer_id):
		return

	battle_finished_reports[peer_id] = true
	print("[BattleSync] Battle finished report from: ", peer_id)

	# Check if BOTH participants reported
	var both_done := true
	for pid in active_battle_participants:
		if not battle_finished_reports.get(pid, false):
			both_done = false
			break

	if both_done:
		print("[BattleSync] Both participants finished, resuming decisions")
		var p1: int = int(active_battle_participants[0]) if active_battle_participants.size() > 0 else -1
		var p2: int = int(active_battle_participants[1]) if active_battle_participants.size() > 1 else -1
		var side: String = String(active_battle_side)

		# Clear the queue that was used
		if side == "LEFT":
			left_queue.clear()
		elif side == "RIGHT":
			right_queue.clear()

		# Reset battle state
		battle_in_progress = false
		active_battle_participants.clear()
		active_battle_side = ""
		battle_finished_reports.clear()

		_sync_battle_state()
		rpc_battle_finished.rpc(p1, p2, side)

		# Resume decisions
		_advance_decider_to_next_eligible()

@rpc("authority", "call_local", "reliable")
func rpc_battle_finished(_p1_id: int, _p2_id: int, _side: String) -> void:
	battle_finished_broadcast.emit()

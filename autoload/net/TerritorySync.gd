extends Node

## TerritorySync — Territory claiming network coordination.
## Server validates claims and broadcasts results.

signal territory_claimed(territory_id: int, owner_id: int, cards: Array)
signal territory_claim_rejected(territory_id: int, claimer_name: String)
signal territory_contest_blink_started(territory_id: int, attacker_id: int, attacker_card_count: int)

## Any peer requests to claim a territory; server validates and broadcasts
func request_claim_territory(territory_id: int, owner_id: int, cards: Array) -> void:
	if multiplayer.is_server():
		_server_process_claim_territory(multiplayer.get_unique_id(), territory_id, owner_id, cards)
	else:
		server_claim_territory.rpc_id(1, territory_id, owner_id, cards)

@rpc("any_peer", "reliable")
func server_claim_territory(territory_id: int, owner_id: int, cards: Array) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = multiplayer.get_unique_id()
	_server_process_claim_territory(sender_id, territory_id, owner_id, cards)

func _server_process_claim_territory(requester_id: int, territory_id: int, owner_id: int, cards: Array) -> void:
	if not multiplayer.is_server():
		return
	# Requester must claim for themselves
	if requester_id != owner_id:
		return
	# Turn/phase authority gate: only the active player can claim during turn-based claim windows.
	# Resource collection and any non-claiming phases must not accept territory claims.
	var is_turn_based_claim_window := (
		PhaseController.current_phase == 0
		or (PhaseController.current_phase == 1 and PhaseController.map_sub_phase == PhaseController.MapSubPhase.CLAIMING)
	)
	if not is_turn_based_claim_window:
		print("[TerritorySync] REJECTED claim from %d for territory %d (phase=%d sub=%d)" % [
			requester_id, territory_id, PhaseController.current_phase, PhaseController.map_sub_phase
		])
		return
	if PhaseController.current_turn_peer_id != -1 and requester_id != PhaseController.current_turn_peer_id:
		print("[TerritorySync] REJECTED out-of-turn claim from %d (current turn: %d)" % [
			requester_id, PhaseController.current_turn_peer_id
		])
		return
	# Check if territory is already claimed by another player
	var tcs := _get_territory_claim_state()
	if tcs and tcs.has_method("is_claimed") and tcs.call("is_claimed", territory_id):
		var existing_owner_id = tcs.call("get_owner_id", territory_id)
		if existing_owner_id != null and int(existing_owner_id) != int(owner_id):
			var claimer_name := _get_player_name(int(existing_owner_id))
			rpc_claim_rejected.rpc_id(requester_id, territory_id, claimer_name)
			return
	# Apply and broadcast
	if tcs and tcs.has_method("set_claim"):
		tcs.call("set_claim", territory_id, owner_id, cards)
	rpc_territory_claimed.rpc(territory_id, owner_id, cards)

func _get_territory_claim_state() -> Node:
	return get_node_or_null("/root/" + "Territory" + "Claim" + "State")

func _get_player_name(peer_id: int) -> String:
	for p in App.game_players:
		if int(p.get("id", -1)) == int(peer_id):
			return str(p.get("name", "Player"))
	return "Player"

## Server-only helper for host-controlled bot claims in multiplayer.
func host_claim_territory_as_bot(territory_id: int, bot_id: int, cards: Array) -> void:
	if not multiplayer.is_server():
		return
	var tcs := _get_territory_claim_state()
	if tcs and tcs.has_method("set_claim"):
		tcs.call("set_claim", territory_id, bot_id, cards)
	rpc_territory_claimed.rpc(territory_id, bot_id, cards)

## Conquest: attacker takes territory from defender after winning battle. Server applies and broadcasts.
func request_conquest_territory(territory_id: int, conqueror_id: int, cards: Array) -> void:
	if multiplayer.is_server():
		_server_process_conquest(multiplayer.get_unique_id(), territory_id, conqueror_id, cards)
	else:
		server_conquest_territory.rpc_id(1, territory_id, conqueror_id, cards)

@rpc("any_peer", "reliable")
func server_conquest_territory(territory_id: int, conqueror_id: int, cards: Array) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = multiplayer.get_unique_id()
	_server_process_conquest(sender_id, territory_id, conqueror_id, cards)

func _server_process_conquest(requester_id: int, territory_id: int, conqueror_id: int, cards: Array) -> void:
	if not multiplayer.is_server():
		return
	# Normal case: the winning player applies for themselves.
	# When the winner is a bot, the RPC is sent by a human participant (or the host after bot-vs-bot);
	# conqueror_id is the bot id, so requester_id != conqueror_id — still valid.
	if requester_id != conqueror_id:
		if not PlayerDataSync.is_bot_id(conqueror_id):
			return
		var att_id: int = App.pending_territory_battle_attacker_id
		var def_id: int = App.pending_territory_battle_defender_id
		if conqueror_id != att_id and conqueror_id != def_id:
			return
		var sender_is_participant: bool = (requester_id == att_id or requester_id == def_id)
		var sender_is_host: bool = (requester_id == multiplayer.get_unique_id())
		if not sender_is_participant and not sender_is_host:
			return
	var tcs := _get_territory_claim_state()
	if tcs and tcs.has_method("set_claim"):
		tcs.call("set_claim", territory_id, conqueror_id, cards)
	rpc_territory_claimed.rpc(territory_id, conqueror_id, cards)

@rpc("authority", "call_local", "reliable")
func rpc_territory_claimed(territory_id: int, owner_id: int, cards: Array) -> void:
	territory_claimed.emit(territory_id, owner_id, cards)

@rpc("authority", "reliable")
func rpc_claim_rejected(territory_id: int, claimer_name: String) -> void:
	territory_claim_rejected.emit(territory_id, claimer_name)

# ---------- CONTEST BLINK ----------

## Any peer requests to start contest blink on a territory (after Attack is clicked).
func request_territory_contest_blink(territory_id: int, attacker_card_count: int) -> void:
	if multiplayer.is_server():
		_server_process_contest_blink(multiplayer.get_unique_id(), territory_id, attacker_card_count)
	else:
		server_contest_blink.rpc_id(1, territory_id, attacker_card_count)

@rpc("any_peer", "reliable")
func server_contest_blink(territory_id: int, attacker_card_count: int) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = multiplayer.get_unique_id()
	_server_process_contest_blink(sender_id, territory_id, attacker_card_count)

func _server_process_contest_blink(attacker_id: int, territory_id: int, attacker_card_count: int) -> void:
	if not multiplayer.is_server():
		return
	rpc_territory_contest_blink.rpc(territory_id, attacker_id, attacker_card_count)

@rpc("authority", "call_local", "reliable")
func rpc_territory_contest_blink(territory_id: int, attacker_id: int, attacker_card_count: int) -> void:
	territory_contest_blink_started.emit(territory_id, attacker_id, attacker_card_count)

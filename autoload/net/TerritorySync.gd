extends Node

## TerritorySync — Territory claiming network coordination.
## Server validates claims and broadcasts results.

signal territory_claimed(territory_id: int, owner_id: int, cards: Array)
signal territory_claim_rejected(territory_id: int, claimer_name: String)

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

@rpc("authority", "call_local", "reliable")
func rpc_territory_claimed(territory_id: int, owner_id: int, cards: Array) -> void:
	territory_claimed.emit(territory_id, owner_id, cards)

@rpc("authority", "reliable")
func rpc_claim_rejected(territory_id: int, claimer_name: String) -> void:
	territory_claim_rejected.emit(territory_id, claimer_name)

extends RefCounted

## BotCommandBehavior
## Handles bot behavior during CONTEST_COMMAND.
## Supports both all-at-once (run_command_turn) and step-by-step (prepare_turn + place_next) modes.

var _active_bot_id: int = -1
var _active_hand: Array = []
var _turn_attacked_claimed: bool = false
var _active_difficulty: int = 0


func run_command_turn(bot_player_id: int) -> bool:
	prepare_turn(bot_player_id, int(PlayerDataSync.get_bot_difficulty(bot_player_id)))
	while true:
		var result: Dictionary = place_next()
		if result.get("done", true):
			return _turn_attacked_claimed
	return _turn_attacked_claimed


func prepare_turn(bot_player_id: int, difficulty: int = 0) -> void:
	_active_bot_id = bot_player_id
	_active_difficulty = clampi(difficulty, 0, 5)
	_turn_attacked_claimed = false
	var hand: Array = App.bot_card_collections.get(bot_player_id, [])
	_active_hand = []
	for c in hand:
		if _is_valid_card_data(c):
			_active_hand.append(c)
	if _active_hand.is_empty():
		print("[BotCommand] Bot %d has no cards; skipping turn." % bot_player_id)
		App.bot_card_collections[bot_player_id] = _active_hand


func place_next() -> Dictionary:
	## Place cards on one territory. Returns {"attacked": bool, "done": bool}.
	if _active_bot_id == -1 or _active_hand.is_empty():
		_finalize_hand()
		return {"attacked": false, "done": true}

	var target_tid := _pick_target_territory_by_difficulty(_active_bot_id, _active_difficulty)
	if target_tid < 0:
		_finalize_hand()
		return {"attacked": false, "done": true}

	var to_place := _choose_cards_to_place_count_by_difficulty(_active_hand.size(), _active_difficulty)
	var placed_cards: Array = []
	for _i in range(to_place):
		if _active_hand.is_empty():
			break
		var pick_idx := randi() % _active_hand.size()
		placed_cards.append(_active_hand[pick_idx])
		_active_hand.remove_at(pick_idx)

	var attacked := false
	if not placed_cards.is_empty():
		attacked = _place_cards_on_territory(_active_bot_id, target_tid, placed_cards)
		_turn_attacked_claimed = _turn_attacked_claimed or attacked

	# 50% chance to stop, or stop if out of cards.
	if _active_hand.is_empty() or not _should_continue_placing_by_difficulty(_active_difficulty):
		_finalize_hand()
		return {"attacked": attacked, "done": true}

	return {"attacked": attacked, "done": false}


func is_turn_active() -> bool:
	return _active_bot_id != -1


func did_attack_claimed() -> bool:
	return _turn_attacked_claimed


func _finalize_hand() -> void:
	if _active_bot_id != -1:
		App.bot_card_collections[_active_bot_id] = _active_hand
	_active_bot_id = -1
	_active_hand = []


func _pick_random_target_territory(bot_player_id: int) -> int:
	var tcs: Node = App.get_node_or_null("/root/TerritoryClaimState")

	var eligible: Array[int] = []
	for tid_key in TerritoryManager.TERRITORY_REGIONS.keys():
		var tid: int = 0
		if tid_key is int:
			tid = tid_key
		elif tid_key is String and (tid_key as String).is_valid_int():
			tid = (tid_key as String).to_int()
		else:
			continue
		if _is_territory_owned_by_bot(tid, bot_player_id, tcs):
			continue
		eligible.append(tid)

	if eligible.is_empty():
		return -1
	return eligible[randi() % eligible.size()]


func _pick_target_territory_by_difficulty(bot_player_id: int, difficulty: int) -> int:
	match difficulty:
		0:
			return _pick_random_target_territory(bot_player_id)
		1:
			return _pick_target_difficulty_1_stub(bot_player_id)
		2:
			return _pick_target_difficulty_2_stub(bot_player_id)
		3:
			return _pick_target_difficulty_3_stub(bot_player_id)
		4:
			return _pick_target_difficulty_4_stub(bot_player_id)
		5:
			return _pick_target_difficulty_5_stub(bot_player_id)
		_:
			return _pick_random_target_territory(bot_player_id)


func _choose_cards_to_place_count_by_difficulty(hand_size: int, difficulty: int) -> int:
	match difficulty:
		0:
			return randi_range(1, mini(3, hand_size))
		_:
			return _choose_cards_to_place_count_stub(hand_size, difficulty)


func _should_continue_placing_by_difficulty(difficulty: int) -> bool:
	match difficulty:
		0:
			return randf() < 0.5
		_:
			return _should_continue_placing_stub(difficulty)


# ---------- Difficulty stubs (fallback to level 0 for now) ----------

func _pick_target_difficulty_1_stub(bot_player_id: int) -> int:
	return _pick_random_target_territory(bot_player_id)

func _pick_target_difficulty_2_stub(bot_player_id: int) -> int:
	return _pick_random_target_territory(bot_player_id)

func _pick_target_difficulty_3_stub(bot_player_id: int) -> int:
	return _pick_random_target_territory(bot_player_id)

func _pick_target_difficulty_4_stub(bot_player_id: int) -> int:
	return _pick_random_target_territory(bot_player_id)

func _pick_target_difficulty_5_stub(bot_player_id: int) -> int:
	return _pick_random_target_territory(bot_player_id)

func _choose_cards_to_place_count_stub(hand_size: int, _difficulty: int) -> int:
	return randi_range(1, mini(3, hand_size))

func _should_continue_placing_stub(_difficulty: int) -> bool:
	return randf() < 0.5


func _is_territory_owned_by_bot(territory_id: int, bot_player_id: int, tcs: Node) -> bool:
	if tcs == null or not tcs.has_method("get_owner_id"):
		return false
	var owner_raw: Variant = tcs.get_owner_id(territory_id)
	var owner_id: int = -1
	if owner_raw is int:
		owner_id = owner_raw
	elif owner_raw is float:
		owner_id = int(owner_raw)
	elif owner_raw is String and (owner_raw as String).is_valid_int():
		owner_id = (owner_raw as String).to_int()
	return owner_id == bot_player_id


func _place_cards_on_territory(bot_player_id: int, territory_id: int, cards: Array) -> bool:
	var valid_cards: Array = []
	for c in cards:
		if _is_valid_card_data(c):
			valid_cards.append(c)
	if valid_cards.is_empty():
		return false

	var tcs: Node = App.get_node_or_null("/root/TerritoryClaimState")
	var owner_id: int = -1
	if tcs and tcs.has_method("get_owner_id"):
		var owner_raw: Variant = tcs.get_owner_id(territory_id)
		if owner_raw is int:
			owner_id = owner_raw
		elif owner_raw is String and (owner_raw as String).is_valid_int():
			owner_id = (owner_raw as String).to_int()

	if owner_id == -1:
		var claim_cards: Array = [null, null, null]
		var defs: Dictionary = {}
		for i in range(mini(3, valid_cards.size())):
			claim_cards[i] = valid_cards[i]
			defs[i] = valid_cards[i]
		var mp := App.get_tree().get_multiplayer() if App and App.get_tree() else null
		if App.is_multiplayer and mp and mp.has_multiplayer_peer() and mp.is_server():
			TerritorySync.host_claim_territory_as_bot(territory_id, bot_player_id, claim_cards)
		elif tcs and tcs.has_method("set_claim"):
			tcs.set_claim(territory_id, bot_player_id, claim_cards)
		BattleStateManager.set_defending_slots(str(territory_id), defs)
		BattleStateManager.clear_attacking_slots(str(territory_id))
		print("[BotCommand] Bot %d claimed territory %d with %d cards." % [bot_player_id, territory_id, defs.size()])
		return false
	else:
		var atks: Dictionary = {}
		for i in range(mini(3, valid_cards.size())):
			atks[i] = valid_cards[i]
		BattleStateManager.set_attacking_slots(str(territory_id), atks)
		App.territory_pending_attackers[territory_id] = bot_player_id
		print("[BotCommand] Bot %d attacked territory %d with %d cards." % [bot_player_id, territory_id, atks.size()])
		return true


func _is_valid_card_data(card_data: Variant) -> bool:
	if not (card_data is Dictionary):
		return false
	var d: Dictionary = card_data
	var path: String = String(d.get("path", ""))
	return not path.is_empty()

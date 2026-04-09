extends RefCounted
const DEBUG_LOGS := false

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
		if DEBUG_LOGS: print("[BotCommand] Bot %d has no cards; skipping turn." % bot_player_id)
		App.bot_card_collections[bot_player_id] = _active_hand


func place_next() -> Dictionary:
	## Place cards on one territory. Returns {"attacked": bool, "done": bool}.
	if _active_bot_id == -1 or _active_hand.is_empty():
		_finalize_hand()
		return {"attacked": false, "done": true}

	var hand_sz := _active_hand.size()
	var tcs: Node = App.get_node_or_null("/root/TerritoryClaimState")
	var target_tid := -1
	var is_attack := false
	var to_place := 0

	# Try preferred target first, then fall back to other eligible territories if attack
	# card-count window is invalid (e.g. hi < lo for level 5 constraints).
	var preferred_tid := _pick_target_territory_by_difficulty(_active_bot_id, _active_difficulty, hand_sz)
	var candidates: Array[int] = []
	if preferred_tid >= 0:
		candidates.append(preferred_tid)
	var eligible: Array[int] = _eligible_target_territories(_active_bot_id)
	eligible.shuffle()
	for tid in eligible:
		if tid == preferred_tid:
			continue
		candidates.append(tid)

	for cand_tid in candidates:
		var owner_id := _get_territory_owner_id(cand_tid, tcs)
		var cand_attack := owner_id != -1 and owner_id != _active_bot_id
		var cand_to_place := _choose_cards_to_place_count_for_target(hand_sz, _active_difficulty, cand_tid, cand_attack)
		if cand_attack and cand_to_place <= 0:
			continue
		target_tid = cand_tid
		is_attack = cand_attack
		to_place = cand_to_place
		break

	if target_tid < 0:
		_finalize_hand()
		return {"attacked": false, "done": true}

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

	# Difficulty 0: random stop chance. Difficulty 1+: exhaust hand every turn.
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


func _pick_target_territory_by_difficulty(bot_player_id: int, difficulty: int, hand_size: int) -> int:
	match difficulty:
		0:
			return _pick_random_target_territory(bot_player_id)
		1:
			return _pick_random_target_territory(bot_player_id)
		2:
			return _pick_target_region_bonus(bot_player_id, hand_size, false)
		3:
			return _pick_target_region_bonus(bot_player_id, hand_size, true)
		4:
			return _pick_target_region_bonus(bot_player_id, hand_size, true)
		5:
			return _pick_target_level_5(bot_player_id, hand_size)
		_:
			return _pick_random_target_territory(bot_player_id)


func _should_continue_placing_by_difficulty(difficulty: int) -> bool:
	match difficulty:
		0:
			return randf() < 0.5
		_:
			return true


func _choose_cards_to_place_count_for_target(hand_size: int, difficulty: int, territory_id: int, is_attack: bool) -> int:
	if hand_size <= 0:
		return 0
	match difficulty:
		0:
			return randi_range(1, mini(3, hand_size))
		1, 2:
			return randi_range(1, mini(3, hand_size))
		3, 4:
			if is_attack:
				var def_n := _defender_card_count_on_territory(territory_id)
				var lo := clampi(def_n, 1, 3)
				var hi := mini(3, hand_size)
				if lo > hi:
					return mini(3, hand_size)
				if lo == hi:
					return lo
				return randi_range(lo, hi)
			return randi_range(1, mini(3, hand_size))
		5:
			if is_attack:
				var def_n5 := _defender_card_count_on_territory(territory_id)
				# Level 5 attack count rule: [defenders - 1, 3], constrained by hand size.
				var lo5 := clampi(def_n5 - 1, 1, 3)
				var hi5 := mini(3, hand_size)
				if lo5 > hi5:
					return 0
				if lo5 == hi5:
					return lo5
				return randi_range(lo5, hi5)
			return randi_range(1, mini(3, hand_size))
		_:
			return randi_range(1, mini(3, hand_size))


# ---------- Target selection: region bonus & aggression ----------


func _get_territory_owner_id(territory_id: int, tcs: Node) -> int:
	if tcs == null or not tcs.has_method("get_owner_id"):
		return -1
	var owner_raw: Variant = tcs.get_owner_id(territory_id)
	if owner_raw == null:
		return -1
	if owner_raw is int:
		return owner_raw
	if owner_raw is float:
		return int(owner_raw)
	if owner_raw is String and (owner_raw as String).is_valid_int():
		return (owner_raw as String).to_int()
	return -1


func _defender_card_count_on_territory(territory_id: int) -> int:
	var n := 0
	if BattleStateManager:
		var d: Dictionary = BattleStateManager.get_defending_slots(str(territory_id))
		for k in d.keys():
			var card: Variant = d[k]
			if card is Dictionary:
				var path: String = String(card.get("path", ""))
				if not path.is_empty():
					n += 1
	## If defending slots were not mirrored into BattleStateManager yet, use persisted claim cards (common on server).
	if n == 0:
		var tcs: Node = App.get_node_or_null("/root/TerritoryClaimState")
		if tcs != null and tcs.has_method("get_cards"):
			var cards: Variant = tcs.get_cards(territory_id)
			if cards is Array:
				for c in cards:
					if c != null and c is Dictionary and String(c.get("path", "")) != "":
						n += 1
	return n


func _eligible_target_territories(bot_player_id: int) -> Array[int]:
	var tcs: Node = App.get_node_or_null("/root/TerritoryClaimState")
	var eligible: Array[int] = []
	for tid_key in TerritoryManager.TERRITORY_REGIONS.keys():
		var tid: int = _coerce_territory_id_int(tid_key)
		if tid < 0:
			continue
		if _is_territory_owned_by_bot(tid, bot_player_id, tcs):
			continue
		eligible.append(tid)
	return eligible


func _coerce_territory_id_int(tid_key: Variant) -> int:
	if tid_key is int:
		return tid_key
	if tid_key is String and (tid_key as String).is_valid_int():
		return (tid_key as String).to_int()
	return -1


func _get_region_partner_tid(territory_id: int) -> int:
	## Each region has exactly two territories in TERRITORY_REGIONS.
	if not TerritoryManager.TERRITORY_REGIONS.has(territory_id):
		return -1
	var my_region: Variant = TerritoryManager.TERRITORY_REGIONS[territory_id]
	for tid_key in TerritoryManager.TERRITORY_REGIONS.keys():
		var tid: int = _coerce_territory_id_int(tid_key)
		if tid < 0 or tid == territory_id:
			continue
		if TerritoryManager.TERRITORY_REGIONS[tid_key] == my_region:
			return tid
	return -1


func _pick_region_completion_targets(bot_player_id: int) -> Array[int]:
	## Territories that complete a region (bot owns sibling, this one is not owned by bot).
	var tcs: Node = App.get_node_or_null("/root/TerritoryClaimState")
	var out: Array[int] = []
	var seen: Dictionary = {}
	for tid_key in TerritoryManager.TERRITORY_REGIONS.keys():
		var tid: int = _coerce_territory_id_int(tid_key)
		if tid < 0 or seen.has(tid):
			continue
		var partner: int = _get_region_partner_tid(tid)
		if partner < 0:
			continue
		seen[tid] = true
		seen[partner] = true
		var bot_has_a := _is_territory_owned_by_bot(tid, bot_player_id, tcs)
		var bot_has_b := _is_territory_owned_by_bot(partner, bot_player_id, tcs)
		if bot_has_a and not bot_has_b:
			out.append(partner)
		elif bot_has_b and not bot_has_a:
			out.append(tid)
	return out


func _filter_attack_targets_smart(eligible: Array[int], bot_player_id: int, hand_size: int, apply_full_defense_skip: bool) -> Array[int]:
	var tcs: Node = App.get_node_or_null("/root/TerritoryClaimState")
	var attacks: Array[int] = []
	for tid in eligible:
		var oid := _get_territory_owner_id(tid, tcs)
		if oid == -1 or oid == bot_player_id:
			continue
		var def_n := _defender_card_count_on_territory(tid)
		if apply_full_defense_skip and def_n > hand_size:
			continue
		attacks.append(tid)
	if attacks.is_empty():
		return attacks
	if apply_full_defense_skip:
		var has_non_full: bool = false
		for tid in attacks:
			if _defender_card_count_on_territory(tid) < 3:
				has_non_full = true
				break
		if has_non_full:
			var filtered: Array[int] = []
			for tid in attacks:
				if _defender_card_count_on_territory(tid) < 3:
					filtered.append(tid)
			if not filtered.is_empty():
				return filtered
	return attacks


func _pick_target_region_bonus(bot_player_id: int, hand_size: int, smart_attacks: bool) -> int:
	var region_first: Array[int] = _pick_region_completion_targets(bot_player_id)
	var eligible: Array[int] = _eligible_target_territories(bot_player_id)
	var region_eligible: Array[int] = []
	for tid in region_first:
		if eligible.find(tid) >= 0:
			region_eligible.append(tid)
	if not region_eligible.is_empty():
		return region_eligible[randi() % region_eligible.size()]

	if smart_attacks:
		var attacks := _filter_attack_targets_smart(eligible, bot_player_id, hand_size, true)
		var claims: Array[int] = []
		var tcs2: Node = App.get_node_or_null("/root/TerritoryClaimState")
		for tid in eligible:
			if _get_territory_owner_id(tid, tcs2) == -1:
				claims.append(tid)
		var pool: Array[int] = []
		if not attacks.is_empty():
			pool = attacks
		elif not claims.is_empty():
			pool = claims
		else:
			## Do not pick attack targets we cannot match (hand smaller than defender count).
			for tid in eligible:
				var oid2 := _get_territory_owner_id(tid, tcs2)
				if oid2 == -1 or oid2 == bot_player_id:
					continue
				if _defender_card_count_on_territory(tid) <= hand_size:
					pool.append(tid)
			if pool.is_empty():
				pool = eligible.duplicate()
		if pool.is_empty():
			return -1
		return pool[randi() % pool.size()]

	if eligible.is_empty():
		return -1
	return eligible[randi() % eligible.size()]


func _distinct_region_count_for_player(player_id: int, tcs: Node) -> int:
	var regions: Dictionary = {}
	for tid_key in TerritoryManager.TERRITORY_REGIONS.keys():
		var tid: int = _coerce_territory_id_int(tid_key)
		if tid < 0:
			continue
		if _get_territory_owner_id(tid, tcs) != player_id:
			continue
		var rid: Variant = TerritoryManager.TERRITORY_REGIONS[tid_key]
		regions[int(rid)] = true
	return regions.size()


func _leader_player_ids_excluding_bot(bot_player_id: int, tcs: Node) -> Array[int]:
	var best: int = -1
	var leaders: Array[int] = []
	for p in App.game_players:
		var pid: int = int(p.get("id", -1))
		if pid < 0 or pid == bot_player_id:
			continue
		var n: int = _distinct_region_count_for_player(pid, tcs)
		if n > best:
			best = n
			leaders.clear()
			leaders.append(pid)
		elif n == best and best >= 0:
			leaders.append(pid)
	return leaders


func _pick_target_level_5(bot_player_id: int, hand_size: int) -> int:
	var tcs: Node = App.get_node_or_null("/root/TerritoryClaimState")
	## Region completion first (same as level 2+).
	var region_first: Array[int] = _pick_region_completion_targets(bot_player_id)
	var eligible: Array[int] = _eligible_target_territories(bot_player_id)
	var region_eligible: Array[int] = []
	for tid in region_first:
		if eligible.find(tid) >= 0:
			region_eligible.append(tid)
	if not region_eligible.is_empty():
		return region_eligible[randi() % region_eligible.size()]

	var attacks := _filter_attack_targets_smart(eligible, bot_player_id, hand_size, true)
	var leader_ids: Array[int] = _leader_player_ids_excluding_bot(bot_player_id, tcs)
	var leader_attacks: Array[int] = []
	for tid in attacks:
		var oid := _get_territory_owner_id(tid, tcs)
		if leader_ids.find(oid) >= 0:
			leader_attacks.append(tid)

	if not leader_attacks.is_empty():
		var best_def: int = 999
		var tier: Array[int] = []
		for tid in leader_attacks:
			var d := _defender_card_count_on_territory(tid)
			if d < best_def:
				best_def = d
				tier.clear()
				tier.append(tid)
			elif d == best_def:
				tier.append(tid)
		return tier[randi() % tier.size()]

	## Fall back to level 3-style pool (claims or any attack).
	var claims: Array[int] = []
	for tid in eligible:
		if _get_territory_owner_id(tid, tcs) == -1:
			claims.append(tid)
	if not attacks.is_empty():
		return attacks[randi() % attacks.size()]
	if not claims.is_empty():
		return claims[randi() % claims.size()]
	if eligible.is_empty():
		return -1
	return eligible[randi() % eligible.size()]


func _is_territory_owned_by_bot(territory_id: int, bot_player_id: int, tcs: Node) -> bool:
	if tcs == null or not tcs.has_method("get_owner_id"):
		return false
	var owner_raw: Variant = tcs.get_owner_id(territory_id)
	if owner_raw == null:
		return false
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
		if DEBUG_LOGS: print("[BotCommand] Bot %d claimed territory %d with %d cards." % [bot_player_id, territory_id, defs.size()])
		return false
	else:
		var atks: Dictionary = {}
		for i in range(mini(3, valid_cards.size())):
			atks[i] = valid_cards[i]
		BattleStateManager.set_attacking_slots(str(territory_id), atks)
		App.territory_pending_attackers[territory_id] = bot_player_id
		if DEBUG_LOGS: print("[BotCommand] Bot %d attacked territory %d with %d cards." % [bot_player_id, territory_id, atks.size()])
		return true


func _is_valid_card_data(card_data: Variant) -> bool:
	if not (card_data is Dictionary):
		return false
	var d: Dictionary = card_data
	var path: String = String(d.get("path", ""))
	return not path.is_empty()

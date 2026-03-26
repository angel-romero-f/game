extends RefCounted

## BotCommandBehavior
## Handles bot behavior during CONTEST_COMMAND.

func run_command_turn(bot_player_id: int) -> bool:
	var hand: Array = App.bot_card_collections.get(bot_player_id, [])
	# Never let bots place invalid/blank cards.
	var filtered_hand: Array = []
	for c in hand:
		if _is_valid_card_data(c):
			filtered_hand.append(c)
	hand = filtered_hand
	if hand.is_empty():
		print("[BotCommand] Bot %d has no cards; skipping turn." % bot_player_id)
		App.bot_card_collections[bot_player_id] = hand
		return false
	var attacked_claimed := false

	while not hand.is_empty():
		var target_tid := _pick_random_target_territory(bot_player_id)
		if target_tid < 0:
			break

		var to_place := randi_range(1, mini(3, hand.size()))
		var placed_cards: Array = []
		for slot_idx in range(to_place):
			if hand.is_empty():
				break
			var pick_idx := randi() % hand.size()
			placed_cards.append(hand[pick_idx])
			hand.remove_at(pick_idx)

		if not placed_cards.is_empty():
			var attacked := _place_cards_on_territory(bot_player_id, target_tid, placed_cards)
			attacked_claimed = attacked_claimed or attacked

		# 50% chance to continue placing cards if cards remain.
		if hand.is_empty():
			break
		if randf() >= 0.5:
			break

	App.bot_card_collections[bot_player_id] = hand
	return attacked_claimed


func _pick_random_target_territory(bot_player_id: int) -> int:
	var tcs: Node = App.get_node_or_null("/root/TerritoryClaimState")

	var eligible: Array[int] = []
	# Use authoritative territory ids so bots can claim unclaimed territories too.
	for tid_key in TerritoryManager.TERRITORY_REGIONS.keys():
		var tid: int = 0
		if tid_key is int:
			tid = tid_key
		elif tid_key is String and (tid_key as String).is_valid_int():
			tid = (tid_key as String).to_int()
		else:
			continue
		# Skip already owned territory.
		if _is_territory_owned_by_bot(tid, bot_player_id, tcs):
			continue
		eligible.append(tid)

	if eligible.is_empty():
		return -1
	return eligible[randi() % eligible.size()]


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
		# Unclaimed territory: bot claims it by placing defending cards.
		var claim_cards: Array = [null, null, null]
		var defs: Dictionary = {}
		for i in range(mini(3, valid_cards.size())):
			claim_cards[i] = valid_cards[i]
			defs[i] = valid_cards[i]
		if tcs and tcs.has_method("set_claim"):
			tcs.set_claim(territory_id, bot_player_id, claim_cards)
		BattleStateManager.set_defending_slots(str(territory_id), defs)
		BattleStateManager.clear_attacking_slots(str(territory_id))
		print("[BotCommand] Bot %d claimed territory %d with %d cards." % [bot_player_id, territory_id, defs.size()])
		return false
	else:
		# Claimed by another player: bot places attacking cards.
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

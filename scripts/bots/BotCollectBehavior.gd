extends RefCounted
const DEBUG_LOGS := false

## BotCollectBehavior
## Handles bot card gain during resource/collect phases.
## One roll per collect pass (matches a single resource window, not two separate minigame runs).


func run_collect_for_bot(bot_player_id: int) -> void:
	if not App.bot_card_collections.has(bot_player_id):
		App.bot_card_collections[bot_player_id] = []
	var diff := int(PlayerDataSync.get_bot_difficulty(bot_player_id))
	var bonus_region_id := _first_eligible_region_bonus_region(bot_player_id)
	var has_region_bonus := bonus_region_id >= 0
	var gain: int
	if diff >= 4:
		## High difficulty: fixed totals (same as two perfect minigames with / without region bonus).
		gain = 4 if has_region_bonus else 2
	else:
		## Low difficulty: random — 0–4 with region bonus, 0–2 without.
		if has_region_bonus:
			gain = randi_range(0, 4)
		else:
			gain = randi_range(0, 2)
	for _i in range(gain):
		var card := _random_card_for_bot_race(bot_player_id)
		if not card.is_empty():
			App.bot_card_collections[bot_player_id].append(card)
	## Consume an eligible region bonus when we clearly used it (high tier always; low tier if at least 2 cards).
	if bonus_region_id >= 0:
		var should_consume := diff >= 4 or gain >= 2
		if should_consume and bonus_region_id not in App.region_bonus_used_this_phase:
			App.region_bonus_used_this_phase.append(bonus_region_id)
	if DEBUG_LOGS: print("[BotCollect] Bot %d gained %d cards (region_bonus=%s, diff=%d)." % [bot_player_id, gain, str(has_region_bonus), diff])


func _first_eligible_region_bonus_region(bot_player_id: int) -> int:
	## Same eligibility as human minigames: full region control and bonus not used this phase.
	for region_id in [1, 2, 3, 4, 5, 6]:
		if region_id in App.region_bonus_used_this_phase:
			continue
		if TerritoryClaimManager and TerritoryClaimManager.has_method("player_owns_full_region"):
			if TerritoryClaimManager.player_owns_full_region(bot_player_id, region_id):
				return region_id
	return -1


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
	# Retry within pool to avoid returning blank cards.
	for _i in range(pool.size()):
		var c: Dictionary = pool[randi() % pool.size()]
		var path: String = String(c.get("sprite_frames", ""))
		if not path.is_empty():
			return {"path": path, "frame": int(c.get("frame_index", 0))}
	return {}

extends RefCounted

## BotCollectBehavior
## Handles bot card gain during resource/collect phases.

func run_collect_for_bot(bot_player_id: int) -> void:
	if not App.bot_card_collections.has(bot_player_id):
		App.bot_card_collections[bot_player_id] = []
	var has_region_bonus := _bot_has_region_bonus(bot_player_id)
	var min_cards := 1
	var max_cards := 3 if has_region_bonus else 2
	var gain := randi_range(min_cards, max_cards)
	for _i in range(gain):
		var card := _random_card_for_bot_race(bot_player_id)
		if not card.is_empty():
			App.bot_card_collections[bot_player_id].append(card)
	print("[BotCollect] Bot %d gained %d cards (region_bonus=%s)." % [bot_player_id, gain, str(has_region_bonus)])


func _bot_has_region_bonus(bot_player_id: int) -> bool:
	# Region IDs used by the project map config.
	for region_id in [1, 2, 3, 4, 5, 6]:
		if TerritoryClaimManager and TerritoryClaimManager.has_method("player_owns_full_region"):
			if TerritoryClaimManager.player_owns_full_region(bot_player_id, region_id):
				return true
	return false


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

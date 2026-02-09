extends Node

## Persists which territories are claimed, by whom, and which cards are in the 3 slots.
## Keys: territory_id (int). Values: { "owner_player_id": int, "cards": [card_dict or null, ...] }
## card_dict: { "path": String, "frame": int } matching App.player_card_collection format.

var claims: Dictionary = {}

const SAVE_PATH: String = "user://territory_claims.dat"


func _ready() -> void:
	load_claims()


func get_claim(territory_id: int) -> Dictionary:
	return claims.get(territory_id, {})


func is_claimed(territory_id: int) -> bool:
	return claims.has(territory_id) and claims[territory_id].get("owner_player_id", null) != null


func get_owner_id(territory_id: int) -> Variant:
	var c := get_claim(territory_id)
	return c.get("owner_player_id", null)


func get_cards(territory_id: int) -> Array:
	var c := get_claim(territory_id)
	return c.get("cards", [null, null, null])


func set_claim(territory_id: int, owner_player_id: int, slot_cards: Array) -> void:
	# slot_cards: array of 3 elements, each a card dict or null
	var cards_copy: Array = []
	for i in range(3):
		if i < slot_cards.size() and slot_cards[i] != null and slot_cards[i] is Dictionary:
			cards_copy.append(slot_cards[i].duplicate())
		else:
			cards_copy.append(null)
	claims[territory_id] = {
		"owner_player_id": owner_player_id,
		"cards": cards_copy
	}
	save_claims()


func clear_claim(territory_id: int) -> void:
	claims.erase(territory_id)
	save_claims()


func clear_all() -> void:
	claims.clear()
	save_claims()


func save_claims() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("TerritoryClaimState: Could not save to %s" % SAVE_PATH)
		return
	file.store_var(claims)
	file.close()


func load_claims() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var data = file.get_var()
	file.close()
	if data is Dictionary:
		claims = data

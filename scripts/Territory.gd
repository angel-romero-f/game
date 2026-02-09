class_name Territory
extends RefCounted

## Territory
## Represents a gray-outlined area on the map.
## Tracks ownership, adjacent territories, and card placements by players.

## Unique identifier for this territory
var territory_id: int

## Region identifier this territory belongs to
var region_id: int

## Player ID that owns this territory (null if unclaimed)
var owner_player_id: Variant = null  # int or null

## Array of adjacent territory IDs
var adjacent_territories: Array[int] = []

## Cards placed by each player
## Key: player_id (int)
## Value: Array of up to 3 card instances or card IDs
## Cards are stored in order: [left, middle, right] (indices 0, 1, 2)
## Each card can be either:
##   - A Card instance (Node2D)
##   - A Dictionary: {"path": String, "frame": int}
##   - null for empty slots
var cards_by_player: Dictionary = {}

## Card slot indices
const SLOT_LEFT: int = 0
const SLOT_MIDDLE: int = 1
const SLOT_RIGHT: int = 2
const MAX_CARDS_PER_PLAYER: int = 3


func _init(
	p_territory_id: int = 0,
	p_region_id: int = 0,
	p_owner_player_id: Variant = null,
	p_adjacent_territories: Array[int] = []
) -> void:
	territory_id = p_territory_id
	region_id = p_region_id
	owner_player_id = p_owner_player_id
	adjacent_territories = p_adjacent_territories.duplicate()


## Returns true if this territory has an owner
func is_claimed() -> bool:
	return owner_player_id != null


## Returns true if multiple players have placed cards (contested)
func is_contested() -> bool:
	return cards_by_player.size() > 1


## Check if a player can place a card in the specified slot
## Returns true if:
##   - The slot index is valid (0-2)
##   - The player hasn't reached the max card limit (3 cards)
##   - The specific slot is empty (if slot_index is provided)
func can_place_card(player_id: int, slot_index: int = -1) -> bool:
	# Validate slot index
	if slot_index != -1 and (slot_index < 0 or slot_index >= MAX_CARDS_PER_PLAYER):
		return false
	
	# Get or create player's card array
	var player_cards: Array = cards_by_player.get(player_id, [])
	
	# Ensure array has 3 slots
	while player_cards.size() < MAX_CARDS_PER_PLAYER:
		player_cards.append(null)
	
	# If specific slot requested, check if it's empty
	if slot_index != -1:
		return player_cards[slot_index] == null
	
	# Otherwise, check if player has any empty slots
	for card in player_cards:
		if card == null:
			return true
	
	return false


## Place a card for a player in the specified slot
## card: Can be a Card instance, a Dictionary {"path": String, "frame": int}, or card ID
## slot_index: 0 (left), 1 (middle), or 2 (right)
## Returns true if placement was successful, false otherwise
func place_card(player_id: int, card: Variant, slot_index: int) -> bool:
	# Validate slot index
	if slot_index < 0 or slot_index >= MAX_CARDS_PER_PLAYER:
		push_error("Invalid slot_index: %d. Must be 0-2" % slot_index)
		return false
	
	# Check if placement is allowed
	if not can_place_card(player_id, slot_index):
		return false
	
	# Get or create player's card array
	if not cards_by_player.has(player_id):
		cards_by_player[player_id] = []
	
	var player_cards: Array = cards_by_player[player_id]
	
	# Ensure array has 3 slots
	while player_cards.size() < MAX_CARDS_PER_PLAYER:
		player_cards.append(null)
	
	# Place the card in the specified slot
	player_cards[slot_index] = card
	
	return true


## Remove a card from a player's slot
## Returns the removed card, or null if slot was empty
func remove_card(player_id: int, slot_index: int) -> Variant:
	if not cards_by_player.has(player_id):
		return null
	
	var player_cards: Array = cards_by_player[player_id]
	if slot_index < 0 or slot_index >= player_cards.size():
		return null
	
	var card = player_cards[slot_index]
	player_cards[slot_index] = null
	
	# Clean up empty arrays (optional - you may want to keep them)
	var has_any_cards := false
	for c in player_cards:
		if c != null:
			has_any_cards = true
			break
	
	if not has_any_cards:
		cards_by_player.erase(player_id)
	
	return card


## Get all cards for a specific player
## Returns an array of 3 cards (may contain nulls for empty slots)
func get_player_cards(player_id: int) -> Array:
	if not cards_by_player.has(player_id):
		return [null, null, null]
	
	var player_cards: Array = cards_by_player[player_id].duplicate()
	
	# Ensure array has 3 slots
	while player_cards.size() < MAX_CARDS_PER_PLAYER:
		player_cards.append(null)
	
	return player_cards


## Get the card in a specific slot for a player
## Returns the card or null
func get_card_in_slot(player_id: int, slot_index: int) -> Variant:
	if slot_index < 0 or slot_index >= MAX_CARDS_PER_PLAYER:
		return null
	
	var player_cards: Array = get_player_cards(player_id)
	return player_cards[slot_index] if slot_index < player_cards.size() else null


## Get count of cards placed by a player
func get_card_count(player_id: int) -> int:
	var player_cards: Array = get_player_cards(player_id)
	var count := 0
	for card in player_cards:
		if card != null:
			count += 1
	return count


## Set the owner of this territory
func set_owner(player_id: Variant) -> void:
	owner_player_id = player_id


## Clear the owner (unclaim the territory)
func clear_owner() -> void:
	owner_player_id = null


## Add an adjacent territory
func add_adjacent_territory(territory_id: int) -> void:
	if territory_id not in adjacent_territories:
		adjacent_territories.append(territory_id)


## Remove an adjacent territory
func remove_adjacent_territory(territory_id: int) -> void:
	var index := adjacent_territories.find(territory_id)
	if index != -1:
		adjacent_territories.remove_at(index)


## Check if a territory is adjacent to this one
func is_adjacent_to(territory_id: int) -> bool:
	return territory_id in adjacent_territories


## Clear all cards for a player
func clear_player_cards(player_id: int) -> void:
	cards_by_player.erase(player_id)


## Clear all cards from all players
func clear_all_cards() -> void:
	cards_by_player.clear()

extends Node

## TerritoryClaimManager — Orchestrates territory claim/attack operations.
## Validates claims, updates Territory model, persists to TerritoryClaimState,
## syncs with BattleStateManager, and removes placed cards from the player's collection.
## UI code should call these functions and react to signals for visual updates.

signal claim_succeeded(territory_id: int, owner_id: int, cards: Array)
signal claim_failed(territory_id: int, reason: String)
signal attack_registered(territory_id: int, attacking_cards: Array)

## Region ID -> minigame. Each TerritoryNode's region_id_override picks which minigame runs.
const REGION_MINIGAMES: Dictionary = {
	1: { "name": "Bridge", "scene": "res://scenes/BridgeGame.tscn" },
	6: { "name": "Ice fishing", "scene": "res://scenes/IceFishingGame.tscn" },
	5: { "name": "River crossing", "scene": "res://scenes/Game.tscn" },
	4: { "name": "", "scene": "" },
	3: { "name": "", "scene": "" },
	2: { "name": "", "scene": "" }
}

var _territory_claim_state: Node = null

func _ready() -> void:
	_territory_claim_state = get_node_or_null("/root/" + "Territory" + "Claim" + "State")

## Claim a territory (single-player path). In multiplayer, routes through TerritorySync.
## Returns true if the claim was initiated (multiplayer) or applied (single-player).
func claim_territory(territory_id: int, local_id: Variant, slot_cards: Array, territory_manager: TerritoryManager) -> bool:
	if territory_id < 0 or not territory_manager.territory_data.has(territory_id):
		claim_failed.emit(territory_id, "invalid_territory")
		return false

	# Check if already claimed by another player
	if _territory_claim_state and _territory_claim_state.has_method("is_claimed") and _territory_claim_state.call("is_claimed", territory_id):
		var owner_id: Variant = _territory_claim_state.call("get_owner_id", territory_id)
		if owner_id != null and int(owner_id) != int(local_id):
			var claimer_name: String = "Player"
			for p in App.game_players:
				if int(p.get("id", -1)) == int(owner_id):
					claimer_name = str(p.get("name", "Player"))
					break
			claim_failed.emit(territory_id, claimer_name)
			return false

	if App.is_multiplayer and App.get_tree().get_multiplayer().has_multiplayer_peer():
		# Multiplayer: request claim via Net; server validates and broadcasts
		TerritorySync.request_claim_territory(territory_id, local_id, slot_cards)
		return true

	# Single-player: apply claim locally
	var territory: Territory = territory_manager.territory_data[territory_id]
	for slot_idx in range(3):
		if slot_cards[slot_idx] != null:
			territory.place_card(local_id, slot_cards[slot_idx], slot_idx)
	territory.set_owner(local_id)
	if _territory_claim_state and _territory_claim_state.has_method("set_claim"):
		_territory_claim_state.set_claim(territory_id, local_id, slot_cards)
	# Report defending slots to BattleStateManager
	if BattleStateManager:
		var defending_dict: Dictionary = {}
		for slot_idx in range(3):
			if slot_cards[slot_idx] != null and slot_cards[slot_idx] is Dictionary:
				defending_dict[slot_idx] = slot_cards[slot_idx]
		BattleStateManager.set_defending_slots(str(territory_id), defending_dict)
	var placed_slots: Dictionary = {}
	for slot_idx in range(3):
		if slot_cards[slot_idx] != null:
			placed_slots[slot_idx] = slot_cards[slot_idx]
	App.remove_placed_cards_from_collection_for_slots(placed_slots)
	claim_succeeded.emit(territory_id, local_id, slot_cards)
	return true

## Apply a network-synced territory claim (all peers receive this).
func apply_network_claim(territory_id: int, owner_id: int, cards: Array, local_id: Variant, territory_manager: TerritoryManager) -> void:
	if not territory_manager or not territory_manager.territory_data.has(territory_id):
		return
	var territory: Territory = territory_manager.territory_data[territory_id]
	# Update Territory data
	territory.set_owner(owner_id)
	for slot_idx in range(min(3, cards.size())):
		if cards[slot_idx] != null:
			territory.place_card(owner_id, cards[slot_idx], slot_idx)
	# Persist to TerritoryClaimState
	if _territory_claim_state and _territory_claim_state.has_method("set_claim"):
		_territory_claim_state.set_claim(territory_id, owner_id, cards)
	# Report defending slots to BattleStateManager
	if BattleStateManager:
		var defending_dict: Dictionary = {}
		for slot_idx in range(min(3, cards.size())):
			if cards[slot_idx] != null and cards[slot_idx] is Dictionary:
				defending_dict[slot_idx] = cards[slot_idx]
		BattleStateManager.set_defending_slots(str(territory_id), defending_dict)
	# If we're the owner, remove placed cards from our collection
	if local_id != null and int(owner_id) == int(local_id):
		var placed_slots: Dictionary = {}
		for slot_idx in range(min(3, cards.size())):
			if cards[slot_idx] != null:
				placed_slots[slot_idx] = cards[slot_idx]
		App.remove_placed_cards_from_collection_for_slots(placed_slots)
	claim_succeeded.emit(territory_id, owner_id, cards)

## Register an attack on a territory. Stores attacking cards in BattleStateManager and removes from player hand.
func register_attack(territory_id: int, attacking_slot_cards: Array) -> void:
	if BattleStateManager:
		var attacking_dict: Dictionary = {}
		for slot_idx in range(3):
			if attacking_slot_cards[slot_idx] != null and attacking_slot_cards[slot_idx] is Dictionary:
				attacking_dict[slot_idx] = attacking_slot_cards[slot_idx]
		BattleStateManager.set_attacking_slots(str(territory_id), attacking_dict)
	var placed_slots: Dictionary = {}
	for slot_idx in range(3):
		if attacking_slot_cards[slot_idx] != null:
			placed_slots[slot_idx] = attacking_slot_cards[slot_idx]
	App.remove_placed_cards_from_collection_for_slots(placed_slots)
	attack_registered.emit(territory_id, attacking_slot_cards)

## Apply saved claims from TerritoryClaimState onto the territory manager (used when returning from battle/minigame).
func apply_saved_claims(territory_manager: TerritoryManager) -> void:
	if not territory_manager:
		return
	if not _territory_claim_state:
		return
	var claims_dict: Variant = _territory_claim_state.get("claims")
	if not (claims_dict is Dictionary):
		return
	for tid_key in claims_dict:
		var tid: int = int(tid_key)
		var claim_data: Dictionary = (claims_dict as Dictionary)[tid_key]
		var owner_id: Variant = claim_data.get("owner_player_id", null)
		var cards: Array = claim_data.get("cards", [])
		if owner_id == null or not territory_manager.territory_data.has(tid):
			continue
		var territory: Territory = territory_manager.territory_data[tid]
		territory.set_owner(owner_id)
		territory.clear_player_cards(int(owner_id))
		for slot_idx in range(min(3, cards.size())):
			if cards[slot_idx] != null:
				territory.place_card(owner_id, cards[slot_idx], slot_idx)

## Launch a territory-specific minigame based on the territory's region.
func launch_territory_minigame(territory_id: int, region_id: int) -> void:
	var region_info: Dictionary = REGION_MINIGAMES.get(region_id, { "scene": "" })
	var scene_path: String = region_info.get("scene", "")
	if scene_path != "" and ResourceLoader.exists(scene_path):
		App.pending_return_map_sub_phase = PhaseController.MapSubPhase.RESOURCE_COLLECTION
		App.returning_from_territory_minigame = true
		App.go(scene_path)

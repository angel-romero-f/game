extends Node

## TerritoryClaimManager — Orchestrates territory claim/attack operations.
## Validates claims, updates Territory model, persists to TerritoryClaimState,
## syncs with BattleStateManager, and removes placed cards from the player's collection.
## UI code should call these functions and react to signals for visual updates.

signal claim_succeeded(territory_id: int, owner_id: int, cards: Array)
signal claim_failed(territory_id: int, reason: String)
signal attack_registered(territory_id: int, attacking_cards: Array)

## Region ID -> minigame. Each territory's region_id picks which minigame runs.
const REGION_MINIGAMES: Dictionary = {
	1: { "name": "Courtly Cuisine", "scene": "res://scenes/CourtlyCuisineGame.tscn" },
	2: { "name": "Bridge", "scene": "res://scenes/BridgeGame.tscn" },
	3: { "name": "River crossing", "scene": "res://scenes/Game.tscn" },
	4: { "name": "Conjurer's Chorus", "scene": "res://scenes/ConjurersChorusGame.tscn" },
	5: { "name": "Cadence", "scene": "res://scenes/CadenceGame.tscn" },
	6: { "name": "Ice fishing", "scene": "res://scenes/IceFishingGame.tscn" }
}

var _territory_claim_state: Node = null

func _ready() -> void:
	_territory_claim_state = get_node_or_null("/root/" + "Territory" + "Claim" + "State")
	if TerritorySync and not TerritorySync.territory_claimed.is_connected(_on_territory_claimed_from_net):
		TerritorySync.territory_claimed.connect(_on_territory_claimed_from_net)

## Handle network-synced claims from TerritorySync (ensures TCS is updated on all peers, including during battle).
func _on_territory_claimed_from_net(territory_id: int, owner_id: int, cards: Array) -> void:
	if _territory_claim_state and _territory_claim_state.has_method("set_claim"):
		_territory_claim_state.set_claim(territory_id, owner_id, cards)
	var tm = App.territory_manager as TerritoryManager if App else null
	if tm and is_instance_valid(tm) and tm.territory_data.has(territory_id):
		apply_network_claim(territory_id, owner_id, cards, _get_local_id(), tm)
	else:
		if BattleStateManager:
			var defending_dict: Dictionary = {}
			for slot_idx in range(min(3, cards.size())):
				if slot_idx < cards.size() and cards[slot_idx] != null and cards[slot_idx] is Dictionary:
					defending_dict[slot_idx] = cards[slot_idx]
			BattleStateManager.set_defending_slots(str(territory_id), defending_dict)
			BattleStateManager.clear_attacking_slots(str(territory_id))

func _get_local_id() -> Variant:
	for p in App.game_players:
		if p.get("is_local", false):
			return p.get("id", 1)
	return 1

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
	App.remove_placed_cards_from_collection_for_slots(placed_slots, "placed_defending")
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
		App.remove_placed_cards_from_collection_for_slots(placed_slots, "placed_defending")
	claim_succeeded.emit(territory_id, owner_id, cards)

## Apply conquest without territory_manager (e.g. during battle when map scene is not loaded).
## Updates TCS and emits claim_succeeded. Use when territory_manager may be invalid.
func apply_conquest_claim(territory_id: int, conqueror_id: int, cards: Array) -> void:
	if _territory_claim_state and _territory_claim_state.has_method("set_claim"):
		_territory_claim_state.set_claim(territory_id, conqueror_id, cards)
	if BattleStateManager:
		var defending_dict: Dictionary = {}
		for slot_idx in range(min(3, cards.size())):
			if slot_idx < cards.size() and cards[slot_idx] != null and cards[slot_idx] is Dictionary:
				defending_dict[slot_idx] = cards[slot_idx]
		BattleStateManager.set_defending_slots(str(territory_id), defending_dict)
		BattleStateManager.clear_attacking_slots(str(territory_id))
	claim_succeeded.emit(territory_id, conqueror_id, cards)

## Register an attack on a territory. Stores attacking cards in BattleStateManager and removes from player hand.
func register_attack(territory_id: int, attacking_slot_cards: Array) -> void:
	# Track attacker for single-player territory battle participant resolution.
	App.territory_pending_attackers[territory_id] = int(_get_local_id())
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
	App.remove_placed_cards_from_collection_for_slots(placed_slots, "placed_attacking")
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

## Returns true if the given player owns every territory in the specified region.
func player_owns_full_region(player_id: int, region_id: int) -> bool:
	if not _territory_claim_state or not App.territory_manager:
		return false
	var tm := App.territory_manager as TerritoryManager
	if not tm:
		return false
	var found_any := false
	for tid in tm.territory_data:
		var territory: Territory = tm.territory_data[tid]
		if not territory or territory.region_id != region_id:
			continue
		found_any = true
		var owner_id: Variant = _territory_claim_state.call("get_owner_id", tid)
		if owner_id == null or int(owner_id) != int(player_id):
			return false
	return found_any

## Launch a territory-specific minigame based on the territory's region.
func launch_territory_minigame(_territory_id: int, region_id: int) -> void:
	var region_info: Dictionary = REGION_MINIGAMES.get(region_id, { "scene": "" })
	var scene_path: String = region_info.get("scene", "")
	if scene_path != "" and ResourceLoader.exists(scene_path):
		App.pending_return_map_sub_phase = PhaseController.MapSubPhase.RESOURCE_COLLECTION
		App.returning_from_territory_minigame = true
		App.pre_roll_minigame_reward_for_region(region_id)

		var local_id: int = _get_local_id()
		var eligible := region_id not in App.region_bonus_used_this_phase and player_owns_full_region(local_id, region_id)
		App.region_bonus_active = eligible
		if eligible:
			App.pre_roll_bonus_reward_for_region(region_id)
			App.region_bonus_used_this_phase.append(region_id)

		App.go(scene_path)

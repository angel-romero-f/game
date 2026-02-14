extends Node

## BattleStateManager
## Runtime-only manager for per-territory battle state.
## - Tracks placed cards per territory (local player's slots)
## - Tracks last battle result per territory (win/lose/tie from local perspective)
##
## This is intended to be used as an autoload singleton:
## Project Settings -> Autoload -> BattleStateManager = res://autoload/BattleStateManager.gd

## ID of the territory for the currently active battle scene.
var current_territory_id: String = ""

## Territory state:
## territory_id -> {
##   "local_slots": Dictionary,  # slot_index (int) -> { "path": String, "frame": int }
##   "defending_slots": Dictionary,  # slot_index -> { "path": String, "frame": int } (owner's cards on territory)
##   "attacking_slots": Dictionary,  # slot_index -> { "path": String, "frame": int } (attacker's cards)
##   "last_result": String,      # "win", "lose", "tie", or ""
##   "last_winner_is_local": bool,
## }
var _territories: Dictionary = {}


func _get_state(territory_id: String = "") -> Dictionary:
	if territory_id.is_empty():
		territory_id = current_territory_id
	if territory_id.is_empty():
		return {}
	if not _territories.has(territory_id):
		_territories[territory_id] = {
			"local_slots": {},
			"defending_slots": {},
			"attacking_slots": {},
			"last_result": "",
			"last_winner_is_local": false,
		}
	return _territories[territory_id]


func set_current_territory(territory_id: String) -> void:
	## Set the active territory id for the current battle.
	current_territory_id = territory_id
	_get_state(territory_id) # Ensure entry exists


func clear_territory(territory_id: String = "") -> void:
	## Clear all state (local slots + last result) for a territory.
	if territory_id.is_empty():
		territory_id = current_territory_id
	if _territories.has(territory_id):
		_territories[territory_id] = {
			"local_slots": {},
			"defending_slots": {},
			"attacking_slots": {},
			"last_result": "",
			"last_winner_is_local": false,
		}


func get_local_slots(territory_id: String = "") -> Dictionary:
	## Get the current placed-card dictionary for this territory:
	## slot_index -> { "path": String, "frame": int }
	var state := _get_state(territory_id)
	return state.get("local_slots", {})


func set_local_slot(slot_idx: int, path: String, frame: int, territory_id: String = "") -> void:
	## Update a single local slot for the active territory.
	var state := _get_state(territory_id)
	if state.is_empty():
		return
	var slots: Dictionary = state["local_slots"]
	if path.is_empty():
		slots.erase(slot_idx)
	else:
		slots[slot_idx] = {"path": path, "frame": frame}


func clear_local_slots(territory_id: String = "") -> void:
	## Clear all local slots for the given territory.
	var state := _get_state(territory_id)
	if state.is_empty():
		return
	state["local_slots"].clear()


func record_battle_result(result: String, local_won: bool, territory_id: String = "") -> void:
	## Record the last battle result for a territory from the local player's perspective.
	## result: "win", "lose", or "tie"
	var state := _get_state(territory_id)
	if state.is_empty():
		return
	state["last_result"] = result
	state["last_winner_is_local"] = (result == "win") and local_won


func get_last_result(territory_id: String = "") -> String:
	var state := _get_state(territory_id)
	return String(state.get("last_result", ""))


func last_winner_is_local(territory_id: String = "") -> bool:
	var state := _get_state(territory_id)
	return bool(state.get("last_winner_is_local", false))


func set_defending_slots(territory_id: String, slots_dict: Dictionary) -> void:
	## Set the defending (owner's) cards for a territory. slots_dict: slot_index -> { "path": String, "frame": int }
	var state := _get_state(territory_id)
	if state.is_empty():
		return
	state["defending_slots"] = {}
	for idx in slots_dict:
		var card: Variant = slots_dict[idx]
		if card is Dictionary and card.get("path", "") != "":
			state["defending_slots"][int(idx)] = {"path": str(card.get("path", "")), "frame": int(card.get("frame", 0))}


func set_attacking_slots(territory_id: String, slots_dict: Dictionary) -> void:
	## Set the attacking cards for a territory. slots_dict: slot_index -> { "path": String, "frame": int }
	var state := _get_state(territory_id)
	if state.is_empty():
		return
	state["attacking_slots"] = {}
	for idx in slots_dict:
		var card: Variant = slots_dict[idx]
		if card is Dictionary and card.get("path", "") != "":
			state["attacking_slots"][int(idx)] = {"path": str(card.get("path", "")), "frame": int(card.get("frame", 0))}


func get_defending_slots(territory_id: String = "") -> Dictionary:
	var state := _get_state(territory_id)
	return state.get("defending_slots", {}).duplicate(true)


func get_attacking_slots(territory_id: String = "") -> Dictionary:
	var state := _get_state(territory_id)
	return state.get("attacking_slots", {}).duplicate(true)


func has_defending_cards(territory_id: String = "") -> bool:
	return not get_defending_slots(territory_id).is_empty()


func has_attacking_cards(territory_id: String = "") -> bool:
	return not get_attacking_slots(territory_id).is_empty()


## Returns territory IDs (as strings) that have both defending and attacking cards, sorted ascending by numeric id.
func get_territory_ids_with_battle() -> Array:
	var out: Array = []
	for tid in _territories:
		var state: Dictionary = _territories[tid]
		var defs: Dictionary = state.get("defending_slots", {})
		var atks: Dictionary = state.get("attacking_slots", {})
		if not defs.is_empty() and not atks.is_empty():
			out.append(tid)
	out.sort_custom(func(a, b): return int(a) < int(b) if (str(a).is_valid_int() and str(b).is_valid_int()) else str(a) < str(b))
	return out

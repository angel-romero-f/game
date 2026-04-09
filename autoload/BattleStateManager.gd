extends Node
const DEBUG_LOGS := false

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
##   "last_winner_is_local": bool,
##   "round_results": Array,       # Array of "win", "lose", "tie" (per slot)
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
			"round_results": [],
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
			"round_results": [],
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


func record_round_results(results: Array, territory_id: String = "") -> void:
	## Record individual round results ("win", "lose", "tie") for a territory.
	var state := _get_state(territory_id)
	if state.is_empty():
		return
	state["round_results"] = results


func process_battle_resolution(overall_result: String, local_won: bool, is_defender: bool, territory_id: String = "") -> Dictionary:
	## Implement new territory card loss rules and return lost slots.
	## If player wins: they only lose their losing cards.
	## If player loses: they lose all cards.
	## If players tie: defending wins (Defender follows win rule, Attacker follows lose rule).
	## For territory battles, local player's cards come from defending_slots (if defender) or attacking_slots (if attacker).
	
	var state := _get_state(territory_id)
	if state.is_empty():
		return {}
	
	var round_results: Array = state.get("round_results", [])
	# Use the correct slot set for the local player (defender's or attacker's cards)
	var local_slots: Dictionary = {}
	if is_defender:
		local_slots = state.get("defending_slots", {}).duplicate(true)
	else:
		local_slots = state.get("attacking_slots", {}).duplicate(true)
	
	var lost_slots: Dictionary = {}
	
	var is_winner := false
	if overall_result == "win":
		is_winner = true
	elif overall_result == "lose":
		is_winner = false
	else: # tie
		is_winner = is_defender # defending wins ties
	
	if is_winner:
		# Winner: only lose cards that lost their round
		for i in range(round_results.size()):
			if round_results[i] == "lose":
				if local_slots.has(i):
					lost_slots[i] = local_slots[i]
	else:
		# Loser: lose all cards
		lost_slots = local_slots.duplicate()
	
	# Update local slots by removing lost ones
	for idx in lost_slots:
		local_slots.erase(idx)
	
	# Update territory-specific slot tracking
	if is_defender:
		state["defending_slots"] = local_slots.duplicate()
	else:
		state["attacking_slots"] = local_slots.duplicate()

	# Debug: log updated state after battle resolution
	if DEBUG_LOGS: print("[BattleStateManager] Battle resolution updated state for territory %s: defending_slots=%s attacking_slots=%s round_results=%s" % [
		territory_id,
		_slots_debug_string(state.get("defending_slots", {})),
		_slots_debug_string(state.get("attacking_slots", {})),
		str(state.get("round_results", []))
	])
	return lost_slots


func get_last_result(territory_id: String = "") -> String:
	var state := _get_state(territory_id)
	return String(state.get("last_result", ""))


func last_winner_is_local(territory_id: String = "") -> bool:
	var state := _get_state(territory_id)
	return bool(state.get("last_winner_is_local", false))


func _slots_debug_string(slots_dict: Dictionary) -> String:
	var parts: Array[String] = []
	for idx in slots_dict.keys():
		var card: Variant = slots_dict[idx]
		if card is Dictionary:
			parts.append("slot %s: %s frame=%s" % [idx, card.get("path", ""), card.get("frame", -1)])
		else:
			parts.append("slot %s: %s" % [idx, str(card)])
	parts.sort()
	return "{" + ", ".join(parts) + "}" if not parts.is_empty() else "{}"


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
	if DEBUG_LOGS: print("[BattleStateManager] Defending slots updated for territory %s: %s" % [territory_id, _slots_debug_string(state["defending_slots"])])


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
	if DEBUG_LOGS: print("[BattleStateManager] Attacking slots updated for territory %s: %s" % [territory_id, _slots_debug_string(state["attacking_slots"])])


func clear_attacking_slots(territory_id: String = "") -> void:
	## Clear attacking slots for a territory (e.g. after conquest so they become defending).
	var state := _get_state(territory_id)
	if state.is_empty():
		return
	state["attacking_slots"] = {}
	if DEBUG_LOGS: print("[BattleStateManager] Attacking slots cleared for territory %s" % territory_id)


func clear_all_attacking_slots() -> void:
	## Clear attacking slots for ALL territories. Called at the start of each turn
	## to prevent stale attacking cards from previous battles triggering phantom battles.
	for tid in _territories:
		_territories[tid]["attacking_slots"] = {}


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

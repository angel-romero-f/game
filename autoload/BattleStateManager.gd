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

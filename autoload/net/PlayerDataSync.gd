extends Node

## PlayerDataSync — Synchronizes player metadata (names, races, rolls) across the network.
## No game flow logic — only player identity data.

const RACES := ["Elf", "Orc", "Fairy", "Infernal"]

var player_names: Dictionary = {}
var player_races: Dictionary = {} # peer_id -> race_name (String)
var player_rolls: Dictionary = {} # peer_id -> roll value (int)

signal player_names_updated
signal player_races_updated
signal player_rolls_updated
signal turn_order_finalized

func _ready() -> void:
	NetworkManager.connection_closing.connect(_on_connection_closing)
	NetworkManager.peer_disconnected_signal.connect(_on_peer_disconnected)

func _on_connection_closing() -> void:
	player_names.clear()
	player_races.clear()
	player_rolls.clear()

func _on_peer_disconnected(id: int) -> void:
	if multiplayer.is_server():
		if player_names.has(id):
			player_names.erase(id)
			_sync_player_names()
		if player_races.has(id):
			player_races.erase(id)
			_sync_player_races()

# ---------- NAME SYNC ----------

## Submit local player's name to the host
func submit_player_name(player_name: String) -> void:
	var cleaned := player_name.strip_edges()
	if cleaned.is_empty():
		return
	if multiplayer.is_server():
		_set_player_name(multiplayer.get_unique_id(), cleaned)
		_sync_player_names()
	else:
		set_player_name.rpc_id(1, cleaned)

@rpc("any_peer", "reliable")
func set_player_name(player_name: String) -> void:
	if not multiplayer.is_server():
		return
	var cleaned := player_name.strip_edges()
	if cleaned.is_empty():
		return
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = multiplayer.get_unique_id()
	_set_player_name(id, cleaned)
	_sync_player_names()

@rpc("authority", "call_local", "reliable")
func sync_player_names(names: Dictionary) -> void:
	player_names = names.duplicate(true)
	player_names_updated.emit()

func _set_player_name(id: int, player_name: String) -> void:
	player_names[id] = player_name

func _sync_player_names() -> void:
	sync_player_names.rpc(player_names)

# ---------- RACE SYNC ----------

## Submit local player's race to the host. Pass "" to unselect.
func submit_player_race(race: String) -> void:
	var cleaned := race.strip_edges()
	if multiplayer.is_server():
		_server_try_set_player_race(multiplayer.get_unique_id(), cleaned)
		_sync_player_races()
	else:
		set_player_race.rpc_id(1, cleaned)

@rpc("any_peer", "reliable")
func set_player_race(race: String) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = multiplayer.get_unique_id()
	_server_try_set_player_race(id, race.strip_edges())
	_sync_player_races()

@rpc("authority", "call_local", "reliable")
func sync_player_races(races: Dictionary) -> void:
	player_races = races.duplicate(true)
	player_races_updated.emit()

func _server_try_set_player_race(id: int, race: String) -> void:
	if race.is_empty():
		if player_races.has(id):
			player_races.erase(id)
		return
	if not RACES.has(race):
		return
	# Enforce one race per player
	for pid in player_races.keys():
		if int(pid) != id and String(player_races[pid]) == race:
			return
	player_races[id] = race

func _sync_player_races() -> void:
	sync_player_races.rpc(player_races)

# ---------- ROLL SYNC ----------

## Host generates rolls for all players and syncs to everyone
func host_generate_and_sync_rolls() -> void:
	if not multiplayer.is_server():
		push_warning("Only host can generate rolls")
		return
	player_rolls.clear()
	for pid in player_races.keys():
		player_rolls[pid] = randi_range(1, 20)
	_resolve_roll_ties()
	print("Host generated rolls: ", player_rolls)
	_sync_player_rolls()

func _resolve_roll_ties() -> void:
	var max_attempts := 20
	var attempts := 0
	while attempts < max_attempts:
		var has_ties := false
		var roll_counts := {}
		for pid in player_rolls.keys():
			var roll_val: int = player_rolls[pid]
			if not roll_counts.has(roll_val):
				roll_counts[roll_val] = []
			roll_counts[roll_val].append(pid)
		for roll_val in roll_counts.keys():
			if roll_counts[roll_val].size() > 1:
				has_ties = true
				print("Tie at roll ", roll_val, " - rerolling for: ", roll_counts[roll_val])
				for pid in roll_counts[roll_val]:
					player_rolls[pid] = randi_range(1, 20)
		if not has_ties:
			break
		attempts += 1
	if attempts >= max_attempts:
		push_warning("Could not fully resolve roll ties after ", max_attempts, " attempts")

func _sync_player_rolls() -> void:
	sync_player_rolls.rpc(player_rolls)

@rpc("authority", "call_local", "reliable")
func sync_player_rolls(rolls: Dictionary) -> void:
	player_rolls = rolls.duplicate(true)
	print("Received synced rolls: ", player_rolls)
	# Update App.game_players with the synced rolls
	for i in range(App.game_players.size()):
		var pid = App.game_players[i].get("id", -1)
		if player_rolls.has(pid):
			App.game_players[i]["roll"] = player_rolls[pid]
			print("Updated player ", App.game_players[i].get("name"), " roll to ", player_rolls[pid])
	player_rolls_updated.emit()

## Request host to generate rolls (called by GameIntro when ready)
func request_roll_generation() -> void:
	if multiplayer.is_server():
		host_generate_and_sync_rolls()
	else:
		request_rolls_from_host.rpc_id(1)

@rpc("any_peer", "reliable")
func request_rolls_from_host() -> void:
	if multiplayer.is_server():
		host_generate_and_sync_rolls()

# ---------- TURN ORDER ----------

## Finalize turn order: resolve ties (single-player), sort players, write App.turn_order, emit signal.
func finalize_turn_order() -> void:
	if not App.is_multiplayer:
		_resolve_single_player_ties()
	var sorted_players := App.game_players.duplicate()
	sorted_players.sort_custom(func(a, b): return a.get("roll", 0) > b.get("roll", 0))
	App.turn_order = sorted_players
	print("Turn order finalized:")
	for i in range(App.turn_order.size()):
		var p = App.turn_order[i]
		print("  ", i + 1, ". ", p.get("name", "Unknown"), " - Roll: ", p.get("roll", 0))
	turn_order_finalized.emit()

func _resolve_single_player_ties() -> void:
	var max_attempts := 10
	var attempts := 0
	# Ensure all players have valid rolls (no zeros)
	for i in range(App.game_players.size()):
		var current_roll: int = int(App.game_players[i].get("roll", 0))
		if current_roll <= 0:
			App.game_players[i]["roll"] = randi_range(1, 20)
			print("Fixed invalid roll for player: ", App.game_players[i].get("name", "Unknown"))
	while attempts < max_attempts:
		var has_ties := false
		var rolls_count := {}
		for i in range(App.game_players.size()):
			var roll: int = int(App.game_players[i].get("roll", 0))
			if not rolls_count.has(roll):
				rolls_count[roll] = []
			rolls_count[roll].append(i)
		for roll in rolls_count.keys():
			if rolls_count[roll].size() > 1:
				has_ties = true
				print("Tie detected at roll ", roll, " - rerolling for tied players")
				for idx in rolls_count[roll]:
					var new_roll := randi_range(1, 20)
					App.game_players[idx]["roll"] = new_roll
					print("  ", App.game_players[idx].get("name", "Unknown"), " rerolled: ", new_roll)
		if not has_ties:
			break
		attempts += 1
	if attempts >= max_attempts:
		push_warning("Reached max tie resolution attempts - some ties may remain")

extends Node

const PORT := 9999
const MAX_CLIENTS := 4

var peer: ENetMultiplayerPeer

signal joined_game
signal left_game
signal player_names_updated
signal player_races_updated
signal player_rolls_updated

var player_names: Dictionary = {}
var player_races: Dictionary = {} # peer_id -> race_name (String)
var player_rolls: Dictionary = {} # peer_id -> roll value (int)

const RACES := ["Elf", "Orc", "Fairy", "Infernal"]

## Host a game server
func host_game() -> void:
	# Clean up any existing connection first (silent cleanup)
	if multiplayer.multiplayer_peer:
		_cleanup_connection()
	
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_CLIENTS)
	if err != OK:
		push_error("create_server failed: %s" % err)
		return
	multiplayer.multiplayer_peer = peer
	_connect_signals()
	joined_game.emit()

## Join a game using code string like "192.168.1.12" or "192.168.1.12:9999"
func join_game(code: String) -> void:
	# Clean up any existing connection first (silent cleanup)
	if multiplayer.multiplayer_peer:
		_cleanup_connection()
	
	var ip := ""
	var port := PORT
	
	# Parse code: accept "ip" or "ip:port"
	code = code.strip_edges()
	if ":" in code:
		var parts := code.split(":")
		if parts.size() >= 2:
			ip = parts[0]
			port = parts[1].to_int()
			if port <= 0:
				port = PORT
		else:
			ip = code
	else:
		ip = code
	
	if ip.is_empty():
		push_error("Invalid host code: empty IP")
		return
	
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		push_error("create_client failed: %s" % err)
		return
	multiplayer.multiplayer_peer = peer
	_connect_signals()
	joined_game.emit()

## Get the host's likely LAN IP address with port
func get_host_code() -> String:
	var addresses := IP.get_local_addresses()
	
	# Try to find a non-localhost IPv4 address
	# Private IP ranges: 192.168.x.x, 10.x.x.x, 172.16-31.x.x
	for address in addresses:
		if typeof(address) == TYPE_STRING:
			# Skip IPv6 and localhost
			if ":" in address or address == "127.0.0.1" or address.begins_with("127."):
				continue
			# Check for private IP ranges
			if address.begins_with("192.168.") or address.begins_with("10."):
				return address + ":" + str(PORT)
			# Check for 172.16-31.x.x range
			if address.begins_with("172."):
				var parts := address.split(".")
				if parts.size() >= 2:
					var second_octet := parts[1].to_int()
					if second_octet >= 16 and second_octet <= 31:
						return address + ":" + str(PORT)
	
	# Fallback to localhost
	return "127.0.0.1:" + str(PORT)

func _connect_signals() -> void:
	# Disconnect first to avoid duplicates
	_disconnect_signals()
	# Then connect
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

func _disconnect_signals() -> void:
	if multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.disconnect(_on_peer_connected)
	if multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.disconnect(_on_peer_disconnected)

func _on_peer_connected(id: int) -> void:
	# Only server handles spawns
	if multiplayer.is_server():
		get_tree().call_group("game", "server_spawn_player", id)

func _on_peer_disconnected(id: int) -> void:
	# Only server handles despawns
	if multiplayer.is_server():
		get_tree().call_group("game", "server_despawn_player", id)
		if player_names.has(id):
			player_names.erase(id)
			_sync_player_names()
		if player_races.has(id):
			player_races.erase(id)
			_sync_player_races()

## Internal cleanup (doesn't emit left_game signal)
func _cleanup_connection() -> void:
	_disconnect_signals()
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	peer = null
	player_names.clear()
	player_races.clear()
	player_rolls.clear()

## Disconnect from multiplayer session
func disconnect_from_game() -> void:
	_cleanup_connection()
	left_game.emit()

## Submit local player's name to the host
func submit_player_name(name: String) -> void:
	var cleaned := name.strip_edges()
	if cleaned.is_empty():
		return
	
	if multiplayer.is_server():
		_set_player_name(multiplayer.get_unique_id(), cleaned)
		_sync_player_names()
	else:
		set_player_name.rpc_id(1, cleaned)

## Submit local player's race to the host.
## Pass "" to unselect.
func submit_player_race(race: String) -> void:
	var cleaned := race.strip_edges()
	if multiplayer.is_server():
		_server_try_set_player_race(multiplayer.get_unique_id(), cleaned)
		_sync_player_races()
	else:
		set_player_race.rpc_id(1, cleaned)

@rpc("any_peer", "reliable")
func set_player_name(name: String) -> void:
	if not multiplayer.is_server():
		return
	
	var cleaned := name.strip_edges()
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

func _set_player_name(id: int, name: String) -> void:
	player_names[id] = name

func _sync_player_names() -> void:
	sync_player_names.rpc(player_names)

func _server_try_set_player_race(id: int, race: String) -> void:
	# Unselect
	if race.is_empty():
		if player_races.has(id):
			player_races.erase(id)
		return
	# Validate
	if not RACES.has(race):
		return
	# Enforce "one race per player"
	for pid in player_races.keys():
		if int(pid) != id and String(player_races[pid]) == race:
			return
	player_races[id] = race

func _sync_player_races() -> void:
	sync_player_races.rpc(player_races)

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

## RPC: Start the multiplayer race selection screen (called by host).
@rpc("authority", "call_local", "reliable")
func start_race_select() -> void:
	if multiplayer.is_server():
		_sync_player_races()
	App.go("res://scenes/ui/MultiplayerRaceSelect.tscn")

## RPC: Start the game (called by host, transitions everyone to GameIntro scene)
@rpc("authority", "call_local", "reliable")
func start_game() -> void:
	App.setup_multiplayer_game()
	App.go("res://scenes/ui/GameIntro.tscn")

## Host generates rolls for all players and syncs to everyone
func host_generate_and_sync_rolls() -> void:
	if not multiplayer.is_server():
		push_warning("Only host can generate rolls")
		return
	
	player_rolls.clear()
	
	# Generate initial rolls for all players
	for pid in player_races.keys():
		player_rolls[pid] = randi_range(1, 20)
	
	# Resolve ties by rerolling until all rolls are unique
	_resolve_roll_ties()
	
	print("Host generated rolls: ", player_rolls)
	
	# Sync to all clients
	_sync_player_rolls()

func _resolve_roll_ties() -> void:
	var max_attempts := 20
	var attempts := 0
	
	while attempts < max_attempts:
		var has_ties := false
		var roll_counts := {}  # roll_value -> array of player ids
		
		# Count occurrences of each roll
		for pid in player_rolls.keys():
			var roll_val: int = player_rolls[pid]
			if not roll_counts.has(roll_val):
				roll_counts[roll_val] = []
			roll_counts[roll_val].append(pid)
		
		# Find and resolve ties
		for roll_val in roll_counts.keys():
			if roll_counts[roll_val].size() > 1:
				has_ties = true
				print("Tie at roll ", roll_val, " - rerolling for: ", roll_counts[roll_val])
				# Reroll for all tied players
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
		# Client requests host to generate
		request_rolls_from_host.rpc_id(1)

@rpc("any_peer", "reliable")
func request_rolls_from_host() -> void:
	if multiplayer.is_server():
		host_generate_and_sync_rolls()

## ========== CARD BATTLE MULTIPLAYER ==========
## Server-authoritative state for the card battle scene.
## peer_id -> { slot_index (0-2) -> { "path": String, "frame": int } }
var battle_placed_cards: Dictionary = {}
## peer_id -> true when that player has pressed Start Battle
var battle_ready_peers: Dictionary = {}
## Emitted when any player's card placement changes (for remote display)
signal battle_cards_updated
## Emitted when server broadcasts that all players are ready and battle should start
signal battle_start_requested
## Emitted when a player leaves the battle (peer_id)
signal battle_player_left(peer_id: int)

## Clear battle state when leaving battle scene
func clear_battle_state() -> void:
	battle_placed_cards.clear()
	battle_ready_peers.clear()

## Request to place a card (client -> server). Server validates and broadcasts.
func request_place_battle_card(slot_index: int, sprite_frames_path: String, frame_index: int) -> void:
	if multiplayer.is_server():
		_server_place_battle_card(multiplayer.get_unique_id(), slot_index, sprite_frames_path, frame_index)
	else:
		place_battle_card.rpc_id(1, slot_index, sprite_frames_path, frame_index)

## Request to remove a card from a slot
func request_remove_battle_card(slot_index: int) -> void:
	if multiplayer.is_server():
		_server_remove_battle_card(multiplayer.get_unique_id(), slot_index)
	else:
		remove_battle_card.rpc_id(1, slot_index)

@rpc("any_peer", "reliable")
func place_battle_card(slot_index: int, sprite_frames_path: String, frame_index: int) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = multiplayer.get_unique_id()
	_server_place_battle_card(id, slot_index, sprite_frames_path, frame_index)

func _server_place_battle_card(peer_id: int, slot_index: int, sprite_frames_path: String, frame_index: int) -> void:
	if slot_index < 0 or slot_index > 2:
		return
	if not battle_placed_cards.has(peer_id):
		battle_placed_cards[peer_id] = {}
	battle_placed_cards[peer_id][slot_index] = {"path": sprite_frames_path, "frame": frame_index}
	sync_battle_cards.rpc(battle_placed_cards)

@rpc("any_peer", "reliable")
func remove_battle_card(slot_index: int) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = multiplayer.get_unique_id()
	_server_remove_battle_card(id, slot_index)

func _server_remove_battle_card(peer_id: int, slot_index: int) -> void:
	if battle_placed_cards.has(peer_id) and battle_placed_cards[peer_id].has(slot_index):
		battle_placed_cards[peer_id].erase(slot_index)
		sync_battle_cards.rpc(battle_placed_cards)

@rpc("authority", "call_local", "reliable")
func sync_battle_cards(cards: Dictionary) -> void:
	battle_placed_cards = cards.duplicate(true)
	battle_cards_updated.emit()

## Request to mark self as ready for battle (Start Battle pressed)
func request_battle_ready() -> void:
	if multiplayer.is_server():
		_server_set_battle_ready(multiplayer.get_unique_id())
	else:
		set_battle_ready.rpc_id(1)

@rpc("any_peer", "reliable")
func set_battle_ready() -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = multiplayer.get_unique_id()
	_server_set_battle_ready(id)

func _server_set_battle_ready(peer_id: int) -> void:
	battle_ready_peers[peer_id] = true
	# Check if all players in the game have pressed ready
	var all_peers: Array = []
	all_peers.append(multiplayer.get_unique_id())
	for pid in multiplayer.get_peers():
		all_peers.append(pid)
	var all_ready := true
	for pid in all_peers:
		if not battle_ready_peers.get(pid, false):
			all_ready = false
			break
	if all_ready:
		start_battle.rpc()

@rpc("authority", "call_local", "reliable")
func start_battle() -> void:
	battle_start_requested.emit()

## Notify server that local player is leaving the battle (for persistence)
func notify_battle_left() -> void:
	var my_id := multiplayer.get_unique_id()
	battle_player_left.emit(my_id)
	# Persist our cards to App for restoration when returning
	if battle_placed_cards.has(my_id):
		App.battle_placed_cards = battle_placed_cards[my_id].duplicate(true)
	else:
		App.battle_placed_cards = {}

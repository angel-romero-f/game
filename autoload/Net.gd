extends Node

const PORT := 9999
const MAX_CLIENTS := 4

var peer: ENetMultiplayerPeer

signal joined_game
signal left_game
signal player_names_updated
signal player_races_updated

var player_names: Dictionary = {}
var player_races: Dictionary = {} # peer_id -> race_name (String)

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

## RPC: Start the game (called by host, transitions everyone to Game scene)
@rpc("authority", "call_local", "reliable")
func start_game() -> void:
	App.go("res://scenes/Game.tscn")

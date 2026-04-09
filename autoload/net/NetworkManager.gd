extends Node

## NetworkManager — Pure connection transport layer.
## Handles hosting, joining, disconnecting, and peer lifecycle events.
## No game logic — only networking plumbing.

const PORT := 9999
const MAX_CLIENTS := 4
const DEBUG_NETWORKING := false

var peer: ENetMultiplayerPeer

signal joined_game
signal left_game
signal peer_connected_signal(id: int)
signal peer_disconnected_signal(id: int)
signal connection_closing

## Host a game server. Returns true on success, false on failure.
func host_game() -> bool:
	if multiplayer.multiplayer_peer:
		_cleanup_connection()

	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_CLIENTS)
	if err != OK:
		push_error("create_server failed: %s" % err)
		peer = null
		return false
	multiplayer.multiplayer_peer = peer
	_connect_signals()
	joined_game.emit()
	return true

## Join a game using code string like:
## - IPv4: "192.168.1.12" or "192.168.1.12:9999"
## - IPv6: "2607:fb91::1" or "[2607:fb91::1]:9999"
func join_game(code: String) -> void:
	_debug_log("=== JOIN_GAME CALLED ===")
	_debug_log("Raw code input: '%s'" % code)

	var ip := ""
	var port := PORT

	code = code.strip_edges()

	if code.begins_with("["):
		var bracket_end := code.find("]")
		if bracket_end > 0:
			ip = code.substr(1, bracket_end - 1)
			if code.length() > bracket_end + 1 and code[bracket_end + 1] == ":":
				port = code.substr(bracket_end + 2).to_int()
				if port <= 0:
					port = PORT
		else:
			ip = code
	elif code.count(":") > 1:
		ip = code
	elif ":" in code:
		var parts := code.split(":")
		if parts.size() >= 2:
			ip = parts[0]
		else:
			ip = code
	else:
		ip = code

	_debug_log("Parsed IP: '%s', Port: %d" % [ip, port])
	_debug_log("IP type: %s" % ("IPv6" if ":" in ip else "IPv4"))

	if ip.is_empty():
		push_error("Invalid host code: empty IP")
		return

	if multiplayer.multiplayer_peer:
		_debug_log("Cleaning up existing peer connection")
		_cleanup_connection()

	peer = ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		push_error("create_client failed with error %s" % err)
		_debug_log("create_client failed with error %s" % err)
		peer = null
		return

	multiplayer.multiplayer_peer = peer
	_connect_signals()

	_debug_log("Client peer created, connecting to %s:%d..." % [ip, port])
	_debug_log("Local addresses on this machine:")
	for addr in IP.get_local_addresses():
		if typeof(addr) == TYPE_STRING:
			_debug_log("  - %s" % String(addr))

## Get the host's likely network address (IPv4 or IPv6)
func get_host_code() -> String:
	var addresses := IP.get_local_addresses()

	_debug_log("get_host_code() - Scanning for network IP...")
	_debug_log("All addresses found: %s" % str(addresses))

	var ipv4_candidates: Array = []
	var ipv6_candidates: Array = []

	for address in addresses:
		if typeof(address) != TYPE_STRING:
			continue

		if ":" in address:
			if address == "0:0:0:0:0:0:0:1" or address == "::1":
				_debug_log("  Skipping %s (IPv6 localhost)" % address)
				continue
			if address.begins_with("fe80:"):
				_debug_log("  Skipping %s (IPv6 link-local)" % address)
				continue
			if address.begins_with("2") or address.begins_with("3"):
				ipv6_candidates.append({"ip": address, "reason": "IPv6 global"})
				_debug_log("  IPv6 Candidate: %s (global unicast)" % address)
			continue

		if address == "127.0.0.1" or address.begins_with("127."):
			_debug_log("  Skipping %s (IPv4 localhost)" % address)
			continue

		var parts := address.split(".")
		if parts.size() != 4:
			continue

		if address.begins_with("192.0.0.") or address.begins_with("192.0.2.") or address.begins_with("198.51.100.") or address.begins_with("203.0.113."):
			_debug_log("  Skipping %s (IANA reserved - not routable)" % address)
			continue

		if address.begins_with("192.168.64.") or address.begins_with("192.168.56."):
			_debug_log("  Skipping %s (VM bridge - not reachable externally)" % address)
			continue

		if address.begins_with("192.168."):
			ipv4_candidates.append({"ip": address, "priority": 1, "reason": "192.168.x.x LAN"})
			_debug_log("  IPv4 Candidate: %s (priority 1 - 192.168.x.x LAN)" % address)
		elif address.begins_with("10."):
			ipv4_candidates.append({"ip": address, "priority": 1, "reason": "10.x.x.x LAN"})
			_debug_log("  IPv4 Candidate: %s (priority 1 - 10.x.x.x LAN)" % address)
		elif address.begins_with("172."):
			var second_octet := parts[1].to_int()
			if second_octet >= 16 and second_octet <= 31:
				ipv4_candidates.append({"ip": address, "priority": 3, "reason": "172.x private (may be VM/container)"})
				_debug_log("  IPv4 Candidate: %s (priority 3 - 172.x private, may be VM/container)" % address)
		else:
			ipv4_candidates.append({"ip": address, "priority": 3, "reason": "other IPv4"})
			_debug_log("  IPv4 Candidate: %s (priority 3 - other network IP)" % address)

	if ipv4_candidates.size() > 0:
		ipv4_candidates.sort_custom(func(a, b): return a["priority"] < b["priority"])
		var best = ipv4_candidates[0]
		_debug_log("  SELECTED IPv4: %s (%s)" % [best["ip"], best["reason"]])
		return best["ip"]

	if ipv6_candidates.size() > 0:
		var best = ipv6_candidates[0]
		_debug_log("  SELECTED IPv6: %s (%s)" % [best["ip"], best["reason"]])
		_debug_log("  NOTE: IPv6-only network detected. Both devices must support IPv6.")
		return best["ip"]

	_debug_log("  WARNING: No network IP found! Falling back to 127.0.0.1")
	_debug_log("  This means networking will ONLY work on the same machine!")
	return "127.0.0.1"

## Disconnect from multiplayer session
func disconnect_from_game() -> void:
	_cleanup_connection()
	left_game.emit()

## Get all connected peer IDs including host
func get_all_peer_ids() -> Array:
	var peers: Array = []
	peers.append(multiplayer.get_unique_id())
	for pid in multiplayer.get_peers():
		peers.append(pid)
	return peers

## Internal cleanup (doesn't emit left_game signal)
func _cleanup_connection() -> void:
	connection_closing.emit()
	_disconnect_signals()
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	peer = null

func _connect_signals() -> void:
	_disconnect_signals()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

func _disconnect_signals() -> void:
	if multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.disconnect(_on_peer_connected)
	if multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.disconnect(_on_peer_disconnected)

func _on_peer_connected(id: int) -> void:
	peer_connected_signal.emit(id)
	if multiplayer.is_server():
		get_tree().call_group("game", "server_spawn_player", id)

func _on_peer_disconnected(id: int) -> void:
	peer_disconnected_signal.emit(id)
	if multiplayer.is_server():
		get_tree().call_group("game", "server_despawn_player", id)

func _debug_log(message: String) -> void:
	if DEBUG_NETWORKING:
		var timestamp := Time.get_time_string_from_system()
		print("[Net %s] %s" % [timestamp, message])

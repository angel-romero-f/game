extends Node

const PORT := 9999
const MAX_CLIENTS := 4

var peer: ENetMultiplayerPeer

signal joined_game
signal left_game
signal player_names_updated
signal player_races_updated
signal player_rolls_updated

# Phase sync signals
signal phase_changed(phase_id: int)
signal done_counts_updated(done_count: int, total: int)
signal battle_decider_changed(peer_id: int)
signal battle_choices_updated(snapshot: Dictionary)
signal battle_started(p1_id: int, p2_id: int, side: String)
signal battle_finished_broadcast()

var player_names: Dictionary = {}
var player_races: Dictionary = {} # peer_id -> race_name (String)
var player_rolls: Dictionary = {} # peer_id -> roll value (int)

# ========== PHASE SYNC STATE ==========
# Current game phase: 0 = RESOURCE_PHASE, 1 = BATTLE_PHASE
var current_phase: int = 0
# Per-player done state in current phase: {peer_id: bool}
var player_done_state: Dictionary = {}
# Per-player minigame counts for resource phase: {peer_id: int}
var player_minigame_counts: Dictionary = {}

# ========== BATTLE PHASE STATE ==========
# Current position in turn order for battle decisions
var battle_decision_index: int = 0
# Current decider's peer_id
var battle_decider_peer_id: int = -1
# Each player's battle choice: {peer_id: "LEFT"/"RIGHT"/"SKIP"/"UNDECIDED"}
var battle_choices: Dictionary = {}
# Queues for each battle option (max 2 each)
var left_queue: Array = []
var right_queue: Array = []
# Whether a battle is currently in progress
var battle_in_progress: bool = false
# The 2 participants in the active battle
var active_battle_participants: Array = []
# Which side the active battle is for
var active_battle_side: String = ""
# Reports from participants that they finished the battle
var battle_finished_reports: Dictionary = {} # {peer_id: bool}

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

## Get the host's likely LAN IP address (IP only, no port)
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
				return address
			# Check for 172.16-31.x.x range
			if address.begins_with("172."):
				var parts := address.split(".")
				if parts.size() >= 2:
					var second_octet := parts[1].to_int()
					if second_octet >= 16 and second_octet <= 31:
						return address
	
	# Fallback to localhost
	return "127.0.0.1"

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
	# Host initializes phase state for all participants
	if multiplayer.is_server():
		host_init_resource_phase()
	App.go("res://scenes/ui/GameIntro.tscn")

## Host: Initialize resource phase for all participants (call at game start and when returning to resource)
func host_init_resource_phase() -> void:
	if not multiplayer.is_server():
		return

	reset_phase_sync_state()
	current_phase = 0
	_init_phase_done_state()

	var all_peers := _get_all_peer_ids()
	var total := all_peers.size()
	print("[Net] Host init resource phase with ", total, " participants: ", all_peers)

	# Broadcast initial state to all clients
	rpc_set_phase.rpc(0)
	rpc_sync_done_state.rpc(player_done_state.duplicate(), player_minigame_counts.duplicate()) # <<< ADD THIS
	rpc_sync_done_counts.rpc(0, total)

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
	# Persist our cards to BattleStateManager for restoration when returning
	if BattleStateManager:
		var territory_id := BattleStateManager.current_territory_id
		BattleStateManager.clear_local_slots(territory_id)
		if battle_placed_cards.has(my_id):
			var placed: Dictionary = battle_placed_cards[my_id]
			for slot_idx in placed:
				var data: Dictionary = placed[slot_idx]
				var path: String = data.get("path", "")
				var frame: int = int(data.get("frame", 0))
				if not path.is_empty():
					BattleStateManager.set_local_slot(int(slot_idx), path, frame, territory_id)

# ========== PHASE SYNC SYSTEM ==========

## Reset all phase-related state for a new game
func reset_phase_sync_state() -> void:
	current_phase = 0
	player_done_state.clear()
	player_minigame_counts.clear()
	battle_decision_index = 0
	battle_decider_peer_id = -1
	battle_choices.clear()
	left_queue.clear()
	right_queue.clear()
	battle_in_progress = false
	active_battle_participants.clear()
	active_battle_side = ""
	battle_finished_reports.clear()

## Get all connected peer IDs including host
func _get_all_peer_ids() -> Array:
	var peers: Array = []
	peers.append(multiplayer.get_unique_id())
	for pid in multiplayer.get_peers():
		peers.append(pid)
	return peers

## Initialize done state for all players at phase start
func _init_phase_done_state() -> void:
	player_done_state.clear()
	player_minigame_counts.clear()
	for pid in _get_all_peer_ids():
		player_done_state[pid] = false
		player_minigame_counts[pid] = 0

## Count how many players are done
func _count_done_players() -> int:
	var count := 0
	for pid in player_done_state.keys():
		if player_done_state.get(pid, false):
			count += 1
	return count

## Check if all players are done and advance phase if so
func _check_all_done_and_advance() -> void:
	if not multiplayer.is_server():
		return
	var all_peers := _get_all_peer_ids()
	var done_count := _count_done_players()
	
	# Broadcast updated done state dictionary AND counts to all clients
	rpc_sync_done_state.rpc(player_done_state.duplicate(), player_minigame_counts.duplicate())
	rpc_sync_done_counts.rpc(done_count, all_peers.size())
	
	if done_count >= all_peers.size():
		# All done - advance to next phase
		if current_phase == 0:
			_server_enter_battle_phase()

## Client requests to increment their minigame count
func request_increment_minigame() -> void:
	if multiplayer.is_server():
		_server_increment_minigame(multiplayer.get_unique_id())
	else:
		server_increment_minigame.rpc_id(1)

@rpc("any_peer", "reliable")
func server_increment_minigame() -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = multiplayer.get_unique_id()
	_server_increment_minigame(id)

func _server_increment_minigame(peer_id: int) -> void:
	# REJECT if player is already done or count >= 2
	if player_done_state.get(peer_id, false):
		print("[Net] REJECTED minigame increment from ", peer_id, " (already done)")
		return
	var current_count: int = player_minigame_counts.get(peer_id, 0)
	if current_count >= 2:
		print("[Net] REJECTED minigame increment from ", peer_id, " (already at 2)")
		return
	
	var count: int = current_count + 1
	player_minigame_counts[peer_id] = count
	print("[Net] Player ", peer_id, " minigame count: ", count)
	
	# Auto-mark done at 2 minigames
	if count >= 2:
		player_done_state[peer_id] = true
		print("[Net] Player ", peer_id, " auto-marked done (2 minigames)")
	
	_check_all_done_and_advance()

## Client requests to skip (mark done early)
func request_skip_to_done() -> void:
	if multiplayer.is_server():
		_server_mark_done(multiplayer.get_unique_id())
	else:
		server_skip_to_done.rpc_id(1)

@rpc("any_peer", "reliable")
func server_skip_to_done() -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = multiplayer.get_unique_id()
	_server_mark_done(id)

func _server_mark_done(peer_id: int) -> void:
	player_done_state[peer_id] = true
	print("[Net] Player ", peer_id, " marked done (skip)")
	_check_all_done_and_advance()

## Authority broadcasts new phase
@rpc("authority", "call_local", "reliable")
func rpc_set_phase(phase_id: int) -> void:
	current_phase = phase_id
	phase_changed.emit(phase_id)

## Authority broadcasts done state dictionaries to clients
@rpc("authority", "call_local", "reliable")
func rpc_sync_done_state(done_state: Dictionary, minigame_counts: Dictionary) -> void:
	player_done_state = done_state.duplicate()
	player_minigame_counts = minigame_counts.duplicate()

## Authority broadcasts done counts
@rpc("authority", "call_local", "reliable")
func rpc_sync_done_counts(done: int, total: int) -> void:
	done_counts_updated.emit(done, total)

## Server enters battle phase
func _server_enter_battle_phase() -> void:
	if not multiplayer.is_server():
		return
	current_phase = 1
	rpc_set_phase.rpc(1)
	_init_battle_phase()

## Initialize battle phase state
func _init_battle_phase() -> void:
	battle_decision_index = 0
	battle_choices.clear()
	left_queue.clear()
	right_queue.clear()
	battle_in_progress = false
	active_battle_participants.clear()
	active_battle_side = ""
	battle_finished_reports.clear()
	
	# Initialize all players as UNDECIDED
	for pid in _get_all_peer_ids():
		battle_choices[pid] = "UNDECIDED"
	
	# Set first decider based on turn order
	_advance_decider_to_next_eligible()

## Advance to the next eligible decider (skip those who already chose or are in battle)
func _advance_decider_to_next_eligible() -> void:
	if not multiplayer.is_server():
		return
	
	# If battle in progress, wait
	if battle_in_progress:
		return
	
	var turn_order := App.turn_order
	if turn_order.is_empty():
		return
	
	# Check if both queues are full - auto-skip remaining UNDECIDED
	if left_queue.size() >= 2 and right_queue.size() >= 2:
		for pid in battle_choices.keys():
			if battle_choices[pid] == "UNDECIDED":
				battle_choices[pid] = "SKIP"
				print("[Net] Auto-skipped player ", pid, " (both queues full)")
		_sync_battle_state()
		_check_battle_phase_complete()
		return
	
	# Find next eligible player
	var found := false
	var start_idx := battle_decision_index
	
	for i in range(turn_order.size()):
		var idx := (start_idx + i) % turn_order.size()
		var player = turn_order[idx]
		var pid: int = player.get("id", -1)
		
		# Skip if already made a choice
		if battle_choices.get(pid, "UNDECIDED") != "UNDECIDED":
			continue
		
		# Skip if in active battle
		if active_battle_participants.has(pid):
			continue
		
		# Found eligible player
		battle_decision_index = idx
		battle_decider_peer_id = pid
		found = true
		break
	
	if found:
		print("[Net] Battle decider set to: ", battle_decider_peer_id)
		rpc_set_battle_decider.rpc(battle_decider_peer_id)
		_sync_battle_state()
	else:
		# No eligible players - check if phase is complete
		_check_battle_phase_complete()

## Check if battle phase is complete (all decided and no battle in progress)
func _check_battle_phase_complete() -> void:
	if battle_in_progress:
		return
	
	var all_decided := true
	for pid in battle_choices.keys():
		if battle_choices[pid] == "UNDECIDED":
			all_decided = false
			break
	
	if all_decided:
		print("[Net] Battle phase complete, returning to resource phase")
		# Use host_init_resource_phase for consistent initialization
		host_init_resource_phase()

## Authority broadcasts current decider
@rpc("authority", "call_local", "reliable")
func rpc_set_battle_decider(peer_id: int) -> void:
	battle_decider_peer_id = peer_id
	battle_decider_changed.emit(peer_id)

## Client submits their battle choice
func request_battle_choice(choice: String) -> void:
	if multiplayer.is_server():
		_server_process_battle_choice(multiplayer.get_unique_id(), choice)
	else:
		server_battle_choice.rpc_id(1, choice)

@rpc("any_peer", "reliable")
func server_battle_choice(choice: String) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = multiplayer.get_unique_id()
	_server_process_battle_choice(id, choice)

func _server_process_battle_choice(peer_id: int, choice: String) -> void:
	# Validate it's this player's turn
	if peer_id != battle_decider_peer_id:
		print("[Net] Rejected choice from ", peer_id, " (not their turn)")
		return
	
	# Validate choice
	if choice not in ["LEFT", "RIGHT", "SKIP"]:
		print("[Net] Invalid choice: ", choice)
		return
	
	# Check if queue is full
	if choice == "LEFT" and left_queue.size() >= 2:
		print("[Net] Left queue full, rejecting")
		return
	if choice == "RIGHT" and right_queue.size() >= 2:
		print("[Net] Right queue full, rejecting")
		return
	
	# Record choice
	battle_choices[peer_id] = choice
	print("[Net] Player ", peer_id, " chose: ", choice)
	
	# Add to queue if not skip
	if choice == "LEFT":
		left_queue.append(peer_id)
	elif choice == "RIGHT":
		right_queue.append(peer_id)
	
	_sync_battle_state()
	
	# Check if a battle should start (2 players in same queue)
	if left_queue.size() == 2:
		_start_paired_battle(left_queue[0], left_queue[1], "LEFT")
	elif right_queue.size() == 2:
		_start_paired_battle(right_queue[0], right_queue[1], "RIGHT")
	else:
		# Advance to next decider
		battle_decision_index += 1
		_advance_decider_to_next_eligible()

## Sync battle state to all clients
func _sync_battle_state() -> void:
	var snapshot := {
		"choices": battle_choices.duplicate(),
		"left_queue": left_queue.duplicate(),
		"right_queue": right_queue.duplicate(),
		"battle_in_progress": battle_in_progress,
		"active_participants": active_battle_participants.duplicate(),
		"active_side": active_battle_side,
	}
	rpc_sync_battle_state.rpc(snapshot)

@rpc("authority", "call_local", "reliable")
func rpc_sync_battle_state(snapshot: Dictionary) -> void:
	battle_choices = snapshot.get("choices", {}).duplicate()
	left_queue = snapshot.get("left_queue", []).duplicate()
	right_queue = snapshot.get("right_queue", []).duplicate()
	battle_in_progress = snapshot.get("battle_in_progress", false)
	active_battle_participants = snapshot.get("active_participants", []).duplicate()
	active_battle_side = snapshot.get("active_side", "")
	battle_choices_updated.emit(snapshot)

## Start a paired battle between two players
func _start_paired_battle(p1_id: int, p2_id: int, side: String) -> void:
	if not multiplayer.is_server():
		return
	
	print("[Net] Starting paired battle: ", p1_id, " vs ", p2_id, " on ", side)
	battle_in_progress = true
	active_battle_participants = [p1_id, p2_id]
	active_battle_side = side
	battle_finished_reports.clear()
	
	_sync_battle_state()
	rpc_start_paired_battle.rpc(p1_id, p2_id, side)

@rpc("authority", "call_local", "reliable")
func rpc_start_paired_battle(p1_id: int, p2_id: int, side: String) -> void:
	battle_started.emit(p1_id, p2_id, side)

## Called by battle participants when they finish the battle
func notify_battle_finished() -> void:
	if multiplayer.is_server():
		_server_battle_finished_report(multiplayer.get_unique_id())
	else:
		server_battle_finished.rpc_id(1)

@rpc("any_peer", "reliable")
func server_battle_finished() -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = multiplayer.get_unique_id()
	_server_battle_finished_report(id)

func _server_battle_finished_report(peer_id: int) -> void:
	if not active_battle_participants.has(peer_id):
		return
	
	battle_finished_reports[peer_id] = true
	print("[Net] Battle finished report from: ", peer_id)
	
	# Check if BOTH participants reported
	var both_done := true
	for pid in active_battle_participants:
		if not battle_finished_reports.get(pid, false):
			both_done = false
			break
	
	if both_done:
		print("[Net] Both participants finished, resuming decisions")
		var p1: int = int(active_battle_participants[0]) if active_battle_participants.size() > 0 else -1
		var p2: int = int(active_battle_participants[1]) if active_battle_participants.size() > 1 else -1
		var side: String = String(active_battle_side)

		
		# Clear the queue that was used
		if side == "LEFT":
			left_queue.clear()
		elif side == "RIGHT":
			right_queue.clear()
		
		# Reset battle state
		battle_in_progress = false
		active_battle_participants.clear()
		active_battle_side = ""
		battle_finished_reports.clear()
		
		_sync_battle_state()
		rpc_battle_finished.rpc(p1, p2, side)
		
		# Resume decisions
		_advance_decider_to_next_eligible()

@rpc("authority", "call_local", "reliable")
func rpc_battle_finished(p1_id: int, p2_id: int, side: String) -> void:
	battle_finished_broadcast.emit()

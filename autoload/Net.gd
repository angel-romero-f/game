extends Node

## Net — Thin facade for backward compatibility.
## Delegates all functionality to the decoupled modules:
##   NetworkManager  (connection transport)
##   PlayerDataSync  (player data sync)
##   PhaseController (phase state)
##   PhaseSync       (phase RPCs)
##   BattleSync      (battle coordination)
##   TerritorySync   (territory claiming)
##
## New code should reference the specific modules directly.

# ---------- FORWARDED SIGNALS ----------
# Connection
signal joined_game
signal left_game
# Player data
signal player_names_updated
signal player_races_updated
signal player_rolls_updated
# Phase
signal phase_changed(phase_id: int)
signal done_counts_updated(done_count: int, total: int)
signal turn_changed(peer_id: int)
signal map_sub_phase_changed(sub_phase: int)
# Battle
signal battle_decider_changed(peer_id: int)
signal battle_choices_updated(snapshot: Dictionary)
signal battle_started(p1_id: int, p2_id: int, side: String)
signal battle_finished_broadcast()
signal battle_cards_updated
signal battle_start_requested
signal battle_player_left(peer_id: int)
# Territory
signal territory_claimed(territory_id: int, owner_id: int, cards: Array)
signal territory_claim_rejected(territory_id: int, claimer_name: String)

func _ready() -> void:
	# Forward connection signals
	NetworkManager.joined_game.connect(func(): joined_game.emit())
	NetworkManager.left_game.connect(func(): left_game.emit())

	# Forward player data signals
	PlayerDataSync.player_names_updated.connect(func(): player_names_updated.emit())
	PlayerDataSync.player_races_updated.connect(func(): player_races_updated.emit())
	PlayerDataSync.player_rolls_updated.connect(func(): player_rolls_updated.emit())

	# Forward phase signals
	PhaseController.phase_changed.connect(func(id): phase_changed.emit(id))
	PhaseController.turn_changed.connect(func(id): turn_changed.emit(id))
	PhaseController.done_counts_updated.connect(func(d, t): done_counts_updated.emit(d, t))
	PhaseController.map_sub_phase_changed.connect(func(sp): map_sub_phase_changed.emit(sp))

	# Forward battle signals
	BattleSync.battle_decider_changed.connect(func(id): battle_decider_changed.emit(id))
	BattleSync.battle_choices_updated.connect(func(s): battle_choices_updated.emit(s))
	BattleSync.battle_started.connect(func(p1, p2, side): battle_started.emit(p1, p2, side))
	BattleSync.battle_finished_broadcast.connect(func(): battle_finished_broadcast.emit())
	BattleSync.battle_cards_updated.connect(func(): battle_cards_updated.emit())
	BattleSync.battle_start_requested.connect(func(): battle_start_requested.emit())
	BattleSync.battle_player_left.connect(func(id): battle_player_left.emit(id))

	# Forward territory signals
	TerritorySync.territory_claimed.connect(func(tid, oid, c): territory_claimed.emit(tid, oid, c))
	TerritorySync.territory_claim_rejected.connect(func(tid, n): territory_claim_rejected.emit(tid, n))

# ---------- PLAYER DATA PROPERTIES (delegated to PlayerDataSync) ----------
var player_names: Dictionary:
	get: return PlayerDataSync.player_names
	set(v): PlayerDataSync.player_names = v

var player_races: Dictionary:
	get: return PlayerDataSync.player_races
	set(v): PlayerDataSync.player_races = v

var player_rolls: Dictionary:
	get: return PlayerDataSync.player_rolls
	set(v): PlayerDataSync.player_rolls = v

# ---------- PHASE STATE PROPERTIES (delegated to PhaseController) ----------
var current_phase: int:
	get: return PhaseController.current_phase
	set(v): PhaseController.current_phase = v

var map_sub_phase: int:
	get: return PhaseController.map_sub_phase
	set(v): PhaseController.map_sub_phase = v

var player_done_state: Dictionary:
	get: return PhaseController.player_done_state
	set(v): PhaseController.player_done_state = v

var player_minigame_counts: Dictionary:
	get: return PhaseController.player_minigame_counts
	set(v): PhaseController.player_minigame_counts = v

var current_turn_peer_id: int:
	get: return PhaseController.current_turn_peer_id
	set(v): PhaseController.current_turn_peer_id = v

var current_turn_index: int:
	get: return PhaseController.current_turn_index
	set(v): PhaseController.current_turn_index = v

# ---------- BATTLE STATE PROPERTIES (delegated to BattleSync) ----------
var battle_decision_index: int:
	get: return BattleSync.battle_decision_index
	set(v): BattleSync.battle_decision_index = v

var battle_decider_peer_id: int:
	get: return BattleSync.battle_decider_peer_id
	set(v): BattleSync.battle_decider_peer_id = v

var battle_choices: Dictionary:
	get: return BattleSync.battle_choices
	set(v): BattleSync.battle_choices = v

var left_queue: Array:
	get: return BattleSync.left_queue
	set(v): BattleSync.left_queue = v

var right_queue: Array:
	get: return BattleSync.right_queue
	set(v): BattleSync.right_queue = v

var battle_in_progress: bool:
	get: return BattleSync.battle_in_progress
	set(v): BattleSync.battle_in_progress = v

var active_battle_participants: Array:
	get: return BattleSync.active_battle_participants
	set(v): BattleSync.active_battle_participants = v

var active_battle_side: String:
	get: return BattleSync.active_battle_side
	set(v): BattleSync.active_battle_side = v

var battle_finished_reports: Dictionary:
	get: return BattleSync.battle_finished_reports
	set(v): BattleSync.battle_finished_reports = v

var battle_placed_cards: Dictionary:
	get: return BattleSync.battle_placed_cards
	set(v): BattleSync.battle_placed_cards = v

var battle_ready_peers: Dictionary:
	get: return BattleSync.battle_ready_peers
	set(v): BattleSync.battle_ready_peers = v

# ---------- CONSTANTS ----------
const RACES := ["Elf", "Orc", "Fairy", "Infernal"]
const PORT := 9999
const MAX_CLIENTS := 4

# ---------- CONNECTION METHODS (delegated to NetworkManager) ----------
func host_game() -> bool: return NetworkManager.host_game()
func join_game(code: String) -> void: NetworkManager.join_game(code)
func get_host_code() -> String: return NetworkManager.get_host_code()
func disconnect_from_game() -> void: NetworkManager.disconnect_from_game()

# ---------- PLAYER DATA METHODS (delegated to PlayerDataSync) ----------
func submit_player_name(player_name: String) -> void: PlayerDataSync.submit_player_name(player_name)
func submit_player_race(race: String) -> void: PlayerDataSync.submit_player_race(race)
func host_generate_and_sync_rolls() -> void: PlayerDataSync.host_generate_and_sync_rolls()
func request_roll_generation() -> void: PlayerDataSync.request_roll_generation()

# ---------- PHASE METHODS (delegated to PhaseSync) ----------
func host_init_card_command_phase() -> void: PhaseSync.host_init_card_command_phase()
func host_init_card_collection_phase() -> void: PhaseSync.host_init_card_collection_phase()
func request_end_card_command_turn() -> void: PhaseSync.request_end_card_command_turn()
func request_end_claiming_turn() -> void: PhaseSync.request_end_claiming_turn()
func request_increment_minigame() -> void: PhaseSync.request_increment_minigame()
func request_skip_to_done() -> void: PhaseSync.request_skip_to_done()

func reset_phase_sync_state() -> void:
	PhaseController.reset()
	BattleSync.reset_battle_state()

# ---------- BATTLE METHODS (delegated to BattleSync) ----------
func clear_battle_state() -> void: BattleSync.clear_battle_state()
func request_place_battle_card(slot_index: int, sprite_frames_path: String, frame_index: int) -> void:
	BattleSync.request_place_battle_card(slot_index, sprite_frames_path, frame_index)
func request_remove_battle_card(slot_index: int) -> void: BattleSync.request_remove_battle_card(slot_index)
func request_battle_ready() -> void: BattleSync.request_battle_ready()
func notify_battle_left() -> void: BattleSync.notify_battle_left()
func notify_battle_finished() -> void: BattleSync.notify_battle_finished()
func request_start_territory_battle(territory_id: int) -> void: BattleSync.request_start_territory_battle(territory_id)
func request_battle_choice(choice: String) -> void: BattleSync.request_battle_choice(choice)

# ---------- TERRITORY METHODS (delegated to TerritorySync) ----------
func request_claim_territory(territory_id: int, owner_id: int, cards: Array) -> void:
	TerritorySync.request_claim_territory(territory_id, owner_id, cards)

# ---------- RPC METHODS (needed because consumers call Net.xyz.rpc()) ----------
# These RPCs execute on all peers via the Net autoload node.

@rpc("authority", "call_local", "reliable")
func start_race_select() -> void:
	if multiplayer.is_server():
		PlayerDataSync._sync_player_races()
	App.go("res://scenes/ui/MultiplayerRaceSelect.tscn")

@rpc("authority", "call_local", "reliable")
func start_game() -> void:
	App.setup_multiplayer_game()
	App.go("res://scenes/ui/GameIntro.tscn")

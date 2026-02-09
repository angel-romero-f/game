extends Node

## Simple scene navigation helper + small UI state
var player_name: String = ""
var next_scene: String = ""
var selected_race: String = "Elf"

## Game players data for turn order
## Array of dictionaries: { "id": int, "name": String, "race": String, "roll": int, "is_local": bool }
var game_players: Array = []
var turn_order: Array = []  # Sorted game_players by roll (highest first)
var is_multiplayer: bool = false

## Lives system for minigame
const MAX_LIVES: int = 3
var current_lives: int = MAX_LIVES

## ========== PHASE SYSTEM ==========
## Game alternates between Resource Collection and Battle phases
enum GamePhase { RESOURCE_PHASE, BATTLE_PHASE }

signal game_phase_changed(new_phase: GamePhase)
signal minigame_completed_signal  # Emitted when a minigame is won

var current_game_phase: GamePhase = GamePhase.RESOURCE_PHASE
var minigames_completed_this_phase: int = 0
const MAX_MINIGAMES_PER_PHASE: int = 2

## Flag to show phase transition overlay when returning to GameIntro
var show_phase_transition: bool = false
var phase_transition_text: String = ""

## When returning from a territory minigame: restore GameIntro map sub-phase (0=CLAIMING, 1=RESOURCE_COLLECTION, 2=BATTLE_READY). -1 = not returning.
var pending_return_map_sub_phase: int = -1
## True when we left for a minigame from territory; GameIntro will call on_minigame_completed() when it loads.
var returning_from_territory_minigame: bool = false

func enter_resource_phase() -> void:
	current_game_phase = GamePhase.RESOURCE_PHASE
	minigames_completed_this_phase = 0
	phase_transition_text = "Collect Your Resources"
	show_phase_transition = true
	print("[Phase] Entering RESOURCE_PHASE")
	game_phase_changed.emit(current_game_phase)

func enter_battle_phase() -> void:
	current_game_phase = GamePhase.BATTLE_PHASE
	phase_transition_text = "Choose Your Battles"
	show_phase_transition = true
	print("[Phase] Entering BATTLE_PHASE")
	game_phase_changed.emit(current_game_phase)

func on_minigame_completed() -> void:
	## Called when player wins a minigame
	minigames_completed_this_phase += 1
	print("[Phase] Minigame completed. Count: ", minigames_completed_this_phase, "/", MAX_MINIGAMES_PER_PHASE)
	minigame_completed_signal.emit()
	
	# In multiplayer, notify host of minigame completion (host controls phase)
	if is_multiplayer and multiplayer.has_multiplayer_peer():
		Net.request_increment_minigame()
		# Don't auto-transition locally - host will broadcast phase change
		return
	
	# Single player: check if we should auto-transition to battle phase
	if minigames_completed_this_phase >= MAX_MINIGAMES_PER_PHASE:
		print("[Phase] Max minigames reached, transitioning to battle phase")
		enter_battle_phase()

func on_battle_completed() -> void:
	## Called when battle ends (win, lose, or tie)
	print("[Phase] Battle completed, returning to resource phase")
	# In multiplayer, phase transitions are handled by host after battle_finished
	if not is_multiplayer:
		enter_resource_phase()

func skip_to_battle_phase() -> void:
	## Called when player chooses to skip remaining minigames
	print("[Phase] Player skipping to battle phase")
	
	# In multiplayer, request host to mark us as done
	if is_multiplayer and multiplayer.has_multiplayer_peer():
		Net.request_skip_to_done()
		return
	
	# Single player: transition immediately
	enter_battle_phase()

func can_play_minigame() -> bool:
	## Returns true if player can still play minigames this phase
	# In multiplayer, check host-authoritative done state
	if is_multiplayer and multiplayer.has_multiplayer_peer():
		var my_id := multiplayer.get_unique_id()
		# If host marked us as done, we cannot play
		if Net.player_done_state.get(my_id, false):
			return false
		# Also check minigame count from host
		var count: int = Net.player_minigame_counts.get(my_id, 0)
		if count >= MAX_MINIGAMES_PER_PHASE:
			return false
	return current_game_phase == GamePhase.RESOURCE_PHASE and minigames_completed_this_phase < MAX_MINIGAMES_PER_PHASE

func reset_phase_state() -> void:
	## Reset phase state for a new game
	current_game_phase = GamePhase.RESOURCE_PHASE
	minigames_completed_this_phase = 0
	show_phase_transition = false
	phase_transition_text = ""
## ========== END PHASE SYSTEM ==========

## ========== PLAYER HAND SYSTEM ==========
## Available cards - each entry is {sprite_frames_path, frame_index}
## Race-specific card pools
const ELF_CARDS: Array = [
	{"sprite_frames": "res://assets/elf_fire_cards.pxo", "frame_index": 0},
	{"sprite_frames": "res://assets/elf_fire_cards.pxo", "frame_index": 1},
	{"sprite_frames": "res://assets/elf_fire_cards.pxo", "frame_index": 2},
	{"sprite_frames": "res://assets/elf_fire_cards.pxo", "frame_index": 3},
]

const INFERNAL_CARDS: Array = [
	{"sprite_frames": "res://assets/infernal_water_cards.pxo", "frame_index": 0},
	{"sprite_frames": "res://assets/infernal_water_cards.pxo", "frame_index": 1},
	{"sprite_frames": "res://assets/infernal_water_cards.pxo", "frame_index": 2},
	{"sprite_frames": "res://assets/infernal_water_cards.pxo", "frame_index": 3},
]

## Mixed pool for races without specific cards (Orc, Fairy)
const MIXED_CARD_POOL: Array = [
	{"sprite_frames": "res://assets/elf_fire_cards.pxo", "frame_index": 0},
	{"sprite_frames": "res://assets/elf_fire_cards.pxo", "frame_index": 1},
	{"sprite_frames": "res://assets/elf_fire_cards.pxo", "frame_index": 2},
	{"sprite_frames": "res://assets/elf_fire_cards.pxo", "frame_index": 3},
	{"sprite_frames": "res://assets/infernal_water_cards.pxo", "frame_index": 0},
	{"sprite_frames": "res://assets/infernal_water_cards.pxo", "frame_index": 1},
	{"sprite_frames": "res://assets/infernal_water_cards.pxo", "frame_index": 2},
	{"sprite_frames": "res://assets/infernal_water_cards.pxo", "frame_index": 3},
]

## Player's current hand - array of card data dictionaries (legacy, used for hand display)
var player_hand: Array = []

## Player's card collection - the cards they own. Format: [{ "path": String, "frame": int }, ...]
## At game start: 4 random cards. After minigame win: +1 random card.
var player_card_collection: Array = []

## Legacy: persisted card placements when leaving battle early (single active battle).
## slot_index (0-2) -> { "path": String, "frame": int }
## New code should prefer BattleStateManager for per-territory state.
var battle_placed_cards: Dictionary = {}

## ========== MAP TERRITORY OWNERSHIP ==========
## territory_id -> {
##   "owner_id": int,
##   "owner_name": String,
##   "owner_race": String,
##   "cards": Array[Dictionary]  # cards committed to this territory
## }
var territories: Dictionary = {}

func reset_territories() -> void:
	territories.clear()

func place_card_on_territory(territory_id: String, player: Dictionary, card_data: Dictionary) -> void:
	if territory_id.is_empty():
		return
	var t: Dictionary = territories.get(territory_id, {})
	t["owner_id"] = player.get("id", 0)
	t["owner_name"] = player.get("name", "Player")
	t["owner_race"] = player.get("race", "Elf")
	if not t.has("cards"):
		t["cards"] = []
	var cards: Array = t["cards"]
	cards.append(card_data.duplicate())
	t["cards"] = cards
	territories[territory_id] = t

func get_territory(territory_id: String) -> Dictionary:
	return territories.get(territory_id, {})

## ========== END MAP TERRITORY OWNERSHIP ==========

func initialize_player_hand(hand_size: int = 3) -> void:
	## Randomly selects cards from the appropriate pool based on selected race
	player_hand.clear()
	
	# Choose card pool based on race
	var card_pool: Array
	match selected_race:
		"Elf":
			card_pool = ELF_CARDS.duplicate()
			print("[Hand] Using Elf card pool")
		"Infernal":
			card_pool = INFERNAL_CARDS.duplicate()
			print("[Hand] Using Infernal card pool")
		_:
			card_pool = MIXED_CARD_POOL.duplicate()
			print("[Hand] Using mixed card pool for ", selected_race)
	
	card_pool.shuffle()
	for i in range(mini(hand_size, card_pool.size())):
		player_hand.append(card_pool[i].duplicate())
	print("[Hand] Initialized player hand with ", player_hand.size(), " cards")

func reset_player_hand() -> void:
	## Clears the player's hand
	player_hand.clear()

## Remove cards described by a placed-slots dictionary from the player's collection.
## placed_slots: slot_index -> { "path": String, "frame": int }
func remove_placed_cards_from_collection_for_slots(placed_slots: Dictionary) -> void:
	var removed := 0
	for slot_idx in placed_slots:
		var card_data: Dictionary = placed_slots[slot_idx]
		var path: String = card_data.get("path", "")
		var frame: int = int(card_data.get("frame", 0))
		for i in range(player_card_collection.size() - 1, -1, -1):
			var c: Dictionary = player_card_collection[i]
			if c.get("path", "") == path and int(c.get("frame", 0)) == frame:
				player_card_collection.remove_at(i)
				removed += 1
				break
	if removed > 0:
		print("[Cards] Removed ", removed, " placed cards from collection (battle lost)")


## Backwards-compatible helper using legacy battle_placed_cards.
func remove_placed_cards_from_collection() -> void:
	remove_placed_cards_from_collection_for_slots(battle_placed_cards)

## Initialize player's card collection with 4 random cards at game start
func initialize_player_card_collection() -> void:
	player_card_collection.clear()
	var card_pool: Array
	match selected_race:
		"Elf":
			card_pool = ELF_CARDS.duplicate()
		"Infernal":
			card_pool = INFERNAL_CARDS.duplicate()
		"Fairy":
			card_pool = FAIRY_CARDS.duplicate()
		"Orc":
			card_pool = ORC_CARDS.duplicate()
		_:
			card_pool = MIXED_CARD_POOL.duplicate()
	card_pool.shuffle()
	for i in range(mini(4, card_pool.size())):
		var c: Dictionary = card_pool[i].duplicate()
		player_card_collection.append({"path": c.get("sprite_frames", ""), "frame": int(c.get("frame_index", 0))})
	print("[Cards] Initialized collection with ", player_card_collection.size(), " cards")

## Add a random card when player wins a minigame
func add_card_from_minigame_win() -> void:
	var card_pool: Array
	card_pool = MIXED_CARD_POOL.duplicate()
	if card_pool.is_empty():
		return
	var c: Dictionary = card_pool[randi() % card_pool.size()].duplicate()
	player_card_collection.append({"path": c.get("sprite_frames", ""), "frame": int(c.get("frame_index", 0))})
	print("[Cards] Added card from minigame win. Collection size: ", player_card_collection.size())
## ========== END PLAYER HAND SYSTEM ==========

func reset_lives() -> void:
	current_lives = MAX_LIVES

func lose_life() -> bool:
	## Returns true if game over (no lives left)
	current_lives -= 1
	return current_lives <= 0

func get_lives() -> int:
	return current_lives

var main_music: AudioStreamPlayer
var battle_music: AudioStreamPlayer
var ui_sfx: AudioStreamPlayer
var blip_select_stream: AudioStream

func _ready() -> void:
	# Ensure audio buses exist
	_setup_audio_buses()
	
	# Create and start main music immediately on game launch
	main_music = AudioStreamPlayer.new()
	main_music.name = "MainMusic"
	main_music.bus = "Music"  # Assign to Music bus
	add_child(main_music)
	
	# Load the music stream
	var stream: AudioStreamMP3 = load("res://music/main_music.mp3")
	if stream == null and FileAccess.file_exists("res://music/main_music.mp3"):
		stream = AudioStreamMP3.new()
		stream.data = FileAccess.get_file_as_bytes("res://music/main_music.mp3")
	
	if stream:
		stream.loop = true
		main_music.stream = stream
		main_music.play()
		print("Main music started from App autoload")
	
	# Create battle music player
	battle_music = AudioStreamPlayer.new()
	battle_music.name = "BattleMusic"
	battle_music.bus = "Music"  # Assign to Music bus
	add_child(battle_music)
	
	# Load the battle music stream
	var battle_stream: AudioStreamMP3 = load("res://music/battle_music.mp3")
	if battle_stream == null and FileAccess.file_exists("res://music/battle_music.mp3"):
		battle_stream = AudioStreamMP3.new()
		battle_stream.data = FileAccess.get_file_as_bytes("res://music/battle_music.mp3")
	
	if battle_stream:
		battle_stream.loop = true
		battle_music.stream = battle_stream
		print("Battle music loaded in App autoload")

	# UI SFX (button blips, etc.)
	ui_sfx = AudioStreamPlayer.new()
	ui_sfx.name = "UISfx"
	ui_sfx.bus = "UI"  # Assign to UI bus
	add_child(ui_sfx)
	blip_select_stream = load("res://sounds/blipSelect.wav")
	if blip_select_stream:
		ui_sfx.stream = blip_select_stream

	# Auto-hook any buttons added to the scene tree (covers all screens/scenes).
	if not get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.connect(_on_node_added)
	call_deferred("_hook_buttons_on_current_scene")

func go(path: String) -> void:
	get_tree().change_scene_to_file(path)
	call_deferred("_hook_buttons_on_current_scene")

@warning_ignore("shadowed_variable_base_class")
func set_player_name(name: String) -> void:
	player_name = name.strip_edges()

func set_next_scene(path: String) -> void:
	next_scene = path

func set_selected_race(race: String) -> void:
	selected_race = race.strip_edges()

func setup_single_player_game() -> void:
	is_multiplayer = false
	game_players.clear()
	turn_order.clear()
	reset_lives()
	reset_phase_state()
	reset_territories()
	initialize_player_hand()
	initialize_player_card_collection()
	# Use path built from parts so the autoload name is not parsed as an identifier
	var tcs_path: String = "/root/" + "Territory" + "Claim" + "State"
	var tcs: Node = get_node_or_null(tcs_path)
	if tcs and tcs.has_method("clear_all"):
		tcs.clear_all()
	
	# Add the local player
	var local_player := {
		"id": 1,
		"name": player_name if not player_name.is_empty() else "Player",
		"race": selected_race,
		"roll": 0,
		"is_local": true
	}
	game_players.append(local_player)
	
	# Generate 3 AI opponents with the remaining races
	var all_races := ["Elf", "Orc", "Fairy", "Infernal"]
	var available_races: Array = []
	for r in all_races:
		if r != selected_race:
			available_races.append(r)
	available_races.shuffle()
	
	var ai_names := ["Thorne", "Mira", "Grak", "Lyra", "Korrin", "Sable", "Dusk", "Ember"]
	ai_names.shuffle()
	
	for i in range(3):
		var ai_player := {
			"id": i + 100,  # AI IDs start at 100
			"name": ai_names[i],
			"race": available_races[i],
			"roll": 0,
			"is_local": false
		}
		game_players.append(ai_player)

func setup_multiplayer_game() -> void:
	is_multiplayer = true
	game_players.clear()
	turn_order.clear()
	reset_lives()
	reset_phase_state()
	reset_territories()
	initialize_player_hand()
	initialize_player_card_collection()
	
	# Build player list from Net.player_names and Net.player_races
	var my_id := multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
	
	for pid in Net.player_races.keys():
		var p := {
			"id": int(pid),
			"name": String(Net.player_names.get(pid, "Player")),
			"race": String(Net.player_races[pid]),
			"roll": 0,
			"is_local": int(pid) == my_id
		}
		game_players.append(p)

func get_race_texture_path(race: String) -> String:
	match race:
		"Elf":
			return "res://pictures/elf_girl_1/eg1_south.png"
		"Orc":
			return "res://pictures/orc_boy_1/ob1_south.png"
		"Fairy":
			return "res://pictures/fairy_girl_1/fg1_south.png"
		"Infernal":
			return "res://pictures/infernal_boy_1/ib1_south.png"
	return ""

func get_race_color(race: String) -> Color:
	match race:
		"Elf":
			return Color(1, 0.9, 0.2, 1)  # Yellow
		"Orc":
			return Color(0.2, 0.8, 0.2, 1)  # Green
		"Fairy":
			return Color(0.7, 0.3, 0.9, 1)  # Purple
		"Infernal":
			return Color(0.9, 0.2, 0.2, 1)  # Red
	return Color.WHITE

func stop_main_music() -> void:
	if main_music and main_music.playing:
		main_music.stop()

func play_main_music() -> void:
	if main_music and not main_music.playing:
		main_music.play()

func stop_battle_music() -> void:
	if battle_music and battle_music.playing:
		battle_music.stop()

func play_battle_music() -> void:
	if battle_music and not battle_music.playing:
		battle_music.play()

func switch_to_battle_music() -> void:
	stop_main_music()
	play_battle_music()

func switch_to_main_music() -> void:
	stop_battle_music()
	play_main_music()

func play_blip_select() -> void:
	if not ui_sfx or not ui_sfx.stream:
		return
	# Restart so rapid presses still feel responsive.
	if ui_sfx.playing:
		ui_sfx.stop()
	ui_sfx.play()

func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		_connect_button_sfx(node)

func _hook_buttons_on_current_scene() -> void:
	var scene := get_tree().current_scene
	if scene:
		_hook_buttons_recursive(scene)

func _hook_buttons_recursive(root: Node) -> void:
	if root is BaseButton:
		_connect_button_sfx(root)
	for child in root.get_children():
		_hook_buttons_recursive(child)

func _connect_button_sfx(button: BaseButton) -> void:
	var cb := Callable(self, "play_blip_select")
	if not button.pressed.is_connected(cb):
		button.pressed.connect(cb)

func _setup_audio_buses() -> void:
	# Check if Music bus exists, if not create it
	var music_bus_idx = AudioServer.get_bus_index("Music")
	if music_bus_idx == -1:
		AudioServer.add_bus()
		var new_bus_idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(new_bus_idx, "Music")
		AudioServer.set_bus_send(new_bus_idx, "Master")
		print("Created Music audio bus")
	
	# Check if SFX bus exists, if not create it
	var sfx_bus_idx = AudioServer.get_bus_index("SFX")
	if sfx_bus_idx == -1:
		AudioServer.add_bus()
		var new_bus_idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(new_bus_idx, "SFX")
		AudioServer.set_bus_send(new_bus_idx, "Master")
		print("Created SFX audio bus")
	
	# Check if UI bus exists, if not create it
	var ui_bus_idx = AudioServer.get_bus_index("UI")
	if ui_bus_idx == -1:
		AudioServer.add_bus()
		var new_bus_idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(new_bus_idx, "UI")
		AudioServer.set_bus_send(new_bus_idx, "Master")
		print("Created UI audio bus")

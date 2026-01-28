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
	
	# Check if we should auto-transition to battle phase
	if minigames_completed_this_phase >= MAX_MINIGAMES_PER_PHASE:
		print("[Phase] Max minigames reached, transitioning to battle phase")
		enter_battle_phase()

func on_battle_completed() -> void:
	## Called when battle ends (win, lose, or tie)
	print("[Phase] Battle completed, returning to resource phase")
	enter_resource_phase()

func skip_to_battle_phase() -> void:
	## Called when player chooses to skip remaining minigames
	print("[Phase] Player skipping to battle phase")
	enter_battle_phase()

func can_play_minigame() -> bool:
	## Returns true if player can still play minigames this phase
	return current_game_phase == GamePhase.RESOURCE_PHASE and minigames_completed_this_phase < MAX_MINIGAMES_PER_PHASE

func reset_phase_state() -> void:
	## Reset phase state for a new game
	current_game_phase = GamePhase.RESOURCE_PHASE
	minigames_completed_this_phase = 0
	show_phase_transition = false
	phase_transition_text = ""
## ========== END PHASE SYSTEM ==========

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

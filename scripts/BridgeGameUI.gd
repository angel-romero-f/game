extends CanvasLayer

@onready var game_over_panel: Panel = $UI/GameOverPanel
@onready var game_over_label: Label = $UI/GameOverPanel/GameOverLabel
@onready var win_panel: Panel = $UI/WinPanel
@onready var win_label: Label = $UI/WinPanel/WinLabel
@onready var lose_music: AudioStreamPlayer = get_node_or_null("../LoseMusic")
@onready var settings_button: Button = $UI/SettingsButton
@onready var settings_panel: Panel = $UI/SettingsPanel

var player: Node2D = null
var is_paused: bool = false

func _ready():
	game_over_panel.visible = false
	win_panel.visible = false
	settings_panel.visible = false
	
	# Assign lose music to Music bus
	if lose_music:
		lose_music.bus = "Music"
	
	# Fallback: load stream if the import is missing at runtime.
	if lose_music and lose_music.stream == null:
		if FileAccess.file_exists("res://music/lose_music.mp3"):
			var stream := AudioStreamMP3.new()
			stream.data = FileAccess.get_file_as_bytes("res://music/lose_music.mp3")
			lose_music.stream = stream
	
	if lose_music and not lose_music.finished.is_connected(_on_lose_music_finished):
		lose_music.finished.connect(_on_lose_music_finished)
	
	# Connect settings button
	if settings_button:
		settings_button.pressed.connect(_on_settings_pressed)
	
	# Connect settings panel buttons
	var resume_button = get_node_or_null("UI/SettingsPanel/SettingsContainer/ButtonContainer/ResumeButton")
	var main_menu_button = get_node_or_null("UI/SettingsPanel/SettingsContainer/ButtonContainer/MainMenuButton")
	
	if resume_button:
		resume_button.pressed.connect(_on_resume_pressed)
	if main_menu_button:
		main_menu_button.pressed.connect(_on_main_menu_pressed)
	
	# Connect volume sliders
	_setup_volume_sliders()
	
	# Wait a frame for scene to be ready
	await get_tree().process_frame
	
	# Find player and connect signals
	find_player()

func find_player():
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player = players[0]
		if player.has_signal("player_died"):
			player.player_died.connect(_on_player_died)
		if player.has_signal("player_won"):
			player.player_won.connect(_on_player_won)

func _on_player_died():
	var is_final_death := App.lose_life()
	show_game_over(is_final_death)

func _on_player_won():
	show_win()

func show_game_over(is_final: bool):
	game_over_panel.visible = true
	
	if is_final:
		# Final death - show game over and play lose music
		if game_over_label:
			game_over_label.text = "Game Over!\nYou've used all your chances!\nPress R to return to map"
		if lose_music:
			App.stop_main_music()
			lose_music.stop()
			lose_music.play()
	else:
		# Not final - show remaining lives
		var lives_left := App.get_lives()
		if game_over_label:
			game_over_label.text = "You got hit!\n%d chance%s remaining\nPress R to try again" % [lives_left, "s" if lives_left != 1 else ""]

func _on_lose_music_finished() -> void:
	App.play_main_music()

func show_win():
	win_panel.visible = true
	if win_label:
		win_label.text = "You Made It!\nYou crossed the bridge!\nPress R to return to map"

func _on_settings_pressed():
	toggle_pause()

func toggle_pause():
	is_paused = !is_paused
	settings_panel.visible = is_paused
	get_tree().paused = is_paused
	
	if settings_button:
		settings_button.visible = !is_paused

func _on_resume_pressed():
	toggle_pause()

func _on_main_menu_pressed():
	get_tree().paused = false
	App.go("res://scenes/ui/MainMenu.tscn")

func _setup_volume_sliders():
	# Get references to sliders
	var master_slider = get_node_or_null("UI/SettingsPanel/SettingsContainer/MasterVolume/Slider")
	var music_slider = get_node_or_null("UI/SettingsPanel/SettingsContainer/MusicVolume/Slider")
	var sfx_slider = get_node_or_null("UI/SettingsPanel/SettingsContainer/SFXVolume/Slider")
	var ui_slider = get_node_or_null("UI/SettingsPanel/SettingsContainer/UIVolume/Slider")
	
	# Set initial values and connect signals
	if master_slider:
		master_slider.value = _db_to_linear(AudioServer.get_bus_volume_db(0))
		master_slider.value_changed.connect(_on_master_volume_changed)
	
	if music_slider:
		var music_bus_idx = AudioServer.get_bus_index("Music")
		if music_bus_idx >= 0:
			music_slider.value = _db_to_linear(AudioServer.get_bus_volume_db(music_bus_idx))
		music_slider.value_changed.connect(_on_music_volume_changed)
	
	if sfx_slider:
		var sfx_bus_idx = AudioServer.get_bus_index("SFX")
		if sfx_bus_idx >= 0:
			sfx_slider.value = _db_to_linear(AudioServer.get_bus_volume_db(sfx_bus_idx))
		sfx_slider.value_changed.connect(_on_sfx_volume_changed)
	
	if ui_slider:
		var ui_bus_idx = AudioServer.get_bus_index("UI")
		if ui_bus_idx >= 0:
			ui_slider.value = _db_to_linear(AudioServer.get_bus_volume_db(ui_bus_idx))
		ui_slider.value_changed.connect(_on_ui_volume_changed)

func _on_master_volume_changed(value: float) -> void:
	AudioServer.set_bus_volume_db(0, _linear_to_db(value))

func _on_music_volume_changed(value: float) -> void:
	var music_bus_idx = AudioServer.get_bus_index("Music")
	if music_bus_idx >= 0:
		AudioServer.set_bus_volume_db(music_bus_idx, _linear_to_db(value))

func _on_sfx_volume_changed(value: float) -> void:
	var sfx_bus_idx = AudioServer.get_bus_index("SFX")
	if sfx_bus_idx >= 0:
		AudioServer.set_bus_volume_db(sfx_bus_idx, _linear_to_db(value))

func _on_ui_volume_changed(value: float) -> void:
	var ui_bus_idx = AudioServer.get_bus_index("UI")
	if ui_bus_idx >= 0:
		AudioServer.set_bus_volume_db(ui_bus_idx, _linear_to_db(value))

# Helper functions to convert between linear (0-1) and decibels
func _linear_to_db(value: float) -> float:
	if value <= 0:
		return -80  # Minimum volume in dB
	return 20 * log(value) / log(10)

func _db_to_linear(db: float) -> float:
	if db <= -80:
		return 0
	return pow(10, db / 20)

extends Control

var master_slider: HSlider
var music_slider: HSlider
var sfx_slider: HSlider
var ui_slider: HSlider
var save_button: Button
var how_to_play_button: Button
var quit_button: Button
var back_button: Button

func _ready() -> void:
	# Get references to UI elements
	master_slider = get_node_or_null("Card/Margin/VBoxContainer/MasterVolume/Slider")
	music_slider = get_node_or_null("Card/Margin/VBoxContainer/MusicVolume/Slider")
	sfx_slider = get_node_or_null("Card/Margin/VBoxContainer/SFXVolume/Slider")
	ui_slider = get_node_or_null("Card/Margin/VBoxContainer/UIVolume/Slider")
	save_button = get_node_or_null("Card/Margin/VBoxContainer/Buttons/SaveButton")
	how_to_play_button = get_node_or_null("Card/Margin/VBoxContainer/Buttons/HowToPlayButton")
	quit_button = get_node_or_null("Card/Margin/VBoxContainer/Buttons/QuitButton")
	back_button = get_node_or_null("Card/Margin/VBoxContainer/Buttons/BackButton")
	
	# Connect slider signals
	if master_slider:
		master_slider.value_changed.connect(_on_master_volume_changed)
		# Set initial value from current bus volume
		master_slider.value = _db_to_linear(AudioServer.get_bus_volume_db(0))
	
	if music_slider:
		music_slider.value_changed.connect(_on_music_volume_changed)
		var music_bus_idx = AudioServer.get_bus_index("Music")
		if music_bus_idx >= 0:
			music_slider.value = _db_to_linear(AudioServer.get_bus_volume_db(music_bus_idx))
	
	if sfx_slider:
		sfx_slider.value_changed.connect(_on_sfx_volume_changed)
		var sfx_bus_idx = AudioServer.get_bus_index("SFX")
		if sfx_bus_idx >= 0:
			sfx_slider.value = _db_to_linear(AudioServer.get_bus_volume_db(sfx_bus_idx))
	
	if ui_slider:
		ui_slider.value_changed.connect(_on_ui_volume_changed)
		var ui_bus_idx = AudioServer.get_bus_index("UI")
		if ui_bus_idx >= 0:
			ui_slider.value = _db_to_linear(AudioServer.get_bus_volume_db(ui_bus_idx))
	
	# Connect button signals
	if save_button:
		save_button.pressed.connect(_on_save_pressed)
	if how_to_play_button:
		how_to_play_button.pressed.connect(_on_how_to_play_pressed)
	if quit_button:
		quit_button.pressed.connect(_on_quit_pressed)
	if back_button:
		back_button.pressed.connect(_on_back_pressed)

func _on_master_volume_changed(value: float) -> void:
	# Convert linear (0-1) to decibels
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

func _on_save_pressed() -> void:
	# Placeholder for save functionality
	print("Save button pressed (not implemented yet)")

func _on_how_to_play_pressed() -> void:
	# Placeholder for how to play functionality
	print("How to Play button pressed (not implemented yet)")

func _on_quit_pressed() -> void:
	get_tree().quit()

func _on_back_pressed() -> void:
	App.go("res://scenes/ui/MainMenu.tscn")

# Helper functions to convert between linear (0-1) and decibels
func _linear_to_db(value: float) -> float:
	if value <= 0:
		return -80  # Minimum volume in dB
	return 20 * log(value) / log(10)

func _db_to_linear(db: float) -> float:
	if db <= -80:
		return 0
	return pow(10, db / 20)

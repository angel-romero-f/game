extends Panel

## SettingsPanelUI — Script-on-node attached to $SettingsPanel.
## Handles volume sliders and emits resume/main_menu signals.

signal resume_pressed
signal main_menu_pressed

var _master_slider: HSlider
var _music_slider: HSlider
var _sfx_slider: HSlider
var _ui_slider: HSlider

func _ready() -> void:
	var resume_button = get_node_or_null("SettingsContainer/ButtonContainer/ResumeButton")
	var main_menu_button = get_node_or_null("SettingsContainer/ButtonContainer/MainMenuButton")
	if resume_button:
		resume_button.pressed.connect(func(): resume_pressed.emit())
	if main_menu_button:
		main_menu_button.pressed.connect(func(): main_menu_pressed.emit())
	_setup_volume_sliders()

func _setup_volume_sliders() -> void:
	_master_slider = get_node_or_null("SettingsContainer/MasterVolume/Slider") as HSlider
	_music_slider = get_node_or_null("SettingsContainer/MusicVolume/Slider") as HSlider
	_sfx_slider = get_node_or_null("SettingsContainer/SFXVolume/Slider") as HSlider
	_ui_slider = get_node_or_null("SettingsContainer/UIVolume/Slider") as HSlider

	if _master_slider:
		_master_slider.value = _db_to_linear(AudioServer.get_bus_volume_db(0))
		_master_slider.value_changed.connect(_on_master_volume_changed)
	if _music_slider:
		var idx = AudioServer.get_bus_index("Music")
		if idx >= 0:
			_music_slider.value = _db_to_linear(AudioServer.get_bus_volume_db(idx))
		_music_slider.value_changed.connect(_on_music_volume_changed)
	if _sfx_slider:
		var idx = AudioServer.get_bus_index("SFX")
		if idx >= 0:
			_sfx_slider.value = _db_to_linear(AudioServer.get_bus_volume_db(idx))
		_sfx_slider.value_changed.connect(_on_sfx_volume_changed)
	if _ui_slider:
		var idx = AudioServer.get_bus_index("UI")
		if idx >= 0:
			_ui_slider.value = _db_to_linear(AudioServer.get_bus_volume_db(idx))
		_ui_slider.value_changed.connect(_on_ui_volume_changed)

func _on_master_volume_changed(value: float) -> void:
	AudioServer.set_bus_volume_db(0, _linear_to_db(value))

func _on_music_volume_changed(value: float) -> void:
	var idx = AudioServer.get_bus_index("Music")
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, _linear_to_db(value))

func _on_sfx_volume_changed(value: float) -> void:
	var idx = AudioServer.get_bus_index("SFX")
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, _linear_to_db(value))

func _on_ui_volume_changed(value: float) -> void:
	var idx = AudioServer.get_bus_index("UI")
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, _linear_to_db(value))

func _linear_to_db(value: float) -> float:
	if value <= 0:
		return -80
	return 20 * log(value) / log(10)

func _db_to_linear(db: float) -> float:
	if db <= -80:
		return 0
	return pow(10, db / 20)

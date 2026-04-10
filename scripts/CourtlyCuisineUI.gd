extends CanvasLayer

## Courtly Cuisine UI — Timer, reward preview, game-over / win panels, settings.
## Mirrors BridgeGameUI / IceFishingUI structure for consistency across minigames.

@onready var game_over_panel: Panel = $UI/GameOverPanel
@onready var game_over_label: Label = $UI/GameOverPanel/GameOverLabel
@onready var win_panel: Panel = $UI/WinPanel
@onready var win_label: Label = $UI/WinPanel/WinLabel
@onready var settings_button: Button = $UI/SettingsButton
@onready var settings_panel: Panel = $UI/SettingsPanel

var lose_music: AudioStreamPlayer = null
var is_paused: bool = false

var _timer_label: Label = null
var _reward_panel: Control = null
var _timeout_label: Label = null
var _pixel_font: Font = null
var _big_title_label: Label = null
var _lives_label: Label = null


func _ready():
	game_over_panel.visible = false
	win_panel.visible = false
	settings_panel.visible = false

	_pixel_font = load("res://fonts/m5x7.ttf") as Font

	# ── Timer label (top-right corner) ──
	_timer_label = Label.new()
	_timer_label.name = "MinigameTimerLabel"
	if _pixel_font:
		_timer_label.add_theme_font_override("font", _pixel_font)
	_timer_label.add_theme_font_size_override("font_size", 36)
	_timer_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.2, 1.0))
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_timer_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_timer_label.offset_left = -180
	_timer_label.offset_top = 58
	_timer_label.offset_right = -8
	_timer_label.offset_bottom = 94
	_timer_label.text = "Time: 30"
	$UI.add_child(_timer_label)

	# ── Reward preview (top-left) ──
	_build_reward_preview()

	# ── Timeout label (hidden until needed) ──
	_timeout_label = Label.new()
	_timeout_label.name = "TimeoutLabel"
	if _pixel_font:
		_timeout_label.add_theme_font_override("font", _pixel_font)
	_timeout_label.add_theme_font_size_override("font_size", 32)
	_timeout_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.2, 1.0))
	_timeout_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timeout_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_timeout_label.set_anchors_preset(Control.PRESET_CENTER)
	_timeout_label.offset_left = -220
	_timeout_label.offset_right = 220
	_timeout_label.offset_top = -30
	_timeout_label.offset_bottom = 30
	_timeout_label.text = "Time's Up!"
	_timeout_label.visible = false
	$UI.add_child(_timeout_label)

	# ── Big title label (centered, used for win/lose splash text) ──
	_big_title_label = Label.new()
	_big_title_label.name = "BigTitleLabel"
	if _pixel_font:
		_big_title_label.add_theme_font_override("font", _pixel_font)
	_big_title_label.add_theme_font_size_override("font_size", 72)
	_big_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_big_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_big_title_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1.0))
	_big_title_label.add_theme_constant_override("outline_size", 8)
	_big_title_label.set_anchors_preset(Control.PRESET_CENTER)
	_big_title_label.offset_left = -500
	_big_title_label.offset_right = 500
	_big_title_label.offset_top = -100
	_big_title_label.offset_bottom = 100
	_big_title_label.visible = false
	$UI.add_child(_big_title_label)

	# ── Lives display (bottom-left) ──
	_lives_label = Label.new()
	_lives_label.name = "LivesLabel"
	if _pixel_font:
		_lives_label.add_theme_font_override("font", _pixel_font)
	_lives_label.add_theme_font_size_override("font_size", 24)
	_lives_label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.3, 1.0))
	_lives_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1.0))
	_lives_label.add_theme_constant_override("outline_size", 3)
	_lives_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_lives_label.offset_left = 12
	_lives_label.offset_top = -44
	_lives_label.offset_right = 200
	_lives_label.offset_bottom = -8
	_update_lives_display()
	$UI.add_child(_lives_label)

	# ── Lose music ──
	lose_music = get_parent().get_node_or_null("LoseMusic")
	if lose_music:
		lose_music.bus = "Music"
	if lose_music and lose_music.stream == null:
		if FileAccess.file_exists("res://music/lose_music.mp3"):
			var stream := AudioStreamMP3.new()
			stream.data = FileAccess.get_file_as_bytes("res://music/lose_music.mp3")
			lose_music.stream = stream
	if lose_music and not lose_music.finished.is_connected(_on_lose_music_finished):
		lose_music.finished.connect(_on_lose_music_finished)

	# ── Settings wiring ──
	if settings_button:
		settings_button.pressed.connect(_on_settings_pressed)
	var resume_button = get_node_or_null("UI/SettingsPanel/SettingsContainer/ButtonContainer/ResumeButton")
	var main_menu_button = get_node_or_null("UI/SettingsPanel/SettingsContainer/ButtonContainer/MainMenuButton")
	if resume_button:
		resume_button.pressed.connect(_on_resume_pressed)
	if main_menu_button:
		main_menu_button.pressed.connect(_on_main_menu_pressed)
	_setup_volume_sliders()


# ── Reward preview (top-left, same as other minigames) ──────

func _build_reward_preview() -> void:
	var reward := App.pending_minigame_reward
	if reward.is_empty():
		return
	var path: String = reward.get("path", "")
	var frame: int = int(reward.get("frame", 0))
	if path == "" or not ResourceLoader.exists(path):
		return
	var sf := load(path) as SpriteFrames
	if not sf or not sf.has_animation("default"):
		return
	if frame < 0 or frame >= sf.get_frame_count("default"):
		return
	var has_bonus := App.region_bonus_active and not App.pending_bonus_reward.is_empty()
	var panel_right := 190 if has_bonus else 100
	_reward_panel = PanelContainer.new()
	_reward_panel.name = "RewardPreviewPanel"
	_reward_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_reward_panel.offset_left = 8
	_reward_panel.offset_top = 8
	_reward_panel.offset_right = panel_right
	_reward_panel.offset_bottom = 160
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.15, 0.82)
	style.set_border_width_all(2)
	style.border_color = Color(1.0, 0.85, 0.3, 0.9)
	style.set_corner_radius_all(4)
	_reward_panel.add_theme_stylebox_override("panel", style)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	_reward_panel.add_child(vbox)
	var lbl := Label.new()
	lbl.text = "Region Bonus! Win 2:" if has_bonus else "If you win:"
	if _pixel_font:
		lbl.add_theme_font_override("font", _pixel_font)
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3, 1.0))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(lbl)
	var cards_container := HBoxContainer.new()
	cards_container.add_theme_constant_override("separation", 4)
	cards_container.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(cards_container)
	var tex_rect := TextureRect.new()
	tex_rect.texture = sf.get_frame_texture("default", frame)
	tex_rect.custom_minimum_size = Vector2(80, 112)
	tex_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	cards_container.add_child(tex_rect)
	if has_bonus:
		var bonus := App.pending_bonus_reward
		var b_path: String = bonus.get("path", "")
		var b_frame: int = int(bonus.get("frame", 0))
		if b_path != "" and ResourceLoader.exists(b_path):
			var b_sf := load(b_path) as SpriteFrames
			if b_sf and b_sf.has_animation("default") and b_frame >= 0 and b_frame < b_sf.get_frame_count("default"):
				var b_tex := TextureRect.new()
				b_tex.texture = b_sf.get_frame_texture("default", b_frame)
				b_tex.custom_minimum_size = Vector2(80, 112)
				b_tex.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
				b_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				cards_container.add_child(b_tex)
	$UI.add_child(_reward_panel)


# ── Timer display ────────────────────────────────────────────

func update_timer_display(time_left: float) -> void:
	if _timer_label:
		var secs := int(ceil(time_left))
		var col := Color(1.0, 0.9, 0.2, 1.0)
		if time_left <= 10.0:
			col = Color(1.0, 0.3, 0.2, 1.0)
		_timer_label.add_theme_color_override("font_color", col)
		_timer_label.text = "Time: %d" % secs


func _update_lives_display():
	if _lives_label:
		var hearts := ""
		for i in range(App.get_lives()):
			hearts += "♥ "
		_lives_label.text = hearts.strip_edges()


# ── Game over (failed placement) ─────────────────────────────

func show_game_over(is_final: bool):
	game_over_panel.visible = true
	_update_lives_display()

	if is_final:
		App.stop_main_music()
		if lose_music:
			lose_music.play()
		if _big_title_label:
			_big_title_label.text = "Kitchen Catastrophe!"
			_big_title_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2))
			_big_title_label.visible = true
		if game_over_panel:
			game_over_panel.visible = false
		_auto_return_after_timeout()
	else:
		var lives_left := App.get_lives()
		if game_over_label:
			game_over_label.text = "Clumsy plating!\n%d chance%s remaining\nPress R to try again" % [lives_left, "s" if lives_left != 1 else ""]


# ── Win ──────────────────────────────────────────────────────

func show_win():
	win_panel.visible = true
	if _timer_label:
		_timer_label.visible = false
	if _reward_panel:
		_reward_panel.visible = false
	if _lives_label:
		_lives_label.visible = false
	if _big_title_label:
		_big_title_label.text = "S'more Success! Sweet Victory!"
		_big_title_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.2))
		_big_title_label.visible = true
		_big_title_label.offset_top = -260
		_big_title_label.offset_bottom = -160
	if win_panel:
		win_panel.visible = false
	_build_win_card_display()
	_auto_return_after_timeout(3.5)


# ── Timeout ──────────────────────────────────────────────────

func show_timeout() -> void:
	if _timer_label:
		_timer_label.text = "Time: 0"
		_timer_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.2, 1.0))
	if _reward_panel:
		_reward_panel.visible = false
	if _timeout_label:
		_timeout_label.visible = true
	_auto_return_after_timeout()


func _auto_return_after_timeout(delay: float = 1.8) -> void:
	await get_tree().create_timer(delay).timeout
	var game_node := get_parent()
	if game_node and game_node.has_method("handle_continue"):
		game_node.call("handle_continue")


func _on_lose_music_finished() -> void:
	App.play_main_music()


# ── Win card display popup ───────────────────────────────────

func _build_win_card_display() -> void:
	var reward := App.pending_minigame_reward
	if reward.is_empty():
		return
	var path: String = reward.get("path", "")
	var frame: int = int(reward.get("frame", 0))
	if path == "" or not ResourceLoader.exists(path):
		return
	var sf := load(path) as SpriteFrames
	if not sf or not sf.has_animation("default"):
		return
	if frame < 0 or frame >= sf.get_frame_count("default"):
		return

	var card_name := _card_name_from_path(path)

	var panel := PanelContainer.new()
	panel.name = "WinCardPopup"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -130
	panel.offset_right = 130
	panel.offset_top = -140
	panel.offset_bottom = 140
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.15, 0.85)
	style.set_border_width_all(3)
	style.border_color = Color(1.0, 0.85, 0.3, 0.9)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vbox)

	var tex := TextureRect.new()
	tex.texture = sf.get_frame_texture("default", frame)
	tex.custom_minimum_size = Vector2(140, 196)
	tex.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(tex)

	var lbl := Label.new()
	lbl.text = "You won: %s!" % card_name
	if _pixel_font:
		lbl.add_theme_font_override("font", _pixel_font)
	lbl.add_theme_font_size_override("font_size", 24)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3, 1.0))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1.0))
	lbl.add_theme_constant_override("outline_size", 4)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(lbl)

	$UI.add_child(panel)


func _card_name_from_path(path: String) -> String:
	var file_name := path.get_file().get_basename()
	file_name = file_name.replace("_cards", "").replace("_card", "")
	var parts := file_name.split("_")
	var name_parts: PackedStringArray = []
	for p in parts:
		if p.length() > 0:
			name_parts.append(p.capitalize())
	if name_parts.is_empty():
		return "a New Card"
	return " ".join(name_parts) + " Card"


# ── Settings / pause ─────────────────────────────────────────

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


# ── Volume sliders (identical to other minigame UIs) ─────────

func _setup_volume_sliders():
	var master_slider = get_node_or_null("UI/SettingsPanel/SettingsContainer/MasterVolume/Slider")
	var music_slider = get_node_or_null("UI/SettingsPanel/SettingsContainer/MusicVolume/Slider")
	var sfx_slider = get_node_or_null("UI/SettingsPanel/SettingsContainer/SFXVolume/Slider")
	var ui_slider = get_node_or_null("UI/SettingsPanel/SettingsContainer/UIVolume/Slider")

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

func _linear_to_db(value: float) -> float:
	if value <= 0:
		return -80
	return 20 * log(value) / log(10)

func _db_to_linear(db: float) -> float:
	if db <= -80:
		return 0
	return pow(10, db / 20)

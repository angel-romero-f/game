extends Node

## TutorialSequence — Interactive step-based tutorial driven by the host,
## RPC-synced to all clients.  Receives gnome sprite + dialogue refs from
## GnomeTutorialUI and territory/hand refs from GameIntro.

signal tutorial_completed

const UI_FONT := preload("res://fonts/m5x7.ttf")
const GNOME_VOICE_STREAMS := [
	preload("res://dialog/gnome2.mp3"),
	preload("res://dialog/gnome3.mp3"),
	preload("res://dialog/gnome4.mp3"),
	preload("res://dialog/gnome5.mp3"),
	preload("res://dialog/gnome6.mp3"),
	preload("res://dialog/gnome7.mp3"),
	preload("res://dialog/gnome8.mp3"),
	preload("res://dialog/gnome9.mp3"),
	preload("res://dialog/gnome10.mp3"),
]
const GNOME_VOICE_BUS := "SFX"
const GNOME_VOICE_VOLUME_DB := -7.0
const GNOME_VOICE_PITCH_SCALE := 1.03
const TYPEWRITER_CHARS_PER_SEC := 35.0
const GNOME_DISPLAY_SIZE := 256.0

# Hardcoded territory IDs at the TOP of the map to avoid overlapping dialogue
const CLAIM_TERRITORY_ID := 4
const ATTACK_TERRITORY_ID := 9

# Mock card data (deterministic — never touches App.player_card_collection)
# Player has stronger cards (higher frame = higher power) to win convincingly
const MOCK_PLAYER_CARDS: Array = [
	{"path": "res://assets/elf_fire_cards.pxo", "frame": 3},   # power 4
	{"path": "res://assets/elf_air_cards.pxo", "frame": 1},    # power 2
	{"path": "res://assets/elf_water_cards.pxo", "frame": 3},  # power 4
]

const MOCK_ENEMY_CARDS: Array = [
	{"path": "res://assets/orc_fire_cards.pxo", "frame": 1},   # power 2
	{"path": "res://assets/orc_air_cards.pxo", "frame": 2},    # power 3
	{"path": "res://assets/orc_water_cards.pxo", "frame": 0},  # power 1
]

# Round results: 4>2 WIN, 2<3 LOSE, 4>1 WIN => player wins 2-1
const BATTLE_RESULTS: Array = ["win", "lose", "win"]
const PLAYER_POWERS: Array = [4, 2, 4]
const ENEMY_POWERS: Array = [2, 3, 1]

enum Step {
	TERRITORY_INTRO,
	SHOW_HAND,
	CLAIM_TERRITORY,
	ATTACK_INTRO,
	MOCK_BATTLE,
	MINIGAME_INTRO,
	MINIGAME_PREVIEW,
	FAREWELL,
	DONE,
}

var _step: Step = Step.DONE

# Refs handed in from GnomeTutorialUI / GameIntro
var _gnome_rect: TextureRect
var _front_texture: Texture2D
var _walk_frames: SpriteFrames
var _walk_anim_name: String = "default"
var _anim_fps: float = 8.0
var _dialogue_panel: PanelContainer
var _dialogue_label: RichTextLabel
var _gnome_container: Control
var _voice_player: AudioStreamPlayer
var _voice_line_idx: int = 0
var _map_overlay: ColorRect
var _territory_manager: Node
var _card_icon_button: Button
var _hand_display_panel: PanelContainer
var _hand_container: HBoxContainer

# Typewriter state
var _full_text: String = ""
var _visible_chars: int = 0
var _typewriter_timer: float = 0.0
var _typewriter_done: bool = false

# Walk animation
var _frame_idx: int = 0
var _frame_timer: float = 0.0
var _is_walking: bool = false

# Next button (host-only)
var _next_button: Button
var _waiting_label: Label
var _next_container: HBoxContainer

# Territory click interception
var _awaiting_territory_click: int = -1
var _territory_click_connected: bool = false

# Card icon click interception
var _awaiting_card_icon_click: bool = false
var _card_icon_click_connected: bool = false

# Hand close interception (after hand is opened, wait for user to close it)
var _awaiting_hand_close: bool = false
var _hand_close_connected: bool = false

# Auto-advance timer
var _auto_advance_timer: float = -1.0

# Mock battle overlay
var _battle_overlay: Control
var _battle_step_timer: float = -1.0
var _battle_round: int = 0
var _battle_card_pairs: Array = []
var _battle_result_label: Label

# Minigame preview overlay
var _minigame_overlay: Control

# Pulsing glow for territory highlight
var _pulse_timer: float = 0.0
var _pulsing_indicator: Node = null

# Pulsing glow for card icon button
var _card_icon_pulse_active: bool = false
var _card_icon_original_modulate: Color = Color.WHITE


func initialize(refs: Dictionary) -> void:
	_gnome_rect = refs.get("gnome_rect")
	_front_texture = refs.get("front_texture")
	_walk_frames = refs.get("walk_frames")
	_walk_anim_name = refs.get("walk_anim_name", "default")
	_anim_fps = refs.get("anim_fps", 8.0)
	_dialogue_panel = refs.get("dialogue_panel")
	_dialogue_label = refs.get("dialogue_label")
	_gnome_container = refs.get("gnome_container")
	_map_overlay = refs.get("map_overlay")
	_territory_manager = refs.get("territory_manager")
	_card_icon_button = refs.get("card_icon_button")
	_hand_display_panel = refs.get("hand_display_panel")
	_hand_container = refs.get("hand_container")
	_voice_line_idx = 0

	if _gnome_container and is_instance_valid(_gnome_container):
		_voice_player = AudioStreamPlayer.new()
		_voice_player.name = "TutorialGnomeVoicePlayer"
		_voice_player.volume_db = GNOME_VOICE_VOLUME_DB
		_voice_player.pitch_scale = GNOME_VOICE_PITCH_SCALE
		if AudioServer.get_bus_index(GNOME_VOICE_BUS) != -1:
			_voice_player.bus = GNOME_VOICE_BUS
		_gnome_container.add_child(_voice_player)

	print("[Tutorial] initialize — gnome_rect=%s front_tex=%s walk_frames=%s" % [
		_gnome_rect != null, _front_texture != null, _walk_frames != null])
	print("[Tutorial] initialize — dialogue_panel=%s dialogue_label=%s gnome_container=%s" % [
		_dialogue_panel != null, _dialogue_label != null, _gnome_container != null])
	print("[Tutorial] initialize — territory_manager=%s card_icon=%s hand_panel=%s hand_container=%s" % [
		_territory_manager != null, _card_icon_button != null,
		_hand_display_panel != null, _hand_container != null])


func start() -> void:
	print("[Tutorial] start()")
	_build_next_button()
	_begin_step(Step.TERRITORY_INTRO)


func process_frame(delta: float) -> void:
	_process_typewriter(delta)
	_process_walk_animation(delta)
	_process_pulse(delta)
	_process_card_icon_pulse(delta)

	if _auto_advance_timer > 0.0:
		_auto_advance_timer -= delta
		if _auto_advance_timer <= 0.0:
			_auto_advance_timer = -1.0
			_on_auto_advance()

	if _battle_step_timer > 0.0:
		_battle_step_timer -= delta
		if _battle_step_timer <= 0.0:
			_battle_step_timer = -1.0
			_advance_battle_round()


# ---------- NEXT BUTTON ----------

func _build_next_button() -> void:
	print("[Tutorial] _build_next_button()")
	if not _dialogue_panel:
		push_error("[Tutorial] _dialogue_panel is null in _build_next_button")
		return
	var child0 = _dialogue_panel.get_child(0)
	if not child0 or not (child0 is VBoxContainer):
		push_error("[Tutorial] dialogue_panel child(0) is not VBoxContainer: %s" % child0)
		return

	_next_container = HBoxContainer.new()
	_next_container.name = "TutorialNextContainer"
	_next_container.visible = false
	_next_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_next_container.add_theme_constant_override("separation", 32)
	child0.add_child(_next_container)

	var btn_normal := _make_button_style(Color(0.18, 0.15, 0.25, 1.0), Color(0.65, 0.55, 0.35, 1.0))
	var btn_hover := _make_button_style(Color(0.28, 0.24, 0.38, 1.0), Color(0.85, 0.75, 0.45, 1.0))

	_next_button = Button.new()
	_next_button.text = "Next"
	_next_button.add_theme_font_override("font", UI_FONT)
	_next_button.add_theme_font_size_override("font_size", 26)
	_next_button.add_theme_color_override("font_color", Color(0.95, 0.9, 0.75))
	_next_button.add_theme_stylebox_override("normal", btn_normal)
	_next_button.add_theme_stylebox_override("hover", btn_hover)
	_next_button.pressed.connect(_on_next_pressed)
	_next_container.add_child(_next_button)

	_waiting_label = Label.new()
	_waiting_label.text = "Waiting for host..."
	_waiting_label.add_theme_font_override("font", UI_FONT)
	_waiting_label.add_theme_font_size_override("font_size", 22)
	_waiting_label.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55, 1.0))
	_waiting_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_waiting_label.visible = false
	_next_container.add_child(_waiting_label)
	print("[Tutorial] _build_next_button() done")


func _show_next_button() -> void:
	print("[Tutorial] _show_next_button() step=%s" % Step.keys()[_step])
	if not _next_container:
		push_error("[Tutorial] _next_container is null")
		return
	_next_container.visible = true
	if App.is_multiplayer and multiplayer.has_multiplayer_peer():
		_next_button.visible = multiplayer.is_server()
		_waiting_label.visible = not multiplayer.is_server()
	else:
		_next_button.visible = true
		_waiting_label.visible = false


func _hide_next_button() -> void:
	if _next_container:
		_next_container.visible = false


func _on_next_pressed() -> void:
	print("[Tutorial] _on_next_pressed() step=%s" % Step.keys()[_step])
	if App.is_multiplayer and multiplayer.has_multiplayer_peer():
		_rpc_advance_step.rpc()
	else:
		_advance_to_next_step()


@rpc("authority", "call_local", "reliable")
func _rpc_advance_step() -> void:
	_advance_to_next_step()


func _advance_to_next_step() -> void:
	print("[Tutorial] _advance_to_next_step() from step=%s" % Step.keys()[_step])
	_hide_next_button()
	var next_step: Step
	match _step:
		Step.TERRITORY_INTRO:
			next_step = Step.SHOW_HAND
		Step.SHOW_HAND:
			next_step = Step.CLAIM_TERRITORY
		Step.CLAIM_TERRITORY:
			next_step = Step.ATTACK_INTRO
		Step.ATTACK_INTRO:
			next_step = Step.MOCK_BATTLE
		Step.MOCK_BATTLE:
			next_step = Step.MINIGAME_INTRO
		Step.MINIGAME_INTRO:
			next_step = Step.MINIGAME_PREVIEW
		Step.MINIGAME_PREVIEW:
			next_step = Step.FAREWELL
		Step.FAREWELL:
			next_step = Step.DONE
		_:
			return
	_begin_step(next_step)


# ---------- STEP ORCHESTRATION ----------

func _begin_step(step: Step) -> void:
	print("[Tutorial] _begin_step(%s)" % Step.keys()[step])
	_step = step
	_typewriter_done = false
	_stop_pulse()
	_stop_card_icon_pulse()
	_disconnect_territory_click()
	_disconnect_card_icon_click()
	_disconnect_card_icon_close()

	match step:
		Step.TERRITORY_INTRO:
			_step_territory_intro()
		Step.SHOW_HAND:
			_step_show_hand()
		Step.CLAIM_TERRITORY:
			_step_claim_territory()
		Step.ATTACK_INTRO:
			_step_attack_intro()
		Step.MOCK_BATTLE:
			_step_mock_battle()
		Step.MINIGAME_INTRO:
			_step_minigame_intro()
		Step.MINIGAME_PREVIEW:
			_step_minigame_preview()
		Step.FAREWELL:
			_step_farewell()
		Step.DONE:
			_step_done()


# ---------- STEP 1: TERRITORY INTRO ----------

func _step_territory_intro() -> void:
	print("[Tutorial] _step_territory_intro — looking for territory %d" % CLAIM_TERRITORY_ID)
	var indicator := _get_indicator(CLAIM_TERRITORY_ID)
	if not indicator:
		push_warning("[Tutorial] Territory %d not found — skipping to next step" % CLAIM_TERRITORY_ID)
		_begin_step(Step.SHOW_HAND)
		return

	print("[Tutorial] Found indicator at position %s" % indicator.global_position)
	var target_pos := _get_gnome_position_near_indicator(indicator)
	print("[Tutorial] Moving gnome to %s" % target_pos)
	_tween_gnome_to(target_pos, 1.5, func():
		print("[Tutorial] Gnome arrived at territory, starting pulse + dialogue")
		_start_pulse(indicator)
		_set_dialogue_text(
			"See this glowing spot on the map? That is a colonly! "
			+"You can place cards on it to claim it as your own."
		)
	)


# ---------- STEP 2: SHOW HAND ----------

func _step_show_hand() -> void:
	print("[Tutorial] _step_show_hand — card_icon_button=%s" % (_card_icon_button != null))
	if _card_icon_button:
		_card_icon_button.visible = true
		_card_icon_button.modulate.a = 0.0
		var tween := create_tween()
		tween.tween_property(_card_icon_button, "modulate:a", 1.0, 0.4)
		_start_card_icon_pulse()
		print("[Tutorial] Card icon button made visible with pulse")

	_set_dialogue_text(
		"That card icon in the corner shows your cards. Click it to see what you have!"
	)

	_connect_card_icon_click()


# ---------- STEP 3: CLAIM TERRITORY ----------

func _step_claim_territory() -> void:
	print("[Tutorial] _step_claim_territory")
	var indicator := _get_indicator(CLAIM_TERRITORY_ID)
	if indicator:
		_start_pulse(indicator)
		print("[Tutorial] Started pulse on territory %d" % CLAIM_TERRITORY_ID)

	_set_dialogue_text(
		"Now click the glowing colonly to place your cards and claim it!"
	)

	_connect_territory_click(CLAIM_TERRITORY_ID)


# ---------- STEP 4: ATTACK INTRO ----------

func _step_attack_intro() -> void:
	print("[Tutorial] _step_attack_intro — looking for territory %d" % ATTACK_TERRITORY_ID)
	var indicator := _get_indicator(ATTACK_TERRITORY_ID)
	if not indicator:
		push_warning("[Tutorial] Territory %d not found — skipping" % ATTACK_TERRITORY_ID)
		_begin_step(Step.MOCK_BATTLE)
		return

	# Mock the enemy territory as claimed by "orc" with 1 card (frame 4)
	_set_indicator_frame(indicator, 4)
	print("[Tutorial] Set enemy indicator to frame 4 (orc 1-card)")

	var target_pos := _get_gnome_position_near_indicator(indicator)
	_tween_gnome_to(target_pos, 1.5, func():
		print("[Tutorial] Gnome arrived at attack territory, starting pulse + dialogue")
		_start_pulse(indicator)
		_set_dialogue_text(
			"This colonly belongs to another player. You can attack it to "
			+ "try and take it for yourself! If you win the battle, the colonly becomes yours."
		)
		_connect_territory_click(ATTACK_TERRITORY_ID)
	)


# ---------- STEP 5: MOCK BATTLE ----------

var _battle_waiting_for_typewriter: bool = false

func _step_mock_battle() -> void:
	print("[Tutorial] _step_mock_battle")
	var vp_size := get_viewport().get_visible_rect().size
	var center := Vector2((vp_size.x - GNOME_DISPLAY_SIZE) / 2.0, vp_size.y * 0.08)
	_tween_gnome_to(center, 1.0, func():
		print("[Tutorial] Gnome at center, showing battle explanation first")
		_set_dialogue_text(
			"Now let's see a battle! In a real game, you place your cards into "
			+ "lanes and can rearrange them before fighting. For now, watch how it "
			+ "plays out — each card has a power number. The higher power wins the round, "
			+ "and whoever wins more rounds takes the colonly!"
		)
		_battle_waiting_for_typewriter = true
	)


# ---------- STEP 6: MINIGAME INTRO ----------

func _step_minigame_intro() -> void:
	print("[Tutorial] _step_minigame_intro")
	# Walk gnome back to the claimed territory
	var indicator := _get_indicator(CLAIM_TERRITORY_ID)
	if not indicator:
		push_warning("[Tutorial] Claim territory %d not found for minigame intro" % CLAIM_TERRITORY_ID)
		_begin_step(Step.FAREWELL)
		return

	var target_pos := _get_gnome_position_near_indicator(indicator)
	_tween_gnome_to(target_pos, 1.5, func():
		print("[Tutorial] Gnome at claimed territory for minigame intro")
		_start_pulse(indicator)
		_set_dialogue_text(
			"One more thing! After everyone takes a turn claiming colonies, you can play minigames to earn more cards for your collection. "
			+ "Click on a colonly you own to see what minigames are available!"
		)
		_connect_territory_click(CLAIM_TERRITORY_ID)
	)


# ---------- STEP 7: MINIGAME PREVIEW ----------

func _step_minigame_preview() -> void:
	print("[Tutorial] _step_minigame_preview")
	_disconnect_territory_click()
	_stop_pulse()

	# Hide dialogue while we show the preview images
	if _dialogue_panel:
		_dialogue_panel.visible = false

	_build_minigame_preview_overlay()

	# After a short delay, show dialogue over the preview
	var tween := create_tween()
	tween.tween_interval(0.5)
	tween.tween_callback(func():
		if _dialogue_panel:
			_dialogue_panel.visible = true
			_dialogue_panel.modulate.a = 0.0
			var fade := create_tween()
			fade.tween_property(_dialogue_panel, "modulate:a", 1.0, 0.3)
		_set_dialogue_text(
			"Here are some of the minigames you'll play — a river rapids challenge and "
			+ "a bridge crossing race! Win them to add powerful cards to your hand."
		)
	)


func _build_minigame_preview_overlay() -> void:
	print("[Tutorial] _build_minigame_preview_overlay()")
	_minigame_overlay = Control.new()
	_minigame_overlay.name = "MinigamePreviewOverlay"
	_minigame_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_minigame_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not _gnome_container:
		push_error("[Tutorial] _gnome_container is null for minigame preview!")
		return
	_gnome_container.add_child(_minigame_overlay)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.04, 0.08, 0.9)
	style.border_color = Color(0.65, 0.55, 0.35, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.content_margin_left = 24.0
	style.content_margin_right = 24.0
	style.content_margin_top = 16.0
	style.content_margin_bottom = 16.0
	panel.add_theme_stylebox_override("panel", style)
	panel.anchor_left = 0.08
	panel.anchor_right = 0.92
	panel.anchor_top = 0.06
	panel.anchor_bottom = 0.62
	_minigame_overlay.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "-- MINIGAMES --"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", UI_FONT)
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4, 1.0))
	vbox.add_child(title)

	var images_hbox := HBoxContainer.new()
	images_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	images_hbox.add_theme_constant_override("separation", 24)
	vbox.add_child(images_hbox)

	# River rapids minigame image
	var river_vbox := VBoxContainer.new()
	river_vbox.add_theme_constant_override("separation", 6)
	river_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	images_hbox.add_child(river_vbox)

	var river_tex := TextureRect.new()
	river_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	river_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	river_tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	river_tex.custom_minimum_size = Vector2(280, 180)
	river_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var river_sf: SpriteFrames = load("res://assets/flatwaterfallbg.pxo") as SpriteFrames
	if river_sf and river_sf.has_animation("default") and river_sf.get_frame_count("default") > 0:
		river_tex.texture = river_sf.get_frame_texture("default", 0)
		print("[Tutorial] Loaded river minigame preview")
	river_vbox.add_child(river_tex)

	var river_label := Label.new()
	river_label.text = "River Rapids"
	river_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	river_label.add_theme_font_override("font", UI_FONT)
	river_label.add_theme_font_size_override("font_size", 22)
	river_label.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0, 1.0))
	river_vbox.add_child(river_label)

	# Bridge crossing minigame image
	var bridge_vbox := VBoxContainer.new()
	bridge_vbox.add_theme_constant_override("separation", 6)
	bridge_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	images_hbox.add_child(bridge_vbox)

	var bridge_tex := TextureRect.new()
	bridge_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bridge_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	bridge_tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bridge_tex.custom_minimum_size = Vector2(280, 180)
	bridge_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bridge_texture: Texture2D = load("res://pictures/bridge_water.png") as Texture2D
	if bridge_texture:
		bridge_tex.texture = bridge_texture
		print("[Tutorial] Loaded bridge minigame preview")
	bridge_vbox.add_child(bridge_tex)

	var bridge_label := Label.new()
	bridge_label.text = "Bridge Crossing"
	bridge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bridge_label.add_theme_font_override("font", UI_FONT)
	bridge_label.add_theme_font_size_override("font_size", 22)
	bridge_label.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0, 1.0))
	bridge_vbox.add_child(bridge_label)

	# Fade in
	_minigame_overlay.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(_minigame_overlay, "modulate:a", 1.0, 0.4)
	print("[Tutorial] Minigame preview overlay built")


func _remove_minigame_overlay() -> void:
	if _minigame_overlay and is_instance_valid(_minigame_overlay):
		_minigame_overlay.queue_free()
		_minigame_overlay = null


# ---------- STEP 8: FAREWELL ----------

func _step_farewell() -> void:
	print("[Tutorial] _step_farewell")
	_remove_battle_overlay()
	_remove_minigame_overlay()
	var vp_size := get_viewport().get_visible_rect().size
	var center := Vector2((vp_size.x - GNOME_DISPLAY_SIZE) / 2.0, vp_size.y * 0.32)
	_tween_gnome_to(center, 1.0, func():
		print("[Tutorial] Gnome at center for farewell")
		_set_dialogue_text(
			"That's all you need to know, adventurer. Now go forth and conquer!"
		)
	)


# ---------- STEP 7: DONE ----------

func _step_done() -> void:
	print("[Tutorial] _step_done — cleaning up and emitting tutorial_completed")
	_cleanup()
	tutorial_completed.emit()


# ---------- TYPEWRITER CALLBACK ----------

func _on_typewriter_complete() -> void:
	_stop_voice_playback()
	_typewriter_done = true
	print("[Tutorial] Typewriter complete at step=%s" % Step.keys()[_step])
	match _step:
		Step.TERRITORY_INTRO:
			_show_next_button()
		Step.SHOW_HAND:
			if not _awaiting_card_icon_click:
				_show_next_button()
		Step.CLAIM_TERRITORY:
			pass
		Step.ATTACK_INTRO:
			pass
		Step.MOCK_BATTLE:
			if _battle_waiting_for_typewriter:
				_battle_waiting_for_typewriter = false
				_auto_advance_timer = 2.0
		Step.MINIGAME_INTRO:
			pass  # waiting for territory click
		Step.MINIGAME_PREVIEW:
			_show_next_button()
		Step.FAREWELL:
			_show_next_button()


# ---------- TYPEWRITER ----------

func _set_dialogue_text(text: String) -> void:
	_full_text = text
	_visible_chars = 0
	_typewriter_timer = 0.0
	_typewriter_done = false
	if _dialogue_label:
		_dialogue_label.text = _full_text
		_dialogue_label.visible_characters = 0
	_play_next_voice_line()


func _process_typewriter(delta: float) -> void:
	if _typewriter_done or _full_text.is_empty():
		return
	if _visible_chars >= _full_text.length():
		return
	_typewriter_timer += delta
	var interval := 1.0 / TYPEWRITER_CHARS_PER_SEC
	while _typewriter_timer >= interval and _visible_chars < _full_text.length():
		_typewriter_timer -= interval
		_visible_chars += 1
		if _dialogue_label:
			_dialogue_label.visible_characters = _visible_chars
	if _visible_chars >= _full_text.length():
		_on_typewriter_complete()


# ---------- GNOME MOVEMENT ----------

func _tween_gnome_to(target: Vector2, duration: float, on_complete: Callable) -> void:
	if not _gnome_rect:
		print("[Tutorial] WARNING: _gnome_rect is null in _tween_gnome_to, calling on_complete directly")
		on_complete.call()
		return
	_is_walking = true
	_frame_timer = 0.0
	if _walk_frames and _walk_frames.get_frame_count(_walk_anim_name) > 0:
		_gnome_rect.texture = _walk_frames.get_frame_texture(_walk_anim_name, 0)
	var tween := create_tween()
	tween.tween_property(_gnome_rect, "position", target, duration) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_callback(func():
		_is_walking = false
		if _front_texture:
			_gnome_rect.texture = _front_texture
		on_complete.call()
	)


func _process_walk_animation(delta: float) -> void:
	if not _is_walking or not _walk_frames:
		return
	var count := _walk_frames.get_frame_count(_walk_anim_name)
	if count <= 1:
		return
	_frame_timer += delta
	var spf := 1.0 / _anim_fps
	while _frame_timer >= spf:
		_frame_timer -= spf
		_frame_idx = (_frame_idx + 1) % count
		_gnome_rect.texture = _walk_frames.get_frame_texture(_walk_anim_name, _frame_idx)


# ---------- FADE GNOME + DIALOGUE ----------

func _fade_gnome_and_dialogue(fade_in: bool, on_complete: Callable) -> void:
	var target_alpha := 1.0 if fade_in else 0.0
	var duration := 0.4
	var tween := create_tween()
	if _gnome_rect and is_instance_valid(_gnome_rect):
		tween.parallel().tween_property(_gnome_rect, "modulate:a", target_alpha, duration)
	if _dialogue_panel and is_instance_valid(_dialogue_panel):
		if fade_in:
			_dialogue_panel.visible = true
		tween.parallel().tween_property(_dialogue_panel, "modulate:a", target_alpha, duration)
	tween.tween_callback(func():
		if not fade_in and _dialogue_panel and is_instance_valid(_dialogue_panel):
			_dialogue_panel.visible = false
		on_complete.call()
	)


# ---------- TERRITORY HELPERS ----------

func _get_indicator(territory_id: int) -> Node:
	if not _territory_manager:
		print("[Tutorial] _get_indicator(%d) — territory_manager is null" % territory_id)
		return null
	if _territory_manager.has_method("get_territory_node"):
		var result = _territory_manager.get_territory_node(territory_id)
		print("[Tutorial] _get_indicator(%d) via get_territory_node => %s" % [territory_id, result != null])
		return result
	var territories_dict = _territory_manager.get("territories")
	if territories_dict is Dictionary:
		var result = territories_dict.get(territory_id, null)
		print("[Tutorial] _get_indicator(%d) via territories dict => %s" % [territory_id, result != null])
		return result
	print("[Tutorial] _get_indicator(%d) — no method found" % territory_id)
	return null


func _get_gnome_position_near_indicator(indicator: Node) -> Vector2:
	var ind_pos: Vector2 = indicator.global_position
	var ind_size := Vector2(128, 128)
	# Position gnome to the left of the indicator
	var offset := Vector2(-GNOME_DISPLAY_SIZE - 10.0, - (GNOME_DISPLAY_SIZE - ind_size.y) * 0.5)
	var result := ind_pos + offset
	var vp_size := get_viewport().get_visible_rect().size
	result.x = clampf(result.x, 0.0, vp_size.x - GNOME_DISPLAY_SIZE)
	result.y = clampf(result.y, 0.0, vp_size.y - GNOME_DISPLAY_SIZE)
	return result


func _set_indicator_frame(indicator: Node, frame_idx: int) -> void:
	var tex_rect = indicator.get("_texture_rect")
	var sf = indicator.get("_sprite_frames")
	if not tex_rect or not sf:
		print("[Tutorial] _set_indicator_frame — tex_rect=%s sf=%s" % [tex_rect != null, sf != null])
		return
	if not sf.has_animation("default"):
		print("[Tutorial] _set_indicator_frame — no 'default' animation")
		return
	var count: int = sf.get_frame_count("default")
	frame_idx = clampi(frame_idx, 0, maxi(0, count - 1))
	tex_rect.texture = sf.get_frame_texture("default", frame_idx)
	print("[Tutorial] _set_indicator_frame => frame %d (of %d)" % [frame_idx, count])


# ---------- PULSING GLOW ----------

func _start_pulse(indicator: Node) -> void:
	_pulsing_indicator = indicator
	_pulse_timer = 0.0
	if indicator.has_method("show_selection_glow"):
		indicator.show_selection_glow()


func _stop_pulse() -> void:
	if _pulsing_indicator and is_instance_valid(_pulsing_indicator):
		if _pulsing_indicator.has_method("deselect"):
			_pulsing_indicator.deselect()
	_pulsing_indicator = null


func _process_pulse(delta: float) -> void:
	if not _pulsing_indicator or not is_instance_valid(_pulsing_indicator):
		return
	_pulse_timer += delta
	var alpha := 0.2 + 0.2 * sin(_pulse_timer * 3.0)
	if _pulsing_indicator.has_method("_set_glow_alpha"):
		_pulsing_indicator._set_glow_alpha(alpha)


# ---------- CARD ICON PULSE ----------

func _start_card_icon_pulse() -> void:
	_card_icon_pulse_active = true
	if _card_icon_button:
		_card_icon_original_modulate = _card_icon_button.modulate


func _stop_card_icon_pulse() -> void:
	_card_icon_pulse_active = false
	if _card_icon_button and is_instance_valid(_card_icon_button):
		_card_icon_button.modulate = _card_icon_original_modulate


func _process_card_icon_pulse(delta: float) -> void:
	if not _card_icon_pulse_active or not _card_icon_button:
		return
	_pulse_timer += delta
	var brightness := 1.0 + 0.3 * sin(_pulse_timer * 4.0)
	_card_icon_button.modulate = Color(brightness, brightness, brightness, _card_icon_button.modulate.a)


# ---------- TERRITORY CLICK INTERCEPTION ----------

func _connect_territory_click(territory_id: int) -> void:
	_disconnect_territory_click()
	_awaiting_territory_click = territory_id
	if not _territory_manager:
		print("[Tutorial] _connect_territory_click(%d) — no territory_manager" % territory_id)
		return
	if not _territory_manager.has_signal("territory_selected"):
		print("[Tutorial] _connect_territory_click(%d) — no territory_selected signal" % territory_id)
		return
	_territory_manager.territory_selected.connect(_on_territory_selected_for_tutorial)
	_territory_click_connected = true
	print("[Tutorial] Connected territory_selected signal, waiting for click on %d" % territory_id)


func _disconnect_territory_click() -> void:
	if _territory_click_connected and _territory_manager and is_instance_valid(_territory_manager):
		if _territory_manager.has_signal("territory_selected") and _territory_manager.territory_selected.is_connected(_on_territory_selected_for_tutorial):
			_territory_manager.territory_selected.disconnect(_on_territory_selected_for_tutorial)
	_territory_click_connected = false
	_awaiting_territory_click = -1


func _on_territory_selected_for_tutorial(territory_id: int) -> void:
	print("[Tutorial] Territory clicked: %d (awaiting: %d, step: %s)" % [
		territory_id, _awaiting_territory_click, Step.keys()[_step]])
	if territory_id != _awaiting_territory_click:
		return
	if _step == Step.CLAIM_TERRITORY:
		if App.is_multiplayer and multiplayer.has_multiplayer_peer():
			if not multiplayer.is_server():
				return
			_rpc_claim_territory.rpc()
		else:
			_apply_claim_territory()
	elif _step == Step.ATTACK_INTRO:
		if App.is_multiplayer and multiplayer.has_multiplayer_peer():
			if not multiplayer.is_server():
				return
			_rpc_start_mock_battle.rpc()
		else:
			_apply_start_mock_battle()
	elif _step == Step.MINIGAME_INTRO:
		if App.is_multiplayer and multiplayer.has_multiplayer_peer():
			if not multiplayer.is_server():
				return
			_rpc_show_minigame_preview.rpc()
		else:
			_apply_show_minigame_preview()


# ---------- CARD ICON CLICK INTERCEPTION ----------

func _connect_card_icon_click() -> void:
	_disconnect_card_icon_click()
	_awaiting_card_icon_click = true
	if not _card_icon_button:
		print("[Tutorial] _connect_card_icon_click — no card_icon_button")
		return
	_card_icon_button.pressed.connect(_on_card_icon_pressed_for_tutorial)
	_card_icon_click_connected = true
	print("[Tutorial] Connected card_icon_button.pressed signal")


func _disconnect_card_icon_click() -> void:
	_awaiting_card_icon_click = false
	if _card_icon_click_connected and _card_icon_button and is_instance_valid(_card_icon_button):
		if _card_icon_button.pressed.is_connected(_on_card_icon_pressed_for_tutorial):
			_card_icon_button.pressed.disconnect(_on_card_icon_pressed_for_tutorial)
	_card_icon_click_connected = false


func _on_card_icon_pressed_for_tutorial() -> void:
	print("[Tutorial] Card icon button clicked! step=%s" % Step.keys()[_step])
	if not _awaiting_card_icon_click:
		return
	if App.is_multiplayer and multiplayer.has_multiplayer_peer():
		if not multiplayer.is_server():
			return
		_rpc_open_hand.rpc()
	else:
		_apply_open_hand()


# ---------- HAND CLOSE INTERCEPTION ----------

func _connect_card_icon_close() -> void:
	_disconnect_card_icon_close()
	_awaiting_hand_close = true
	if not _card_icon_button:
		print("[Tutorial] _connect_card_icon_close — no card_icon_button")
		return
	_card_icon_button.pressed.connect(_on_card_icon_pressed_to_close)
	_hand_close_connected = true
	print("[Tutorial] Connected card icon for hand-close, waiting for click")


func _disconnect_card_icon_close() -> void:
	_awaiting_hand_close = false
	if _hand_close_connected and _card_icon_button and is_instance_valid(_card_icon_button):
		if _card_icon_button.pressed.is_connected(_on_card_icon_pressed_to_close):
			_card_icon_button.pressed.disconnect(_on_card_icon_pressed_to_close)
	_hand_close_connected = false


func _on_card_icon_pressed_to_close() -> void:
	print("[Tutorial] Card icon clicked to close hand! step=%s" % Step.keys()[_step])
	if not _awaiting_hand_close:
		return
	if App.is_multiplayer and multiplayer.has_multiplayer_peer():
		if not multiplayer.is_server():
			return
		_rpc_close_hand.rpc()
	else:
		_apply_close_hand()


func _apply_close_hand() -> void:
	print("[Tutorial] _apply_close_hand()")
	_disconnect_card_icon_close()
	_stop_card_icon_pulse()

	# Close the hand panel
	if _hand_display_panel:
		var tween := create_tween()
		tween.tween_property(_hand_display_panel, "modulate:a", 0.0, 0.2)
		tween.tween_callback(func():
			if is_instance_valid(_hand_display_panel):
				_hand_display_panel.visible = false
		)

	# Keep card icon visible but stop pulsing
	if _card_icon_button:
		_card_icon_button.visible = true
		_card_icon_button.modulate = Color(1, 1, 1, 1)

	# Show dialogue panel again
	if _dialogue_panel:
		_dialogue_panel.visible = true

	# Auto-advance to claim step after a short delay
	_auto_advance_timer = 1.0


# ---------- RPC METHODS ----------

@rpc("authority", "call_local", "reliable")
func _rpc_open_hand() -> void:
	_apply_open_hand()


@rpc("authority", "call_local", "reliable")
func _rpc_close_hand() -> void:
	_apply_close_hand()


@rpc("authority", "call_local", "reliable")
func _rpc_claim_territory() -> void:
	_apply_claim_territory()


@rpc("authority", "call_local", "reliable")
func _rpc_start_mock_battle() -> void:
	_apply_start_mock_battle()


@rpc("authority", "call_local", "reliable")
func _rpc_show_minigame_preview() -> void:
	_apply_show_minigame_preview()


# ---------- APPLY ACTIONS (run on all peers) ----------

func _apply_open_hand() -> void:
	print("[Tutorial] _apply_open_hand()")
	_disconnect_card_icon_click()
	_populate_mock_hand()

	# Hide the dialogue panel so cards don't overlap with text
	if _dialogue_panel:
		_dialogue_panel.visible = false

	if _hand_display_panel:
		_hand_display_panel.visible = true
		_hand_display_panel.modulate.a = 0.0
		var tween := create_tween()
		tween.tween_property(_hand_display_panel, "modulate:a", 1.0, 0.3)

	# Keep card icon button visible and pulsing so the user can close the hand
	if _card_icon_button:
		_card_icon_button.visible = true
		_card_icon_button.modulate = Color(1, 1, 1, 1)
		_start_card_icon_pulse()

	# Wait for the user to click the card icon again to close the hand
	_awaiting_hand_close = true
	_connect_card_icon_close()


func _apply_claim_territory() -> void:
	print("[Tutorial] _apply_claim_territory()")
	_disconnect_territory_click()
	_stop_pulse()

	var indicator := _get_indicator(CLAIM_TERRITORY_ID)
	if indicator:
		_set_indicator_frame(indicator, 1)

	if _hand_display_panel:
		var tween := create_tween()
		tween.tween_property(_hand_display_panel, "modulate:a", 0.0, 0.2)
		tween.tween_callback(func():
			if is_instance_valid(_hand_display_panel):
				_hand_display_panel.visible = false
		)

	_set_dialogue_text("Excellent! You've claimed the colonly! Now it belongs to you.")
	_auto_advance_timer = 3.0


func _apply_start_mock_battle() -> void:
	print("[Tutorial] _apply_start_mock_battle()")
	_disconnect_territory_click()
	_stop_pulse()
	_advance_to_next_step()


func _apply_show_minigame_preview() -> void:
	print("[Tutorial] _apply_show_minigame_preview()")
	_disconnect_territory_click()
	_stop_pulse()
	_advance_to_next_step()


func _on_auto_advance() -> void:
	print("[Tutorial] _on_auto_advance() step=%s" % Step.keys()[_step])
	match _step:
		Step.SHOW_HAND:
			_advance_to_next_step()
		Step.CLAIM_TERRITORY:
			_hide_next_button()
			_begin_step(Step.ATTACK_INTRO)
		Step.MOCK_BATTLE:
			# Typewriter finished + delay elapsed — fade out gnome/dialogue, then start battle
			print("[Tutorial] Fading out gnome + dialogue before battle")
			_fade_gnome_and_dialogue(false, func():
				print("[Tutorial] Starting battle overlay")
				_build_mock_battle_overlay()
				_battle_round = 0
				_battle_step_timer = 2.0
			)
		_:
			_advance_to_next_step()


# ---------- MOCK HAND POPULATION ----------

func _populate_mock_hand() -> void:
	print("[Tutorial] _populate_mock_hand()")
	if not _hand_container:
		print("[Tutorial] WARNING: _hand_container is null")
		return
	for child in _hand_container.get_children():
		child.queue_free()
	for card_data in MOCK_PLAYER_CARDS:
		var tex := TextureRect.new()
		tex.expand_mode = TextureRect.EXPAND_FIT_HEIGHT_PROPORTIONAL
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.custom_minimum_size = Vector2(240, 360)
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var path: String = card_data.get("path", "")
		var frame: int = int(card_data.get("frame", 0))
		if path != "" and ResourceLoader.exists(path):
			var sf: SpriteFrames = load(path) as SpriteFrames
			if sf and sf.has_animation("default") and sf.get_frame_count("default") > frame:
				tex.texture = sf.get_frame_texture("default", frame)
				print("[Tutorial] Loaded mock card: %s frame %d" % [path, frame])
			else:
				print("[Tutorial] WARNING: Could not load SpriteFrames from %s" % path)
		_hand_container.add_child(tex)


# ---------- MOCK BATTLE OVERLAY ----------

func _build_mock_battle_overlay() -> void:
	print("[Tutorial] _build_mock_battle_overlay()")
	_battle_overlay = Control.new()
	_battle_overlay.name = "MockBattleOverlay"
	_battle_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_battle_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not _gnome_container:
		push_error("[Tutorial] _gnome_container is null!")
		return
	_gnome_container.add_child(_battle_overlay)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.04, 0.08, 0.9)
	style.border_color = Color(0.65, 0.55, 0.35, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.content_margin_left = 20.0
	style.content_margin_right = 20.0
	style.content_margin_top = 16.0
	style.content_margin_bottom = 16.0
	panel.add_theme_stylebox_override("panel", style)
	panel.anchor_left = 0.1
	panel.anchor_right = 0.9
	panel.anchor_top = 0.2
	panel.anchor_bottom = 0.62
	_battle_overlay.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "-- BATTLE --"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", UI_FONT)
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4, 1.0))
	vbox.add_child(title)

	var defender_label := Label.new()
	defender_label.text = "Defender"
	defender_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	defender_label.add_theme_font_override("font", UI_FONT)
	defender_label.add_theme_font_size_override("font_size", 20)
	defender_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4, 1.0))
	vbox.add_child(defender_label)

	var pairs_hbox := HBoxContainer.new()
	pairs_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	pairs_hbox.add_theme_constant_override("separation", 24)
	vbox.add_child(pairs_hbox)

	_battle_card_pairs.clear()
	for i in range(3):
		var pair_vbox := VBoxContainer.new()
		pair_vbox.add_theme_constant_override("separation", 4)
		pair_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		pairs_hbox.add_child(pair_vbox)

		var round_label := Label.new()
		round_label.text = "Round %d" % (i + 1)
		round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		round_label.add_theme_font_override("font", UI_FONT)
		round_label.add_theme_font_size_override("font_size", 18)
		round_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1.0))
		pair_vbox.add_child(round_label)

		# Enemy card on top
		var enemy_card := _create_card_back()
		enemy_card.name = "EnemyCard_%d" % i
		pair_vbox.add_child(enemy_card)

		var vs_label := Label.new()
		vs_label.text = "VS"
		vs_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vs_label.add_theme_font_override("font", UI_FONT)
		vs_label.add_theme_font_size_override("font_size", 20)
		vs_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 1.0))
		pair_vbox.add_child(vs_label)

		# Player card on bottom
		var player_card := _create_card_back()
		player_card.name = "PlayerCard_%d" % i
		pair_vbox.add_child(player_card)

		var result_label := Label.new()
		result_label.text = ""
		result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		result_label.add_theme_font_override("font", UI_FONT)
		result_label.add_theme_font_size_override("font_size", 22)
		result_label.visible = false
		pair_vbox.add_child(result_label)

		_battle_card_pairs.append({
			"player": player_card,
			"enemy": enemy_card,
			"result_label": result_label,
		})

	# "You" label row
	var you_label := Label.new()
	you_label.text = "You"
	you_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	you_label.add_theme_font_override("font", UI_FONT)
	you_label.add_theme_font_size_override("font_size", 20)
	you_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4, 1.0))
	vbox.add_child(you_label)

	_battle_result_label = Label.new()
	_battle_result_label.text = ""
	_battle_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_battle_result_label.add_theme_font_override("font", UI_FONT)
	_battle_result_label.add_theme_font_size_override("font_size", 34)
	_battle_result_label.visible = false
	vbox.add_child(_battle_result_label)
	print("[Tutorial] Battle overlay built")


func _create_card_back() -> TextureRect:
	var tex := TextureRect.new()
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tex.custom_minimum_size = Vector2(80, 120)
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cardback_path := "res://assets/cardback.pxo"
	if ResourceLoader.exists(cardback_path):
		var sf: SpriteFrames = load(cardback_path) as SpriteFrames
		if sf and sf.has_animation("default") and sf.get_frame_count("default") > 0:
			tex.texture = sf.get_frame_texture("default", 0)
	return tex


func _flip_card(tex_rect: TextureRect, card_data: Dictionary) -> void:
	if not is_instance_valid(tex_rect):
		print("[Tutorial] WARNING: tex_rect invalid in _flip_card")
		return
	var path: String = card_data.get("path", "")
	var frame: int = int(card_data.get("frame", 0))
	var tween := create_tween()
	tween.tween_property(tex_rect, "scale:x", 0.0, 0.3).set_ease(Tween.EASE_IN)
	tween.tween_callback(func():
		if not is_instance_valid(tex_rect):
			return
		if path != "" and ResourceLoader.exists(path):
			var sf: SpriteFrames = load(path) as SpriteFrames
			if sf and sf.has_animation("default") and sf.get_frame_count("default") > frame:
				tex_rect.texture = sf.get_frame_texture("default", frame)
	)
	tween.tween_property(tex_rect, "scale:x", 1.0, 0.3).set_ease(Tween.EASE_OUT)


func _advance_battle_round() -> void:
	print("[Tutorial] _advance_battle_round() round=%d" % _battle_round)
	if _battle_round >= 3:
		_show_battle_result()
		return

	if _battle_round >= _battle_card_pairs.size():
		push_error("[Tutorial] _battle_round %d out of range (pairs=%d)" % [_battle_round, _battle_card_pairs.size()])
		return

	var pair: Dictionary = _battle_card_pairs[_battle_round]
	var player_card: TextureRect = pair["player"]
	var enemy_card: TextureRect = pair["enemy"]
	var result_label: Label = pair["result_label"]
	var current_round: int = _battle_round

	_flip_card(player_card, MOCK_PLAYER_CARDS[current_round])

	var p_power: int = PLAYER_POWERS[current_round]
	var e_power: int = ENEMY_POWERS[current_round]

	var tween := create_tween()
	tween.tween_interval(0.8)
	tween.tween_callback(func():
		_flip_card(enemy_card, MOCK_ENEMY_CARDS[current_round])
	)
	tween.tween_interval(1.0)
	tween.tween_callback(func():
		if not is_instance_valid(result_label):
			return
		var result: String = BATTLE_RESULTS[current_round]
		result_label.visible = true
		if result == "win":
			result_label.text = "Power %d vs %d — WIN!" % [p_power, e_power]
			result_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3, 1.0))
		elif result == "lose":
			result_label.text = "Power %d vs %d — LOSE" % [p_power, e_power]
			result_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3, 1.0))
		else:
			result_label.text = "Power %d vs %d — TIE" % [p_power, e_power]
			result_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.3, 1.0))
		print("[Tutorial] Round %d: power %d vs %d => %s" % [current_round + 1, p_power, e_power, result])
	)

	_battle_round += 1
	_battle_step_timer = 3.5


func _show_battle_result() -> void:
	print("[Tutorial] _show_battle_result()")
	# Visually flip the attack territory to the player's ownership (elf frame 1)
	var indicator := _get_indicator(ATTACK_TERRITORY_ID)
	if indicator:
		_set_indicator_frame(indicator, 1)
		print("[Tutorial] Attack territory now shows player ownership")

	if _battle_result_label and is_instance_valid(_battle_result_label):
		_battle_result_label.visible = true
		_battle_result_label.text = "YOU WIN 2-1!  Territory conquered!"
		_battle_result_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3, 1.0))
		_battle_result_label.modulate.a = 0.0
		var tween := create_tween()
		tween.tween_property(_battle_result_label, "modulate:a", 1.0, 0.4)

	# Linger on the result, then fade out battle and bring gnome back for farewell
	var delay_tween := create_tween()
	delay_tween.tween_interval(2.5)
	delay_tween.tween_callback(func():
		print("[Tutorial] Fading out battle overlay, transitioning to farewell")
		_fade_battle_out_then_farewell()
	)


func _fade_battle_out_then_farewell() -> void:
	if _battle_overlay and is_instance_valid(_battle_overlay):
		var tween := create_tween()
		tween.tween_property(_battle_overlay, "modulate:a", 0.0, 0.5)
		tween.tween_callback(func():
			_remove_battle_overlay()
			_fade_gnome_and_dialogue(true, func():
				_begin_step(Step.MINIGAME_INTRO)
			)
		)
	else:
		_remove_battle_overlay()
		_fade_gnome_and_dialogue(true, func():
			_begin_step(Step.MINIGAME_INTRO)
		)


func _remove_battle_overlay() -> void:
	if _battle_overlay and is_instance_valid(_battle_overlay):
		_battle_overlay.queue_free()
		_battle_overlay = null
	_battle_card_pairs.clear()
	_battle_result_label = null


# ---------- CLEANUP ----------

func _cleanup() -> void:
	print("[Tutorial] _cleanup()")
	_stop_voice_playback()
	_stop_pulse()
	_stop_card_icon_pulse()
	_disconnect_territory_click()
	_disconnect_card_icon_click()
	_disconnect_card_icon_close()
	_remove_battle_overlay()
	_remove_minigame_overlay()

	for tid in [CLAIM_TERRITORY_ID, ATTACK_TERRITORY_ID]:
		var indicator := _get_indicator(tid)
		if indicator and indicator.has_method("update_claimed_visual"):
			indicator.update_claimed_visual()

	if _hand_display_panel and is_instance_valid(_hand_display_panel):
		_hand_display_panel.visible = false
	if _card_icon_button and is_instance_valid(_card_icon_button):
		_card_icon_button.visible = false

	if _hand_container and is_instance_valid(_hand_container):
		for child in _hand_container.get_children():
			child.queue_free()

	if _next_container and is_instance_valid(_next_container):
		_next_container.queue_free()

	print("[Tutorial] _cleanup() done")


func _play_next_voice_line() -> void:
	if not _voice_player:
		return
	_stop_voice_playback()
	if _voice_line_idx >= GNOME_VOICE_STREAMS.size():
		return
	_voice_player.stream = GNOME_VOICE_STREAMS[_voice_line_idx]
	_voice_line_idx += 1
	_voice_player.play()


func _stop_voice_playback() -> void:
	if _voice_player and _voice_player.playing:
		_voice_player.stop()


# ---------- STYLE HELPER ----------

func _make_button_style(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(2)
	s.set_corner_radius_all(4)
	s.content_margin_left = 16.0
	s.content_margin_right = 16.0
	s.content_margin_top = 8.0
	s.content_margin_bottom = 8.0
	return s

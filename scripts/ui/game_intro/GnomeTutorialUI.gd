extends Node

## GnomeTutorialUI — Pre-game gnome that walks on screen, delivers fantasy
## dialogue, and offers a tutorial rundown.  Self-contained programmatic
## component: created with .new(), receives node refs via initialize().

signal gnome_sequence_completed

const UI_FONT := preload("res://fonts/m5x7.ttf")
const GNOME_VOICE_STREAM := preload("res://dialog/gnome1.mp3")
const GNOME_VOICE_BUS := "SFX"
const GNOME_VOICE_VOLUME_DB := -7.0
const GNOME_VOICE_PITCH_SCALE := 1.03
const TYPEWRITER_CHARS_PER_SEC := 35.0
const GNOME_DISPLAY_SIZE := 256.0
const WALK_DURATION := 3.5
const ENTRANCE_DELAY := 1.0
const RESPONSE_LINGER := 2.0

enum Phase { WALKING, DIALOGUE, WAITING_FOR_CHOICE, RESPONSE, TUTORIAL, FADE_OUT, DONE }

const TutorialSequenceScript := preload("res://scripts/ui/game_intro/TutorialSequence.gd")

var current_phase: Phase = Phase.DONE

# Node refs from initialize()
var map_overlay: ColorRect
var showcase_container: CenterContainer
var territory_manager: Node
var card_icon_button: Button
var hand_display_panel: PanelContainer
var hand_container: HBoxContainer

# Tutorial sequence (when user picks "Yes")
var _tutorial_seq: Node

# Walk animation state
var _walk_frames: SpriteFrames
var _front_texture: Texture2D
var _gnome_rect: TextureRect
var _frame_idx: int = 0
var _frame_timer: float = 0.0
var _anim_fps: float = 8.0
var _walk_anim_name: String = "default"

# Dialogue state
var _dialogue_panel: PanelContainer
var _dialogue_label: RichTextLabel
var _voice_player: AudioStreamPlayer
var _typewriter_timer: float = 0.0
var _visible_chars: int = 0
var _full_text: String = ""

# Choice UI
var _yes_button: Button
var _no_button: Button
var _waiting_label: Label
var _button_container: HBoxContainer

# Visual root (sibling of this node, child of parent Control)
var _gnome_container: Control

# Linger timer after response text finishes
var _response_linger: float = 0.0


func initialize(nodes: Dictionary) -> void:
	map_overlay = nodes.get("map_overlay")
	showcase_container = nodes.get("showcase_container")
	territory_manager = nodes.get("territory_manager")
	card_icon_button = nodes.get("card_icon_button")
	hand_display_panel = nodes.get("hand_display_panel")
	hand_container = nodes.get("hand_container")


func start_sequence() -> void:
	_load_sprites()
	if not _walk_frames and not _front_texture:
		push_warning("[GnomeTutorialUI] Could not load gnome sprites — skipping sequence")
		gnome_sequence_completed.emit()
		return
	_build_ui()
	_start_walk()


func process_frame(delta: float) -> void:
	match current_phase:
		Phase.WALKING:
			_animate_walk_sprite(delta)
		Phase.DIALOGUE:
			_process_typewriter(delta)
		Phase.WAITING_FOR_CHOICE:
			pass
		Phase.RESPONSE:
			_process_typewriter(delta)
			if _response_linger > 0.0:
				_response_linger -= delta
				if _response_linger <= 0.0:
					_start_fade_out()
		Phase.TUTORIAL:
			if _tutorial_seq:
				_tutorial_seq.process_frame(delta)
		Phase.FADE_OUT, Phase.DONE:
			pass


func _unhandled_input(event: InputEvent) -> void:
	if current_phase == Phase.DONE:
		return
	# During TUTORIAL phase, allow clicks through so territory indicators and
	# card icon button can receive them (interception is via signal connections).
	if current_phase == Phase.TUTORIAL:
		return
	if event is InputEventKey and event.pressed:
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		get_viewport().set_input_as_handled()


# ---------- SPRITE LOADING ----------

func _load_sprites() -> void:
	_walk_frames = load("res://assets/gnome-animation.pxo") as SpriteFrames
	if _walk_frames:
		var walk_names := _walk_frames.get_animation_names()
		if walk_names.size() > 0:
			_walk_anim_name = walk_names[0]
			_anim_fps = _walk_frames.get_animation_speed(_walk_anim_name)
			if _anim_fps <= 0.0:
				_anim_fps = 8.0

	var front_frames := load("res://assets/gnome.pxo") as SpriteFrames
	if front_frames:
		var front_names := front_frames.get_animation_names()
		if front_names.size() > 0 and front_frames.get_frame_count(front_names[0]) > 0:
			_front_texture = front_frames.get_frame_texture(front_names[0], 0)


# ---------- UI CONSTRUCTION ----------

func _build_ui() -> void:
	_gnome_container = Control.new()
	_gnome_container.name = "GnomeOverlay"
	_gnome_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_gnome_container.z_index = 10
	_gnome_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_parent().add_child(_gnome_container)

	_gnome_rect = TextureRect.new()
	_gnome_rect.name = "GnomeSprite"
	_gnome_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_gnome_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_gnome_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_gnome_rect.custom_minimum_size = Vector2(GNOME_DISPLAY_SIZE, GNOME_DISPLAY_SIZE)
	_gnome_rect.size = Vector2(GNOME_DISPLAY_SIZE, GNOME_DISPLAY_SIZE)
	if _walk_frames and _walk_frames.get_frame_count(_walk_anim_name) > 0:
		_gnome_rect.texture = _walk_frames.get_frame_texture(_walk_anim_name, 0)
	elif _front_texture:
		_gnome_rect.texture = _front_texture
	_gnome_container.add_child(_gnome_rect)
	_voice_player = AudioStreamPlayer.new()
	_voice_player.name = "GnomeVoicePlayer"
	_voice_player.stream = GNOME_VOICE_STREAM
	_voice_player.volume_db = GNOME_VOICE_VOLUME_DB
	_voice_player.pitch_scale = GNOME_VOICE_PITCH_SCALE
	if AudioServer.get_bus_index(GNOME_VOICE_BUS) != -1:
		_voice_player.bus = GNOME_VOICE_BUS
	_gnome_container.add_child(_voice_player)

	_build_dialogue_panel()


func _build_dialogue_panel() -> void:
	_dialogue_panel = PanelContainer.new()
	_dialogue_panel.name = "GnomeDialoguePanel"
	_dialogue_panel.visible = false
	_dialogue_panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.06, 0.12, 0.92)
	style.border_color = Color(0.65, 0.55, 0.35, 1.0)
	style.set_border_width_all(3)
	style.set_corner_radius_all(8)
	style.content_margin_left = 24.0
	style.content_margin_right = 24.0
	style.content_margin_top = 18.0
	style.content_margin_bottom = 18.0
	_dialogue_panel.add_theme_stylebox_override("panel", style)

	_dialogue_panel.anchor_left = 0.12
	_dialogue_panel.anchor_right = 0.88
	_dialogue_panel.anchor_top = 0.68
	_dialogue_panel.anchor_bottom = 0.93

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	_dialogue_panel.add_child(vbox)

	_dialogue_label = RichTextLabel.new()
	_dialogue_label.name = "DialogueText"
	_dialogue_label.bbcode_enabled = false
	_dialogue_label.fit_content = true
	_dialogue_label.scroll_active = false
	_dialogue_label.add_theme_font_override("normal_font", UI_FONT)
	_dialogue_label.add_theme_font_size_override("normal_font_size", 28)
	_dialogue_label.add_theme_color_override("default_color", Color(0.95, 0.9, 0.75, 1.0))
	_dialogue_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_dialogue_label.visible_characters = 0
	vbox.add_child(_dialogue_label)

	_button_container = HBoxContainer.new()
	_button_container.name = "ChoiceButtons"
	_button_container.visible = false
	_button_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_button_container.add_theme_constant_override("separation", 32)
	vbox.add_child(_button_container)

	var btn_normal := _make_button_style(Color(0.18, 0.15, 0.25, 1.0), Color(0.65, 0.55, 0.35, 1.0))
	var btn_hover := _make_button_style(Color(0.28, 0.24, 0.38, 1.0), Color(0.85, 0.75, 0.45, 1.0))

	_yes_button = _make_choice_button("Yes, please!", btn_normal, btn_hover)
	_yes_button.pressed.connect(_on_yes_pressed)
	_button_container.add_child(_yes_button)

	_no_button = _make_choice_button("No, let's play!", btn_normal, btn_hover)
	_no_button.pressed.connect(_on_no_pressed)
	_button_container.add_child(_no_button)

	_waiting_label = Label.new()
	_waiting_label.text = "Waiting for host to decide..."
	_waiting_label.add_theme_font_override("font", UI_FONT)
	_waiting_label.add_theme_font_size_override("font_size", 22)
	_waiting_label.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55, 1.0))
	_waiting_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_waiting_label.visible = false
	_button_container.add_child(_waiting_label)

	_gnome_container.add_child(_dialogue_panel)


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


func _make_choice_button(label: String, normal: StyleBoxFlat, hover: StyleBoxFlat) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.add_theme_font_override("font", UI_FONT)
	btn.add_theme_font_size_override("font_size", 26)
	btn.add_theme_color_override("font_color", Color(0.95, 0.9, 0.75))
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	return btn


# ---------- WALK SEQUENCE ----------

func _start_walk() -> void:
	current_phase = Phase.WALKING

	if map_overlay:
		map_overlay.modulate.a = 0.82

	var vp_size := get_viewport().get_visible_rect().size
	var target_x := (vp_size.x - GNOME_DISPLAY_SIZE) / 2.0
	var target_y := vp_size.y * 0.32

	_gnome_rect.position = Vector2(-GNOME_DISPLAY_SIZE, target_y)
	_gnome_rect.modulate.a = 0.0

	var tween := create_tween()
	tween.tween_interval(ENTRANCE_DELAY)
	tween.tween_property(_gnome_rect, "modulate:a", 1.0, 0.3)
	tween.tween_property(_gnome_rect, "position:x", target_x, WALK_DURATION) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_callback(_on_walk_complete)


func _on_walk_complete() -> void:
	if _front_texture:
		_gnome_rect.texture = _front_texture

	current_phase = Phase.DIALOGUE
	_dialogue_panel.visible = true
	_dialogue_panel.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(_dialogue_panel, "modulate:a", 1.0, 0.4)

	_set_dialogue_text(
		"Greetings, brave adventurers! I am Bramblewood, keeper of the ancient game scrolls.\n"
		+ "Before we begin your quest for dominion... would you like a rundown on how to play?"
	)


# ---------- WALK SPRITE ANIMATION ----------

func _animate_walk_sprite(delta: float) -> void:
	if not _walk_frames:
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


# ---------- TYPEWRITER ----------

func _set_dialogue_text(text: String) -> void:
	_full_text = text
	_dialogue_label.text = _full_text
	_visible_chars = 0
	_dialogue_label.visible_characters = 0
	_typewriter_timer = 0.0
	if _voice_player and _voice_player.stream:
		_voice_player.stop()
		_voice_player.play()


func _process_typewriter(delta: float) -> void:
	if _visible_chars >= _full_text.length():
		return
	_typewriter_timer += delta
	var interval := 1.0 / TYPEWRITER_CHARS_PER_SEC
	while _typewriter_timer >= interval and _visible_chars < _full_text.length():
		_typewriter_timer -= interval
		_visible_chars += 1
		_dialogue_label.visible_characters = _visible_chars
	if _visible_chars >= _full_text.length():
		_on_typewriter_finished()


func _on_typewriter_finished() -> void:
	if _voice_player and _voice_player.playing:
		_voice_player.stop()
	if current_phase == Phase.DIALOGUE:
		current_phase = Phase.WAITING_FOR_CHOICE
		_show_choice_buttons()
	elif current_phase == Phase.RESPONSE:
		_response_linger = RESPONSE_LINGER


# ---------- CHOICE BUTTONS ----------

func _show_choice_buttons() -> void:
	_button_container.visible = true
	if App.is_multiplayer and multiplayer.has_multiplayer_peer():
		var is_host := multiplayer.is_server()
		_yes_button.visible = is_host
		_no_button.visible = is_host
		_waiting_label.visible = not is_host
	else:
		_yes_button.visible = true
		_no_button.visible = true
		_waiting_label.visible = false


func _on_yes_pressed() -> void:
	if App.is_multiplayer and multiplayer.has_multiplayer_peer():
		_rpc_tutorial_decision.rpc(true)
	else:
		_apply_decision(true)


func _on_no_pressed() -> void:
	if App.is_multiplayer and multiplayer.has_multiplayer_peer():
		_rpc_tutorial_decision.rpc(false)
	else:
		_apply_decision(false)


@rpc("authority", "call_local", "reliable")
func _rpc_tutorial_decision(wants_tutorial: bool) -> void:
	_apply_decision(wants_tutorial)


func _apply_decision(wants_tutorial: bool) -> void:
	print("[GnomeTutorialUI] _apply_decision(wants_tutorial=%s)" % wants_tutorial)
	_button_container.visible = false

	if wants_tutorial:
		_start_tutorial()
	else:
		current_phase = Phase.RESPONSE
		_set_dialogue_text("Very well! May fortune favor the bold. Let the games begin!")


func _start_tutorial() -> void:
	print("[GnomeTutorialUI] _start_tutorial() — entering TUTORIAL phase")
	print("[GnomeTutorialUI] Refs: territory_manager=%s card_icon=%s hand_panel=%s hand_container=%s" % [
		territory_manager != null, card_icon_button != null,
		hand_display_panel != null, hand_container != null])
	current_phase = Phase.TUTORIAL
	if _voice_player and _voice_player.playing:
		_voice_player.stop()
	_tutorial_seq = TutorialSequenceScript.new()
	_tutorial_seq.name = "TutorialSequence"
	add_child(_tutorial_seq)
	_tutorial_seq.initialize({
		"gnome_rect": _gnome_rect,
		"front_texture": _front_texture,
		"walk_frames": _walk_frames,
		"walk_anim_name": _walk_anim_name,
		"anim_fps": _anim_fps,
		"dialogue_panel": _dialogue_panel,
		"dialogue_label": _dialogue_label,
		"gnome_container": _gnome_container,
		"map_overlay": map_overlay,
		"territory_manager": territory_manager,
		"card_icon_button": card_icon_button,
		"hand_display_panel": hand_display_panel,
		"hand_container": hand_container,
	})
	_tutorial_seq.tutorial_completed.connect(_on_tutorial_completed)
	_tutorial_seq.start()
	print("[GnomeTutorialUI] Tutorial sequence started")


func _on_tutorial_completed() -> void:
	print("[GnomeTutorialUI] _on_tutorial_completed — starting fade out")
	if _tutorial_seq:
		_tutorial_seq.queue_free()
		_tutorial_seq = null
	_start_fade_out()


# ---------- FADE OUT / COMPLETE ----------

func _start_fade_out() -> void:
	current_phase = Phase.FADE_OUT
	if _voice_player and _voice_player.playing:
		_voice_player.stop()
	var tween := create_tween()
	tween.tween_property(_gnome_container, "modulate:a", 0.0, 0.6)
	if map_overlay:
		tween.parallel().tween_property(map_overlay, "modulate:a", 0.6, 0.6)
	tween.tween_callback(_complete)


func _complete() -> void:
	current_phase = Phase.DONE
	if is_instance_valid(_gnome_container):
		_gnome_container.queue_free()
	gnome_sequence_completed.emit()

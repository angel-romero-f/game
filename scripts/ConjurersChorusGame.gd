extends Node2D

## Conjurer's Chorus — Simon Says minigame with 4 magical performers.
##
## Watch the sequence of highlighted performers, then repeat it using
## keys 1–4 or by clicking the performer blocks.  5 rounds of increasing
## length.  One mistake = immediate loss.  20-second time limit.
##
## Performers, stage, and feedback are built programmatically so sprites
## can be swapped in later without restructuring.

var game_over: bool = false
var player_won: bool = false
var _has_returned: bool = false
const SIMON_SAYS_MUSIC_PATH := "res://music/simon says.mp3"
const PERSISTENT_CHORUS_PLAYER_NAME := "PersistentConjurersChorusMusic"
var _chorus_music_player: AudioStreamPlayer = null

# ── 20-SECOND TIMER (same infrastructure as other minigames) ──
const MINIGAME_TIME_LIMIT: float = 20.0
var _minigame_timer: float = MINIGAME_TIME_LIMIT
var _timer_active: bool = false

# ── TUNING — all timing / layout values gathered here for easy tweaking ──

## Number of performers in the lineup.
const PERFORMER_COUNT: int = 4
## Rounds the player must survive to win.
const TOTAL_ROUNDS: int = 5

## Seconds a performer stays highlighted during sequence playback.
const NOTE_SHOW_DURATION: float = 0.25
## Seconds of silence between consecutive notes during playback.
const NOTE_GAP: float = 0.08
## Pause before the first note of each round's playback.
const PRE_SEQUENCE_DELAY: float = 0.25
## Pause after the last note before accepting player input.
const POST_SEQUENCE_DELAY: float = 0.18
## Pause between a completed round and the next playback.
const BETWEEN_ROUND_DELAY: float = 0.35
## How long the performer flashes when the *player* presses it.
const PLAYER_FLASH_DURATION: float = 0.12

# ── PERFORMER VISUAL CONSTANTS ──

const PERF_W: float = 110.0
const PERF_H: float = 150.0
const PERF_GAP: float = 28.0

const BASE_COLORS: Array = [
	Color(0.72, 0.13, 0.13),  # Crimson
	Color(0.13, 0.42, 0.72),  # Royal blue
	Color(0.13, 0.62, 0.22),  # Emerald
	Color(0.76, 0.62, 0.08),  # Gold
]
const BRIGHT_COLORS: Array = [
	Color(1.0, 0.45, 0.45),
	Color(0.45, 0.72, 1.0),
	Color(0.45, 1.0, 0.55),
	Color(1.0, 0.92, 0.45),
]
const GLOW_COLORS: Array = [
	Color(1.0, 0.3, 0.3, 0.35),
	Color(0.3, 0.6, 1.0, 0.35),
	Color(0.3, 1.0, 0.4, 0.35),
	Color(1.0, 0.85, 0.3, 0.35),
]

# ── GAME STATE ──

enum Phase { IDLE, SHOWING, INPUT, TRANSITION, WON, LOST }
var _phase: int = Phase.IDLE
var _current_round: int = 0
var _sequence: Array[int] = []
var _input_index: int = 0

# ── NODE REFERENCES (built at runtime) ──

## Each entry: { container: Node2D, base_rect: ColorRect, glow_rect: ColorRect,
##               num_label: Label, origin_y: float }
var _performers: Array = []
var _status_label: Label = null
var _round_label: Label = null
var _pixel_font: Font = null


# ══════════════════════════════════════════════════════════════
#  LIFECYCLE
# ══════════════════════════════════════════════════════════════

func _ready() -> void:
	_setup_chorus_music()

	_pixel_font = load("res://fonts/m5x7.ttf") as Font

	if App.minigame_time_remaining <= 0.0:
		App.reset_lives()

	if App.minigame_time_remaining > 0.0:
		_minigame_timer = App.minigame_time_remaining
	else:
		_minigame_timer = MINIGAME_TIME_LIMIT
		App.minigame_time_remaining = _minigame_timer
	_timer_active = true

	_build_stage()
	_build_performers()
	_build_labels()
	_generate_sequence()
	_start_round()
	print("[Minigame:ConjurersChorus] Timer started (%.1fs)" % _minigame_timer)

func _setup_chorus_music() -> void:
	# Simon Says music is exclusive to Conjurer's Chorus.
	App.stop_main_music()

	var root := get_tree().root
	var existing := root.get_node_or_null(PERSISTENT_CHORUS_PLAYER_NAME)
	if existing and existing is AudioStreamPlayer:
		_chorus_music_player = existing as AudioStreamPlayer
		if not _chorus_music_player.playing:
			_chorus_music_player.play()
		return

	var stream := load(SIMON_SAYS_MUSIC_PATH)
	if not stream is AudioStream:
		push_warning("[Minigame:ConjurersChorus] Missing or invalid music at %s" % SIMON_SAYS_MUSIC_PATH)
		return

	_chorus_music_player = AudioStreamPlayer.new()
	_chorus_music_player.name = PERSISTENT_CHORUS_PLAYER_NAME
	_chorus_music_player.bus = "Music"
	_chorus_music_player.stream = stream
	root.add_child(_chorus_music_player)

	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true

	_chorus_music_player.play()

func _stop_chorus_music() -> void:
	if _chorus_music_player and is_instance_valid(_chorus_music_player):
		_chorus_music_player.stop()
		_chorus_music_player.queue_free()
	_chorus_music_player = null


func _process(delta: float) -> void:
	if _timer_active:
		_minigame_timer -= delta
		App.minigame_time_remaining = _minigame_timer
		var ui := get_node_or_null("UI")
		if ui and ui.has_method("update_timer_display"):
			ui.update_timer_display(_minigame_timer)
		if _minigame_timer <= 0.0:
			_on_timeout()


# ══════════════════════════════════════════════════════════════
#  VISUAL CONSTRUCTION
# ══════════════════════════════════════════════════════════════

func _build_stage() -> void:
	var stage := ColorRect.new()
	stage.color = Color(0.08, 0.06, 0.14)
	stage.size = Vector2(620, 280)
	stage.position = Vector2(-310, -110)
	stage.z_index = -5
	add_child(stage)

	var floor_rect := ColorRect.new()
	floor_rect.color = Color(0.18, 0.12, 0.08)
	floor_rect.size = Vector2(600, 28)
	floor_rect.position = Vector2(-300, 140)
	floor_rect.z_index = -4
	add_child(floor_rect)

	var edge := ColorRect.new()
	edge.color = Color(0.35, 0.25, 0.15)
	edge.size = Vector2(600, 5)
	edge.position = Vector2(-300, 135)
	edge.z_index = -3
	add_child(edge)


func _build_performers() -> void:
	var total_w: float = PERFORMER_COUNT * PERF_W + (PERFORMER_COUNT - 1) * PERF_GAP
	var start_x: float = -total_w / 2.0

	for i in range(PERFORMER_COUNT):
		var cx: float = start_x + PERF_W / 2.0 + i * (PERF_W + PERF_GAP)
		var cy: float = 40.0
		var origin_y: float = cy

		var container := Node2D.new()
		container.position = Vector2(cx, cy)
		container.z_index = 2
		add_child(container)

		# Glow / spotlight — larger translucent rect behind, hidden by default
		var glow := ColorRect.new()
		glow.color = GLOW_COLORS[i]
		var pad: float = 18.0
		glow.size = Vector2(PERF_W + pad * 2, PERF_H + pad * 2)
		glow.position = Vector2(-PERF_W / 2.0 - pad, -PERF_H / 2.0 - pad)
		glow.z_index = -1
		glow.visible = false
		container.add_child(glow)

		# Thin border
		var border := ColorRect.new()
		border.color = Color(0.9, 0.85, 0.7, 0.15)
		border.size = Vector2(PERF_W + 4, PERF_H + 4)
		border.position = Vector2(-PERF_W / 2.0 - 2, -PERF_H / 2.0 - 2)
		border.z_index = 0
		container.add_child(border)

		# Performer block
		var base := ColorRect.new()
		base.color = BASE_COLORS[i]
		base.size = Vector2(PERF_W, PERF_H)
		base.position = Vector2(-PERF_W / 2.0, -PERF_H / 2.0)
		base.z_index = 1
		container.add_child(base)

		# Number label
		var lbl := Label.new()
		lbl.text = str(i + 1)
		if _pixel_font:
			lbl.add_theme_font_override("font", _pixel_font)
		lbl.add_theme_font_size_override("font_size", 38)
		lbl.add_theme_color_override("font_color", Color(1.0, 0.95, 0.8, 0.9))
		lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
		lbl.add_theme_constant_override("outline_size", 4)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.size = Vector2(PERF_W, PERF_H)
		lbl.position = Vector2(-PERF_W / 2.0, -PERF_H / 2.0)
		lbl.z_index = 2
		container.add_child(lbl)

		_performers.append({
			"container": container,
			"base_rect": base,
			"glow_rect": glow,
			"num_label": lbl,
			"origin_y": origin_y,
		})


func _build_labels() -> void:
	_status_label = Label.new()
	if _pixel_font:
		_status_label.add_theme_font_override("font", _pixel_font)
	_status_label.add_theme_font_size_override("font_size", 30)
	_status_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))
	_status_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_status_label.add_theme_constant_override("outline_size", 4)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.size = Vector2(400, 40)
	_status_label.position = Vector2(-200, -170)
	_status_label.text = ""
	add_child(_status_label)

	_round_label = Label.new()
	if _pixel_font:
		_round_label.add_theme_font_override("font", _pixel_font)
	_round_label.add_theme_font_size_override("font_size", 22)
	_round_label.add_theme_color_override("font_color", Color(0.7, 0.65, 0.9))
	_round_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_round_label.add_theme_constant_override("outline_size", 3)
	_round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_round_label.size = Vector2(200, 30)
	_round_label.position = Vector2(-100, -135)
	_round_label.text = ""
	add_child(_round_label)


# ══════════════════════════════════════════════════════════════
#  SEQUENCE GENERATION
# ══════════════════════════════════════════════════════════════

func _generate_sequence() -> void:
	_sequence.clear()
	for _i in range(TOTAL_ROUNDS):
		_sequence.append(randi() % PERFORMER_COUNT)


# ══════════════════════════════════════════════════════════════
#  ROUND FLOW
# ══════════════════════════════════════════════════════════════

func _start_round() -> void:
	_update_round_label()
	_play_sequence()


func _play_sequence() -> void:
	_phase = Phase.SHOWING
	if _status_label:
		_status_label.text = "Watch..."

	await get_tree().create_timer(PRE_SEQUENCE_DELAY).timeout
	if game_over:
		return

	var length: int = _current_round + 1
	for i in range(length):
		if game_over:
			return
		_activate_performer(_sequence[i])
		await get_tree().create_timer(NOTE_SHOW_DURATION).timeout
		if game_over:
			return
		_deactivate_performer(_sequence[i])
		if i < length - 1:
			await get_tree().create_timer(NOTE_GAP).timeout
			if game_over:
				return

	await get_tree().create_timer(POST_SEQUENCE_DELAY).timeout
	if game_over:
		return

	_phase = Phase.INPUT
	_input_index = 0
	if _status_label:
		_status_label.text = "Your turn!"


func _advance_round() -> void:
	_phase = Phase.TRANSITION
	_current_round += 1

	if _current_round >= TOTAL_ROUNDS:
		_win()
		return

	if _status_label:
		_status_label.text = "Correct!"
	_play_success_sound()

	await get_tree().create_timer(BETWEEN_ROUND_DELAY).timeout
	if game_over:
		return

	_start_round()


# ══════════════════════════════════════════════════════════════
#  PERFORMER ACTIVATION (visual feedback + sound hooks)
# ══════════════════════════════════════════════════════════════

func _activate_performer(index: int) -> void:
	var p: Dictionary = _performers[index]
	var container: Node2D = p["container"]
	var base: ColorRect = p["base_rect"]
	var glow: ColorRect = p["glow_rect"]

	base.color = BRIGHT_COLORS[index]
	glow.visible = true

	var tw := create_tween().set_parallel(true)
	tw.tween_property(container, "scale", Vector2(1.1, 1.1), 0.08).set_ease(Tween.EASE_OUT)
	tw.tween_property(container, "position:y", p["origin_y"] - 10.0, 0.08).set_ease(Tween.EASE_OUT)

	_play_performer_sound(index)


func _deactivate_performer(index: int) -> void:
	var p: Dictionary = _performers[index]
	var container: Node2D = p["container"]
	var base: ColorRect = p["base_rect"]
	var glow: ColorRect = p["glow_rect"]

	base.color = BASE_COLORS[index]
	glow.visible = false

	var tw := create_tween().set_parallel(true)
	tw.tween_property(container, "scale", Vector2.ONE, 0.1).set_ease(Tween.EASE_IN)
	tw.tween_property(container, "position:y", p["origin_y"], 0.1).set_ease(Tween.EASE_IN)


func _flash_performer(index: int) -> void:
	## Brief non-blocking activation for player-input feedback.
	var p: Dictionary = _performers[index]
	var container: Node2D = p["container"]
	var base: ColorRect = p["base_rect"]
	var glow: ColorRect = p["glow_rect"]

	base.color = BRIGHT_COLORS[index]
	glow.visible = true
	container.scale = Vector2(1.08, 1.08)
	container.position.y = p["origin_y"] - 6.0

	_play_performer_sound(index)

	var tw := create_tween()
	tw.tween_interval(PLAYER_FLASH_DURATION)
	tw.tween_callback(func():
		base.color = BASE_COLORS[index]
		glow.visible = false
		container.scale = Vector2.ONE
		container.position.y = p["origin_y"]
	)


# ── SOUND PLACEHOLDERS ──
# Add AudioStreamPlayer children or load samples here.
# Each performer could map to a unique musical note (e.g. C4, E4, G4, B4).

func _play_performer_sound(_index: int) -> void:
	pass

func _play_success_sound() -> void:
	pass

func _play_fail_sound() -> void:
	pass

func _play_win_fanfare() -> void:
	pass


# ══════════════════════════════════════════════════════════════
#  INPUT
# ══════════════════════════════════════════════════════════════

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.keycode == KEY_R and event.pressed:
		handle_continue()

	if game_over or _phase != Phase.INPUT:
		return

	# Keyboard: keys 1–4
	if event is InputEventKey and event.pressed and not event.echo:
		var idx := -1
		match event.keycode:
			KEY_1: idx = 0
			KEY_2: idx = 1
			KEY_3: idx = 2
			KEY_4: idx = 3
		if idx >= 0:
			_handle_player_input(idx)
			return

	# Mouse click on a performer
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var world_pos := get_global_mouse_position()
		for i in range(PERFORMER_COUNT):
			var c: Node2D = _performers[i]["container"]
			var rect := Rect2(
				c.position.x - PERF_W / 2.0,
				c.position.y - PERF_H / 2.0,
				PERF_W, PERF_H
			)
			if rect.has_point(world_pos):
				_handle_player_input(i)
				return


func _handle_player_input(index: int) -> void:
	if _phase != Phase.INPUT:
		return

	_flash_performer(index)

	var expected: int = _sequence[_input_index]
	if index != expected:
		_lose()
		return

	_input_index += 1
	if _input_index >= _current_round + 1:
		_advance_round()


# ══════════════════════════════════════════════════════════════
#  WIN / LOSE / TIMEOUT / CONTINUE  (matches project conventions)
# ══════════════════════════════════════════════════════════════

func _win() -> void:
	_timer_active = false
	game_over = true
	player_won = true
	_phase = Phase.WON
	if _status_label:
		_status_label.text = ""
	if _round_label:
		_round_label.text = ""
	_play_win_fanfare()

	var ui := get_node_or_null("UI")
	if ui and ui.has_method("show_win"):
		ui.show_win()


func _lose() -> void:
	game_over = true
	player_won = false
	_phase = Phase.LOST
	if _status_label:
		_status_label.text = "Wrong note!"
	_play_fail_sound()

	while App.get_lives() > 0:
		App.lose_life()

	var ui := get_node_or_null("UI")
	if ui and ui.has_method("show_game_over"):
		ui.show_game_over(true)


func _on_timeout() -> void:
	_timer_active = false
	if _has_returned:
		return
	_has_returned = true
	print("[Minigame:ConjurersChorus] Time's up! Returning to map.")
	game_over = true
	player_won = false
	_phase = Phase.LOST
	App.minigame_time_remaining = -1.0
	App.reset_lives()
	App.pending_minigame_reward.clear()
	App.on_minigame_completed()
	_return_to_map()


func handle_continue() -> void:
	if not game_over or _has_returned:
		return
	_has_returned = true

	if player_won:
		App.minigame_time_remaining = -1.0
		App.add_card_from_pending_reward()
		App.on_minigame_completed()
		_return_to_map()
	else:
		App.minigame_time_remaining = -1.0
		App.reset_lives()
		App.pending_minigame_reward.clear()
		App.pending_bonus_reward.clear()
		App.region_bonus_active = false
		App.on_minigame_completed()
		_return_to_map()


func _return_to_map() -> void:
	_stop_chorus_music()
	App.play_main_music()
	App.go("res://scenes/ui/game_intro.tscn")


func _update_round_label() -> void:
	if _round_label:
		_round_label.text = "Round %d / %d" % [_current_round + 1, TOTAL_ROUNDS]

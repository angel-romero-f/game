extends Node2D

## Cadence — 3-lane rhythm minigame with procedurally randomized lanes.
##
## Every quarter note at 215 BPM, a tap note appears in a random lane.
## The rhythm grid is fixed (same song every run) but lane assignments are
## randomized each time the minigame starts, so button patterns differ.
## Win by hitting >= 75 % of notes.
##
## ─── Timing model ───
##   quarter_note = 60.0 / bpm  (≈0.279 s at 215 BPM)
##   hit_time     = note_index × quarter_note + song_offset
##   _song_clock starts at -intro_duration, reaches 0 when music begins.
##   Notes spawn and scroll using this single unified clock — the 4-second
##   countdown doubles as the visual lead-in so beat-0 notes scroll from
##   the top and arrive at the hit line the instant the music starts.

var game_over: bool = false
var player_won: bool = false
var _has_returned: bool = false


# ══════════════════════════════════════════════════════════════
#  TUNING (exported for editor tweaking)
# ══════════════════════════════════════════════════════════════

@export var bpm: float = 215.0

## Total length of the song audio in seconds.
@export var song_duration: float = 27.0

## Fine-tuning offset — shifts the entire chart vs the audio.
## Positive = notes arrive later; negative = notes arrive earlier.
@export var song_offset: float = 0.0

## Seconds before the end of the song to stop placing notes.
## Prevents notes from landing right at the audio tail.
@export var end_padding: float = 0.0

@export var note_scroll_speed: float = 400.0

## Half-window (seconds) around perfect hit time.
@export var hit_window_secs: float = 0.15

## Minimum accuracy (0–1) required to win.
@export var win_accuracy: float = 0.75

@export var lane_count: int = 3

## Seconds of countdown before the song begins.
@export var intro_duration: float = 4.0


# ══════════════════════════════════════════════════════════════
#  TIMING (derived at runtime)
# ══════════════════════════════════════════════════════════════

## Unified song clock.  Starts at -intro_duration, reaches 0 when the music
## begins.  Notes spawn and position themselves using this single value.
var _song_clock: float = 0.0

var _scroll_distance: float
var _travel_time: float


# ══════════════════════════════════════════════════════════════
#  LAYOUT
# ══════════════════════════════════════════════════════════════

const LANE_WIDTH: float = 90.0
const LANE_GAP: float = 8.0
const LANE_TOP_Y: float = -280.0
const HIT_LINE_Y: float = 200.0
const NOTE_SIZE: float = 36.0

var _total_lane_width: float
var _lane_area_left: float


# ══════════════════════════════════════════════════════════════
#  GAME STATE
# ══════════════════════════════════════════════════════════════

enum Phase { INTRO, PLAYING, RESULTS }
var _phase: int = Phase.INTRO


# ══════════════════════════════════════════════════════════════
#  SCORING
# ══════════════════════════════════════════════════════════════

var _total_notes: int = 0
var _hits: int = 0
var _misses: int = 0


# ══════════════════════════════════════════════════════════════
#  NOTES
# ══════════════════════════════════════════════════════════════

## Runtime note list.  Each entry:
##   { "lane": int, "hit_time": float,
##     "node": Node2D or null, "state": &"pending" / &"active" / &"hit" / &"missed" }
var _notes: Array = []
var _next_spawn_index: int = 0


# ══════════════════════════════════════════════════════════════
#  VISUAL NODES (built at runtime)
# ══════════════════════════════════════════════════════════════

var _lane_bg_rects: Array = []
var _hit_line_rect: ColorRect = null
var _lane_flash_rects: Array = []
var _key_labels: Array = []
var _intro_label: Label = null
var _countdown_label: Label = null
var _pixel_font: Font = null


# ══════════════════════════════════════════════════════════════
#  COLORS
# ══════════════════════════════════════════════════════════════

const LANE_COLORS: Array = [
	Color(0.65, 0.16, 0.16),   # lane 0 — red
	Color(0.16, 0.32, 0.65),   # lane 1 — blue
	Color(0.14, 0.52, 0.22),   # lane 2 — green
]
const NOTE_COLORS: Array = [
	Color(1.0, 0.4, 0.4),      # lane 0
	Color(0.45, 0.68, 1.0),    # lane 1
	Color(0.4, 0.92, 0.5),     # lane 2
]
const LANE_BG_COLOR := Color(0.06, 0.05, 0.1, 0.9)
const HIT_LINE_COLOR := Color(0.92, 0.82, 0.5, 0.8)
const FLASH_COLOR := Color(1.0, 0.95, 0.7, 0.35)


# ══════════════════════════════════════════════════════════════
#  AUDIO
# ══════════════════════════════════════════════════════════════

## Hook: for tighter sync, replace delta accumulation with:
##   _song_clock = _music_player.get_playback_position() + song_offset
var _music_player: AudioStreamPlayer = null


# ══════════════════════════════════════════════════════════════
#  LIFECYCLE
# ══════════════════════════════════════════════════════════════

func _ready() -> void:
	_pixel_font = load("res://fonts/m5x7.ttf") as Font

	App.stop_gameplay_music()

	_music_player = get_node_or_null("CadenceMusic") as AudioStreamPlayer
	if _music_player:
		_music_player.bus = "Music"

	App.reset_lives()
	App.minigame_time_remaining = -1.0

	_total_lane_width = lane_count * LANE_WIDTH + (lane_count - 1) * LANE_GAP
	_lane_area_left = -_total_lane_width / 2.0
	_scroll_distance = HIT_LINE_Y - LANE_TOP_Y
	_travel_time = _scroll_distance / note_scroll_speed

	_generate_chart()
	_build_visuals()
	_build_intro_overlay()

	_song_clock = -intro_duration

	_phase = Phase.INTRO
	print("[Minigame:Cadence] Starting (BPM %.0f, %d notes, %.1fs song, ~%.1fs total)" % [
		bpm, _total_notes, song_duration, intro_duration + song_duration])


func _process(delta: float) -> void:
	if _phase == Phase.RESULTS:
		return
	_song_clock += delta
	match _phase:
		Phase.INTRO:
			_process_intro()
		Phase.PLAYING:
			_process_playing()


# ══════════════════════════════════════════════════════════════
#  INTRO / COUNTDOWN
# ══════════════════════════════════════════════════════════════

func _process_intro() -> void:
	# Notes spawn and scroll during the countdown so beat-0 notes arrive at
	# the hit line exactly when the clock reaches 0 and the music starts.
	_spawn_pending_notes()
	_update_note_positions()

	var countdown := -_song_clock
	if _countdown_label:
		if countdown > 3.0:
			_countdown_label.text = ""
		elif countdown > 2.0:
			_countdown_label.text = "3"
		elif countdown > 1.0:
			_countdown_label.text = "2"
		else:
			_countdown_label.text = "1"

	if _song_clock >= 0.0:
		_start_song()


func _start_song() -> void:
	_phase = Phase.PLAYING

	if _intro_label:
		_intro_label.visible = false
	if _countdown_label:
		_countdown_label.visible = false

	if _music_player and _music_player.stream:
		_music_player.play()

	var ui := get_node_or_null("UI")
	if ui and ui.has_method("on_song_started"):
		ui.on_song_started()
	if ui and ui.has_method("update_timer_display"):
		ui.update_timer_display(song_duration)
	if ui and ui.has_method("update_accuracy_display"):
		ui.update_accuracy_display(_hits, _total_notes)


# ══════════════════════════════════════════════════════════════
#  GAMEPLAY
# ══════════════════════════════════════════════════════════════

func _process_playing() -> void:
	_spawn_pending_notes()
	_update_note_positions()
	_check_missed_notes()

	var ui := get_node_or_null("UI")
	if ui and ui.has_method("update_timer_display"):
		ui.update_timer_display(maxf(0.0, song_duration - _song_clock))
	if ui and ui.has_method("update_accuracy_display"):
		ui.update_accuracy_display(_hits, _total_notes)

	var all_done := _song_clock >= song_duration and _all_notes_resolved()
	var hard_cap := _song_clock >= song_duration + 2.0
	if all_done or hard_cap:
		_end_song()


func _spawn_pending_notes() -> void:
	while _next_spawn_index < _notes.size():
		var note: Dictionary = _notes[_next_spawn_index]
		var spawn_time: float = note["hit_time"] - _travel_time
		if _song_clock < spawn_time:
			break
		_spawn_note_visual(note)
		note["state"] = &"active"
		_next_spawn_index += 1


func _spawn_note_visual(note: Dictionary) -> void:
	var lane: int = note["lane"]
	var cx: float = _lane_center_x(lane)
	var half := NOTE_SIZE / 2.0
	var inset := NOTE_SIZE * 0.25

	var node := Node2D.new()
	node.position = Vector2(cx, LANE_TOP_Y)
	node.z_index = 5

	var rect := ColorRect.new()
	rect.color = NOTE_COLORS[lane]
	rect.size = Vector2(NOTE_SIZE, NOTE_SIZE)
	rect.position = Vector2(-half, -half)
	node.add_child(rect)

	var inner := ColorRect.new()
	inner.color = Color(1.0, 1.0, 1.0, 0.25)
	inner.size = Vector2(NOTE_SIZE - inset * 2, NOTE_SIZE - inset * 2)
	inner.position = Vector2(-half + inset, -half + inset)
	node.add_child(inner)

	add_child(node)
	note["node"] = node


func _update_note_positions() -> void:
	for note in _notes:
		var s = note["state"]
		if (s == &"active") and note.has("node") and is_instance_valid(note["node"]):
			var time_until_hit: float = note["hit_time"] - _song_clock
			note["node"].position.y = HIT_LINE_Y - time_until_hit * note_scroll_speed


func _check_missed_notes() -> void:
	for note in _notes:
		if note["state"] != &"active":
			continue
		if _song_clock - note["hit_time"] > hit_window_secs:
			note["state"] = &"missed"
			_misses += 1
			_fade_note(note)


func _all_notes_resolved() -> bool:
	for note in _notes:
		var s = note["state"]
		if s == &"pending" or s == &"active":
			return false
	return true


func _end_song() -> void:
	if _phase == Phase.RESULTS:
		return
	_phase = Phase.RESULTS
	game_over = true

	if _music_player:
		_music_player.stop()

	for note in _notes:
		var s = note["state"]
		if s == &"pending" or s == &"active":
			note["state"] = &"missed"
			_misses += 1

	var accuracy: float = 0.0
	if _total_notes > 0:
		accuracy = float(_hits) / float(_total_notes)

	player_won = accuracy >= win_accuracy

	print("[Minigame:Cadence] Song ended — %d/%d hits (%.0f%%). %s" % [
		_hits, _total_notes, accuracy * 100.0, "WIN" if player_won else "LOSE"])

	var ui := get_node_or_null("UI")
	if player_won:
		if ui and ui.has_method("show_win"):
			ui.show_win()
	else:
		while App.get_lives() > 0:
			App.lose_life()
		if ui and ui.has_method("show_game_over"):
			ui.show_game_over(true)


# ══════════════════════════════════════════════════════════════
#  INPUT
# ══════════════════════════════════════════════════════════════

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.keycode == KEY_R and event.pressed:
		handle_continue()

	if game_over or _phase != Phase.PLAYING:
		return

	if not (event is InputEventKey) or event.echo or not event.pressed:
		return

	var lane := -1
	match event.keycode:
		KEY_A, KEY_J: lane = 0
		KEY_S, KEY_K: lane = 1
		KEY_D, KEY_L: lane = 2

	if lane >= 0:
		_handle_lane_press(lane)


func _handle_lane_press(lane: int) -> void:
	_flash_lane(lane)

	var best_note: Dictionary = {}
	var best_diff: float = INF

	for note in _notes:
		if note["state"] != &"active":
			continue
		if note["lane"] != lane:
			continue
		var diff: float = absf(_song_clock - note["hit_time"])
		if diff <= hit_window_secs and diff < best_diff:
			best_note = note
			best_diff = diff

	if not best_note.is_empty():
		best_note["state"] = &"hit"
		_hits += 1
		_pop_note(best_note)


# ══════════════════════════════════════════════════════════════
#  VISUAL EFFECTS
# ══════════════════════════════════════════════════════════════

func _flash_lane(lane: int) -> void:
	if lane < 0 or lane >= _lane_flash_rects.size():
		return
	var flash: ColorRect = _lane_flash_rects[lane]
	flash.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_property(flash, "modulate:a", 0.0, 0.12)


func _pop_note(note: Dictionary) -> void:
	if not note.has("node") or not is_instance_valid(note["node"]):
		return
	var node: Node2D = note["node"]
	var tw := create_tween().set_parallel(true)
	tw.tween_property(node, "scale", Vector2(1.6, 1.6), 0.1)
	tw.tween_property(node, "modulate:a", 0.0, 0.12)
	tw.chain().tween_callback(node.queue_free)


func _fade_note(note: Dictionary) -> void:
	if not note.has("node") or not is_instance_valid(note["node"]):
		return
	var node: Node2D = note["node"]
	node.modulate = Color(1, 0.3, 0.3, 0.5)
	var tw := create_tween()
	tw.tween_property(node, "modulate:a", 0.0, 0.25)
	tw.tween_callback(node.queue_free)


# ══════════════════════════════════════════════════════════════
#  VISUAL CONSTRUCTION
# ══════════════════════════════════════════════════════════════

func _build_visuals() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.03, 0.08)
	bg.size = Vector2(1200, 700)
	bg.position = Vector2(-600, -350)
	bg.z_index = -10
	add_child(bg)

	var border := ColorRect.new()
	border.color = Color(0.35, 0.28, 0.18, 0.45)
	border.size = Vector2(_total_lane_width + 14, _scroll_distance + 70)
	border.position = Vector2(_lane_area_left - 7, LANE_TOP_Y - 12)
	border.z_index = -2
	add_child(border)

	for i in range(lane_count):
		var lane_x: float = _lane_area_left + i * (LANE_WIDTH + LANE_GAP)
		var lane_h: float = _scroll_distance + 46

		var lane_bg := ColorRect.new()
		lane_bg.color = LANE_BG_COLOR
		lane_bg.size = Vector2(LANE_WIDTH, lane_h)
		lane_bg.position = Vector2(lane_x, LANE_TOP_Y - 6)
		lane_bg.z_index = -1
		add_child(lane_bg)
		_lane_bg_rects.append(lane_bg)

		var lane_tint := ColorRect.new()
		lane_tint.color = LANE_COLORS[i].lerp(Color.BLACK, 0.6)
		lane_tint.color.a = 0.2
		lane_tint.size = Vector2(LANE_WIDTH, lane_h)
		lane_tint.position = Vector2(lane_x, LANE_TOP_Y - 6)
		lane_tint.z_index = 0
		add_child(lane_tint)

		var flash := ColorRect.new()
		flash.color = FLASH_COLOR
		flash.size = Vector2(LANE_WIDTH, lane_h)
		flash.position = Vector2(lane_x, LANE_TOP_Y - 6)
		flash.z_index = 3
		flash.modulate.a = 0.0
		add_child(flash)
		_lane_flash_rects.append(flash)

	var zone_height: float = hit_window_secs * note_scroll_speed * 2.0
	var hit_zone := ColorRect.new()
	hit_zone.color = Color(0.92, 0.82, 0.45, 0.07)
	hit_zone.size = Vector2(_total_lane_width, zone_height)
	hit_zone.position = Vector2(_lane_area_left, HIT_LINE_Y - zone_height / 2.0)
	hit_zone.z_index = 1
	add_child(hit_zone)

	_hit_line_rect = ColorRect.new()
	_hit_line_rect.color = HIT_LINE_COLOR
	_hit_line_rect.size = Vector2(_total_lane_width + 14, 4)
	_hit_line_rect.position = Vector2(_lane_area_left - 7, HIT_LINE_Y - 2)
	_hit_line_rect.z_index = 4
	add_child(_hit_line_rect)

	var key_sets := [["A", "S", "D"], ["J", "K", "L"]]
	for i in range(lane_count):
		var cx: float = _lane_center_x(i)
		var lbl := Label.new()
		lbl.text = "%s / %s" % [key_sets[0][i], key_sets[1][i]]
		if _pixel_font:
			lbl.add_theme_font_override("font", _pixel_font)
		lbl.add_theme_font_size_override("font_size", 24)
		lbl.add_theme_color_override("font_color", LANE_COLORS[i].lerp(Color.WHITE, 0.55))
		lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		lbl.add_theme_constant_override("outline_size", 3)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.size = Vector2(LANE_WIDTH, 30)
		lbl.position = Vector2(cx - LANE_WIDTH / 2.0, HIT_LINE_Y + 14)
		lbl.z_index = 4
		add_child(lbl)
		_key_labels.append(lbl)

	var title_lbl := Label.new()
	title_lbl.text = "~ Cadence ~"
	if _pixel_font:
		title_lbl.add_theme_font_override("font", _pixel_font)
	title_lbl.add_theme_font_size_override("font_size", 20)
	title_lbl.add_theme_color_override("font_color", Color(0.6, 0.55, 0.4, 0.5))
	title_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.4))
	title_lbl.add_theme_constant_override("outline_size", 2)
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.size = Vector2(300, 30)
	title_lbl.position = Vector2(-150, LANE_TOP_Y - 40)
	title_lbl.z_index = 4
	add_child(title_lbl)


func _build_intro_overlay() -> void:
	_intro_label = Label.new()
	_intro_label.text = "~ Cadence ~\nHit the notes as they cross the line!\nA / S / D   or   J / K / L"
	if _pixel_font:
		_intro_label.add_theme_font_override("font", _pixel_font)
	_intro_label.add_theme_font_size_override("font_size", 32)
	_intro_label.add_theme_color_override("font_color", Color(0.95, 0.88, 0.6))
	_intro_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_intro_label.add_theme_constant_override("outline_size", 5)
	_intro_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_intro_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_intro_label.size = Vector2(520, 140)
	_intro_label.position = Vector2(-260, -180)
	_intro_label.z_index = 10
	add_child(_intro_label)

	_countdown_label = Label.new()
	_countdown_label.text = ""
	if _pixel_font:
		_countdown_label.add_theme_font_override("font", _pixel_font)
	_countdown_label.add_theme_font_size_override("font_size", 80)
	_countdown_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.4))
	_countdown_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_countdown_label.add_theme_constant_override("outline_size", 8)
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_countdown_label.size = Vector2(200, 120)
	_countdown_label.position = Vector2(-100, -20)
	_countdown_label.z_index = 10
	add_child(_countdown_label)


# ══════════════════════════════════════════════════════════════
#  CHART GENERATION
# ══════════════════════════════════════════════════════════════

## Builds the note list procedurally.  A note is placed on every quarter
## beat from song_offset up to (song_duration - end_padding).  The rhythm
## grid is fixed; only the lane assignment (0, 1, or 2) is randomized
## each run, giving the same song feel with different button patterns.
func _generate_chart() -> void:
	_notes.clear()
	_next_spawn_index = 0
	_hits = 0
	_misses = 0

	var quarter: float = 60.0 / bpm
	var t: float = song_offset

	while t <= song_duration - end_padding:
		_notes.append({
			"lane": randi_range(0, 2),
			"hit_time": t,
			"state": &"pending",
		})
		t += quarter

	_total_notes = _notes.size()


# ══════════════════════════════════════════════════════════════
#  HELPERS
# ══════════════════════════════════════════════════════════════

func _lane_center_x(lane: int) -> float:
	return _lane_area_left + lane * (LANE_WIDTH + LANE_GAP) + LANE_WIDTH / 2.0


# ══════════════════════════════════════════════════════════════
#  WIN / LOSE / CONTINUE  (matches project conventions)
# ══════════════════════════════════════════════════════════════

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
	App.go("res://scenes/ui/game_intro.tscn")

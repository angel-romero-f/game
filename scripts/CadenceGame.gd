extends Node2D

## Cadence — 3-lane chart-driven rhythm minigame.
##
## Notes scroll downward toward a hit line.  Press J/K/L (or A/S/D) to hit
## tap notes; for hold notes, press all required lanes and sustain until the
## bar passes through.  Win by hitting >= 75 % of chart events.
##
## ─── Timing model ───
##   seconds_per_beat  = 60.0 / bpm
##   hit_time          = beat × seconds_per_beat + song_offset
##   end_time          = (beat + duration_beats) × seconds_per_beat + song_offset
##   Notes with duration_beats >= HOLD_THRESHOLD are treated as hold notes.
##
## ─── Note types ───
##   Tap   — short duration (<1.5 beats), one or more lanes.  Press to hit.
##   Hold  — long duration (>=1.5 beats), one or more lanes.  Press within the
##           hit window, then keep all lanes held until end_time.
##   Chord — any note with multiple lanes (tap or hold).  All lanes must be
##           pressed (and held, for holds) simultaneously.

var game_over: bool = false
var player_won: bool = false
var _has_returned: bool = false


# ══════════════════════════════════════════════════════════════
#  CHART DATA
# ══════════════════════════════════════════════════════════════

## Duration (in beats) at or above which a note becomes a hold.
const HOLD_THRESHOLD: float = 1.5

## Beat chart for cadence_1.mp3 — 110 BPM, 3/4 time, 16 measures.
## Lanes: 0 = J/A, 1 = K/S, 2 = L/D.
const CADENCE_CHART: Array = [
	# ── PART 1 ──────────────────────────────────────────────

	# Measure 1: K J L K L K (eighth notes)
	{"beat": 0.0,  "lanes": [1], "duration_beats": 0.5},
	{"beat": 0.5,  "lanes": [0], "duration_beats": 0.5},
	{"beat": 1.0,  "lanes": [2], "duration_beats": 0.5},
	{"beat": 1.5,  "lanes": [1], "duration_beats": 0.5},
	{"beat": 2.0,  "lanes": [2], "duration_beats": 0.5},
	{"beat": 2.5,  "lanes": [1], "duration_beats": 0.5},

	# Measure 2: JKL held (dotted half = 3 beats)
	{"beat": 3.0,  "lanes": [0, 1, 2], "duration_beats": 3.0},

	# Measure 3: L K J K L K (eighth notes)
	{"beat": 6.0,  "lanes": [2], "duration_beats": 0.5},
	{"beat": 6.5,  "lanes": [1], "duration_beats": 0.5},
	{"beat": 7.0,  "lanes": [0], "duration_beats": 0.5},
	{"beat": 7.5,  "lanes": [1], "duration_beats": 0.5},
	{"beat": 8.0,  "lanes": [2], "duration_beats": 0.5},
	{"beat": 8.5,  "lanes": [1], "duration_beats": 0.5},

	# Measure 4: JKL held (half = 2 beats), then 1 beat rest
	{"beat": 9.0,  "lanes": [0, 1, 2], "duration_beats": 2.0},

	# Measure 5: L K L K L K (eighth notes)
	{"beat": 12.0, "lanes": [2], "duration_beats": 0.5},
	{"beat": 12.5, "lanes": [1], "duration_beats": 0.5},
	{"beat": 13.0, "lanes": [2], "duration_beats": 0.5},
	{"beat": 13.5, "lanes": [1], "duration_beats": 0.5},
	{"beat": 14.0, "lanes": [2], "duration_beats": 0.5},
	{"beat": 14.5, "lanes": [1], "duration_beats": 0.5},

	# Measure 6: JKL held (dotted half = 3 beats)
	{"beat": 15.0, "lanes": [0, 1, 2], "duration_beats": 3.0},

	# Measure 7: K J K J K J (eighth notes)
	{"beat": 18.0, "lanes": [1], "duration_beats": 0.5},
	{"beat": 18.5, "lanes": [0], "duration_beats": 0.5},
	{"beat": 19.0, "lanes": [1], "duration_beats": 0.5},
	{"beat": 19.5, "lanes": [0], "duration_beats": 0.5},
	{"beat": 20.0, "lanes": [1], "duration_beats": 0.5},
	{"beat": 20.5, "lanes": [0], "duration_beats": 0.5},

	# Measure 8: JKL held (half = 2 beats), then 1 beat rest
	{"beat": 21.0, "lanes": [0, 1, 2], "duration_beats": 2.0},

	# ── PART 2 ──────────────────────────────────────────────

	# Measure 1: J K K L K J J K L (triplet eighths)
	{"beat": 24.0,               "lanes": [0], "duration_beats": 1.0 / 3.0},
	{"beat": 24.0 + 1.0 / 3.0,  "lanes": [1], "duration_beats": 1.0 / 3.0},
	{"beat": 24.0 + 2.0 / 3.0,  "lanes": [1], "duration_beats": 1.0 / 3.0},
	{"beat": 25.0,               "lanes": [2], "duration_beats": 1.0 / 3.0},
	{"beat": 25.0 + 1.0 / 3.0,  "lanes": [1], "duration_beats": 1.0 / 3.0},
	{"beat": 25.0 + 2.0 / 3.0,  "lanes": [0], "duration_beats": 1.0 / 3.0},
	{"beat": 26.0,               "lanes": [0], "duration_beats": 1.0 / 3.0},
	{"beat": 26.0 + 1.0 / 3.0,  "lanes": [1], "duration_beats": 1.0 / 3.0},
	{"beat": 26.0 + 2.0 / 3.0,  "lanes": [2], "duration_beats": 1.0 / 3.0},

	# Measure 2: L K J L K J L K J (triplet eighths)
	{"beat": 27.0,               "lanes": [2], "duration_beats": 1.0 / 3.0},
	{"beat": 27.0 + 1.0 / 3.0,  "lanes": [1], "duration_beats": 1.0 / 3.0},
	{"beat": 27.0 + 2.0 / 3.0,  "lanes": [0], "duration_beats": 1.0 / 3.0},
	{"beat": 28.0,               "lanes": [2], "duration_beats": 1.0 / 3.0},
	{"beat": 28.0 + 1.0 / 3.0,  "lanes": [1], "duration_beats": 1.0 / 3.0},
	{"beat": 28.0 + 2.0 / 3.0,  "lanes": [0], "duration_beats": 1.0 / 3.0},
	{"beat": 29.0,               "lanes": [2], "duration_beats": 1.0 / 3.0},
	{"beat": 29.0 + 1.0 / 3.0,  "lanes": [1], "duration_beats": 1.0 / 3.0},
	{"beat": 29.0 + 2.0 / 3.0,  "lanes": [0], "duration_beats": 1.0 / 3.0},

	# Measure 3: J K K L K J L K J (triplet eighths)
	{"beat": 30.0,               "lanes": [0], "duration_beats": 1.0 / 3.0},
	{"beat": 30.0 + 1.0 / 3.0,  "lanes": [1], "duration_beats": 1.0 / 3.0},
	{"beat": 30.0 + 2.0 / 3.0,  "lanes": [1], "duration_beats": 1.0 / 3.0},
	{"beat": 31.0,               "lanes": [2], "duration_beats": 1.0 / 3.0},
	{"beat": 31.0 + 1.0 / 3.0,  "lanes": [1], "duration_beats": 1.0 / 3.0},
	{"beat": 31.0 + 2.0 / 3.0,  "lanes": [0], "duration_beats": 1.0 / 3.0},
	{"beat": 32.0,               "lanes": [2], "duration_beats": 1.0 / 3.0},
	{"beat": 32.0 + 1.0 / 3.0,  "lanes": [1], "duration_beats": 1.0 / 3.0},
	{"beat": 32.0 + 2.0 / 3.0,  "lanes": [0], "duration_beats": 1.0 / 3.0},

	# Measure 4: JKL held (half = 2 beats), then 1 beat rest
	{"beat": 33.0, "lanes": [0, 1, 2], "duration_beats": 2.0},

	# Measure 5: J K K L K J J K L (triplet eighths)
	{"beat": 36.0,               "lanes": [0], "duration_beats": 1.0 / 3.0},
	{"beat": 36.0 + 1.0 / 3.0,  "lanes": [1], "duration_beats": 1.0 / 3.0},
	{"beat": 36.0 + 2.0 / 3.0,  "lanes": [1], "duration_beats": 1.0 / 3.0},
	{"beat": 37.0,               "lanes": [2], "duration_beats": 1.0 / 3.0},
	{"beat": 37.0 + 1.0 / 3.0,  "lanes": [1], "duration_beats": 1.0 / 3.0},
	{"beat": 37.0 + 2.0 / 3.0,  "lanes": [0], "duration_beats": 1.0 / 3.0},
	{"beat": 38.0,               "lanes": [0], "duration_beats": 1.0 / 3.0},
	{"beat": 38.0 + 1.0 / 3.0,  "lanes": [1], "duration_beats": 1.0 / 3.0},
	{"beat": 38.0 + 2.0 / 3.0,  "lanes": [2], "duration_beats": 1.0 / 3.0},

	# Measure 6: L K J L K J L K J (triplet eighths)
	{"beat": 39.0,               "lanes": [2], "duration_beats": 1.0 / 3.0},
	{"beat": 39.0 + 1.0 / 3.0,  "lanes": [1], "duration_beats": 1.0 / 3.0},
	{"beat": 39.0 + 2.0 / 3.0,  "lanes": [0], "duration_beats": 1.0 / 3.0},
	{"beat": 40.0,               "lanes": [2], "duration_beats": 1.0 / 3.0},
	{"beat": 40.0 + 1.0 / 3.0,  "lanes": [1], "duration_beats": 1.0 / 3.0},
	{"beat": 40.0 + 2.0 / 3.0,  "lanes": [0], "duration_beats": 1.0 / 3.0},
	{"beat": 41.0,               "lanes": [2], "duration_beats": 1.0 / 3.0},
	{"beat": 41.0 + 1.0 / 3.0,  "lanes": [1], "duration_beats": 1.0 / 3.0},
	{"beat": 41.0 + 2.0 / 3.0,  "lanes": [0], "duration_beats": 1.0 / 3.0},

	# Measure 7: K J J K J J K J J (triplet eighths)
	{"beat": 42.0,               "lanes": [1], "duration_beats": 1.0 / 3.0},
	{"beat": 42.0 + 1.0 / 3.0,  "lanes": [0], "duration_beats": 1.0 / 3.0},
	{"beat": 42.0 + 2.0 / 3.0,  "lanes": [0], "duration_beats": 1.0 / 3.0},
	{"beat": 43.0,               "lanes": [1], "duration_beats": 1.0 / 3.0},
	{"beat": 43.0 + 1.0 / 3.0,  "lanes": [0], "duration_beats": 1.0 / 3.0},
	{"beat": 43.0 + 2.0 / 3.0,  "lanes": [0], "duration_beats": 1.0 / 3.0},
	{"beat": 44.0,               "lanes": [1], "duration_beats": 1.0 / 3.0},
	{"beat": 44.0 + 1.0 / 3.0,  "lanes": [0], "duration_beats": 1.0 / 3.0},
	{"beat": 44.0 + 2.0 / 3.0,  "lanes": [0], "duration_beats": 1.0 / 3.0},

	# Measure 8: JKL held (half = 2 beats), then 1 beat rest
	{"beat": 45.0, "lanes": [0, 1, 2], "duration_beats": 2.0},
]


# ══════════════════════════════════════════════════════════════
#  TUNING (exported for editor tweaking)
# ══════════════════════════════════════════════════════════════

@export var bpm: float = 110.0

## Fine-tuning offset (seconds) to align the chart with the audio file.
## Positive = notes appear later vs the music (use if notes feel early).
## Negative = notes appear earlier vs the music (use if notes feel late).
## Keep near 0.0 for this chart; the lead-in is handled automatically.
@export var song_offset: float = 0.0

@export var note_scroll_speed: float = 400.0

## Half-window (seconds) around perfect hit time for tap/hold start.
@export var hit_window_secs: float = 0.15

## Minimum accuracy (0–1) required to win.
@export var win_accuracy: float = 0.75

@export var lane_count: int = 3

## Seconds of countdown before the song begins.
@export var intro_duration: float = 4.0


# ══════════════════════════════════════════════════════════════
#  TIMING (derived at runtime)
# ══════════════════════════════════════════════════════════════

var _seconds_per_beat: float
var _song_duration: float   # seconds of actual gameplay (clock 0 → _song_duration)

## Unified song clock.  Starts at -intro_duration when the scene loads and
## counts upward continuously.  Clock = 0 is the moment the music begins and
## beat 0 of the chart hits the hit line.  Notes use this clock for all
## spawn, position, hit, and miss calculations — no separate intro counter.
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
const HOLD_BODY_WIDTH: float = 50.0

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

## Runtime notes built from CADENCE_CHART.  Each entry adds:
##   hit_time, end_time, is_hold, state (&"pending"/&"active"/&"holding"/
##   &"hit"/&"missed"), node (Node2D visual root, or null).
var _notes: Array = []
var _next_spawn_index: int = 0


# ══════════════════════════════════════════════════════════════
#  INPUT
# ══════════════════════════════════════════════════════════════

var _lanes_held: Array = [false, false, false]


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
const HOLD_BODY_ALPHA: float = 0.4
const HOLD_ACTIVE_TINT := Color(1.3, 1.15, 0.7, 1.0)


# ══════════════════════════════════════════════════════════════
#  AUDIO
# ══════════════════════════════════════════════════════════════

## Hook: for tighter sync, replace delta accumulation with:
##   _song_clock = _music_player.get_playback_position() + song_offset
## This eliminates drift between game time and the audio stream.
var _music_player: AudioStreamPlayer = null


# ══════════════════════════════════════════════════════════════
#  LIFECYCLE
# ══════════════════════════════════════════════════════════════

func _ready() -> void:
	_pixel_font = load("res://fonts/m5x7.ttf") as Font

	App.stop_main_music()

	_music_player = get_node_or_null("CadenceMusic") as AudioStreamPlayer
	if _music_player:
		_music_player.bus = "Music"

	App.reset_lives()
	App.minigame_time_remaining = -1.0

	_seconds_per_beat = 60.0 / bpm
	_total_lane_width = lane_count * LANE_WIDTH + (lane_count - 1) * LANE_GAP
	_lane_area_left = -_total_lane_width / 2.0
	_scroll_distance = HIT_LINE_Y - LANE_TOP_Y
	_travel_time = _scroll_distance / note_scroll_speed

	_prepare_notes()
	_build_visuals()
	_build_intro_overlay()

	# Seed the clock at -intro_duration so it reaches 0 exactly when the
	# countdown finishes and the music starts.  Notes use this same clock, so
	# beat-0 notes begin scrolling from the top during the countdown and arrive
	# at the hit line the moment the song begins.
	_song_clock = -intro_duration

	_phase = Phase.INTRO
	print("[Minigame:Cadence] Starting (BPM %.0f, %d notes, %.1fs chart, ~%.1fs total)" % [
		bpm, _total_notes, _song_duration, intro_duration + _song_duration])


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
	# Notes scroll during the countdown — the 4-second intro is the lead-in.
	# beat-0 notes spawn at clock = -_travel_time (≈2.8 s into the intro) and
	# arrive at the hit line exactly when the clock reaches 0 and music starts.
	_spawn_pending_notes()
	_update_note_positions()

	# _song_clock is negative during intro; -_song_clock = seconds until start
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

	# Clock is now 0 — start music so beat 0 of the audio aligns with the hit line.
	# Hook: replace delta accumulation below with _music_player.get_playback_position()
	# for drift-free sync once the chart is polished.
	if _music_player and _music_player.stream:
		_music_player.play()

	var ui := get_node_or_null("UI")
	if ui and ui.has_method("on_song_started"):
		ui.on_song_started()
	if ui and ui.has_method("update_timer_display"):
		ui.update_timer_display(_song_duration)
	if ui and ui.has_method("update_accuracy_display"):
		ui.update_accuracy_display(_hits, _total_notes)


# ══════════════════════════════════════════════════════════════
#  GAMEPLAY
# ══════════════════════════════════════════════════════════════

func _process_playing() -> void:
	_spawn_pending_notes()
	_update_note_positions()
	_check_missed_notes()
	_check_active_holds()

	var ui := get_node_or_null("UI")
	if ui and ui.has_method("update_timer_display"):
		ui.update_timer_display(maxf(0.0, _song_duration - _song_clock))
	if ui and ui.has_method("update_accuracy_display"):
		ui.update_accuracy_display(_hits, _total_notes)

	var all_done := _song_clock >= _song_duration and _all_notes_resolved()
	var hard_cap := _song_clock >= _song_duration + 2.0
	if all_done or hard_cap:
		_end_song()


func _spawn_pending_notes() -> void:
	while _next_spawn_index < _notes.size():
		var note: Dictionary = _notes[_next_spawn_index]
		var spawn_time: float = note["hit_time"] - _travel_time
		if _song_clock < spawn_time:
			break
		if note["is_hold"]:
			_spawn_hold_visual(note)
		else:
			_spawn_tap_visual(note)
		note["state"] = &"active"
		_next_spawn_index += 1


func _spawn_tap_visual(note: Dictionary) -> void:
	var root := Node2D.new()
	root.position = Vector2(0, LANE_TOP_Y)
	root.z_index = 5
	var half := NOTE_SIZE / 2.0
	var inset := NOTE_SIZE * 0.25

	for lane in note["lanes"]:
		var cx: float = _lane_center_x(lane)
		var rect := ColorRect.new()
		rect.color = NOTE_COLORS[lane]
		rect.size = Vector2(NOTE_SIZE, NOTE_SIZE)
		rect.position = Vector2(cx - half, -half)
		root.add_child(rect)

		var inner := ColorRect.new()
		inner.color = Color(1.0, 1.0, 1.0, 0.25)
		inner.size = Vector2(NOTE_SIZE - inset * 2, NOTE_SIZE - inset * 2)
		inner.position = Vector2(cx - half + inset, -half + inset)
		root.add_child(inner)

	add_child(root)
	note["node"] = root


func _spawn_hold_visual(note: Dictionary) -> void:
	var root := Node2D.new()
	root.position = Vector2(0, LANE_TOP_Y)
	root.z_index = 5
	var half := NOTE_SIZE / 2.0
	var inset := NOTE_SIZE * 0.25
	var bar_height: float = note["duration_beats"] * _seconds_per_beat * note_scroll_speed
	var body_half: float = HOLD_BODY_WIDTH / 2.0

	for lane in note["lanes"]:
		var cx: float = _lane_center_x(lane)

		# Body — semi-transparent bar extending upward from the head
		var body := ColorRect.new()
		var c: Color = NOTE_COLORS[lane]
		body.color = Color(c.r, c.g, c.b, HOLD_BODY_ALPHA)
		body.size = Vector2(HOLD_BODY_WIDTH, bar_height)
		body.position = Vector2(cx - body_half, -bar_height)
		root.add_child(body)

		# Head marker — bright square at the bottom of the bar
		var head := ColorRect.new()
		head.color = NOTE_COLORS[lane]
		head.size = Vector2(NOTE_SIZE, NOTE_SIZE)
		head.position = Vector2(cx - half, -half)
		root.add_child(head)

		var inner := ColorRect.new()
		inner.color = Color(1.0, 1.0, 1.0, 0.3)
		inner.size = Vector2(NOTE_SIZE - inset * 2, NOTE_SIZE - inset * 2)
		inner.position = Vector2(cx - half + inset, -half + inset)
		root.add_child(inner)

	# Horizontal connector for chords (visual cue that all lanes are linked)
	var lanes_arr: Array = note["lanes"]
	if lanes_arr.size() > 1:
		var left_cx: float = _lane_center_x(lanes_arr.min())
		var right_cx: float = _lane_center_x(lanes_arr.max())
		var conn := ColorRect.new()
		conn.color = HIT_LINE_COLOR
		conn.size = Vector2(right_cx - left_cx + NOTE_SIZE, 4)
		conn.position = Vector2(left_cx - half, -2)
		root.add_child(conn)

	add_child(root)
	note["node"] = root


func _update_note_positions() -> void:
	for note in _notes:
		var s = note["state"]
		if (s == &"active" or s == &"holding") and note.has("node") and is_instance_valid(note["node"]):
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


func _check_active_holds() -> void:
	for note in _notes:
		if note["state"] != &"holding":
			continue
		if _song_clock >= note["end_time"]:
			note["state"] = &"hit"
			_hits += 1
			_pop_note(note)


func _all_notes_resolved() -> bool:
	for note in _notes:
		var s = note["state"]
		if s == &"pending" or s == &"active" or s == &"holding":
			return false
	return true


func _end_song() -> void:
	if _phase == Phase.RESULTS:
		return
	_phase = Phase.RESULTS
	game_over = true

	if _music_player:
		_music_player.stop()

	# Force-resolve any stragglers (safety net for the hard-cap path)
	for note in _notes:
		var s = note["state"]
		if s == &"pending" or s == &"active" or s == &"holding":
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

	if not (event is InputEventKey) or event.echo:
		return

	var lane := -1
	match event.keycode:
		KEY_A, KEY_J: lane = 0
		KEY_S, KEY_K: lane = 1
		KEY_D, KEY_L: lane = 2

	if lane < 0:
		return

	if event.pressed:
		_handle_lane_press(lane)
	else:
		_handle_lane_release(lane)


func _handle_lane_press(lane: int) -> void:
	_flash_lane(lane)
	_lanes_held[lane] = true

	# Find the best active note that includes this lane AND has all its
	# required lanes currently held (important for chords).
	var best_note: Dictionary = {}
	var best_diff: float = INF

	for note in _notes:
		if note["state"] != &"active":
			continue
		var lanes: Array = note["lanes"]
		if not lanes.has(lane):
			continue
		var all_held := true
		for l in lanes:
			if not _lanes_held[l]:
				all_held = false
				break
		if not all_held:
			continue
		var diff: float = absf(_song_clock - note["hit_time"])
		if diff <= hit_window_secs and diff < best_diff:
			best_note = note
			best_diff = diff

	if best_note.is_empty():
		return

	if best_note["is_hold"]:
		best_note["state"] = &"holding"
		if best_note.has("node") and is_instance_valid(best_note["node"]):
			best_note["node"].modulate = HOLD_ACTIVE_TINT
	else:
		best_note["state"] = &"hit"
		_hits += 1
		_pop_note(best_note)


func _handle_lane_release(lane: int) -> void:
	# Check whether an alternate key for this lane is still held (J vs A, etc.)
	var alt_held := false
	match lane:
		0: alt_held = Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_J)
		1: alt_held = Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_K)
		2: alt_held = Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_L)
	if alt_held:
		return

	_lanes_held[lane] = false

	for note in _notes:
		if note["state"] != &"holding":
			continue
		var lanes: Array = note["lanes"]
		if not lanes.has(lane):
			continue
		# Grace: if within 50 ms of the hold's end, count as a hit
		if _song_clock >= note["end_time"] - 0.05:
			note["state"] = &"hit"
			_hits += 1
			_pop_note(note)
		else:
			note["state"] = &"missed"
			_misses += 1
			_fade_note(note)


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
	# Full-screen dark background
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.03, 0.08)
	bg.size = Vector2(1200, 700)
	bg.position = Vector2(-600, -350)
	bg.z_index = -10
	add_child(bg)

	# Border around the lane area
	var border := ColorRect.new()
	border.color = Color(0.35, 0.28, 0.18, 0.45)
	border.size = Vector2(_total_lane_width + 14, _scroll_distance + 70)
	border.position = Vector2(_lane_area_left - 7, LANE_TOP_Y - 12)
	border.z_index = -2
	add_child(border)

	# Per-lane backgrounds, tints, and flash overlays
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

	# Hit-window zone highlight
	var zone_height: float = hit_window_secs * note_scroll_speed * 2.0
	var hit_zone := ColorRect.new()
	hit_zone.color = Color(0.92, 0.82, 0.45, 0.07)
	hit_zone.size = Vector2(_total_lane_width, zone_height)
	hit_zone.position = Vector2(_lane_area_left, HIT_LINE_Y - zone_height / 2.0)
	hit_zone.z_index = 1
	add_child(hit_zone)

	# Hit line
	_hit_line_rect = ColorRect.new()
	_hit_line_rect.color = HIT_LINE_COLOR
	_hit_line_rect.size = Vector2(_total_lane_width + 14, 4)
	_hit_line_rect.position = Vector2(_lane_area_left - 7, HIT_LINE_Y - 2)
	_hit_line_rect.z_index = 4
	add_child(_hit_line_rect)

	# Key labels below the hit line
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

	# Title
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
#  CHART PREPARATION
# ══════════════════════════════════════════════════════════════

func _prepare_notes() -> void:
	_notes.clear()
	_next_spawn_index = 0
	_hits = 0
	_misses = 0

	var last_end_beat: float = 0.0

	for entry in CADENCE_CHART:
		var beat: float = float(entry["beat"])
		var lanes: Array = entry["lanes"]
		var dur: float = float(entry["duration_beats"])
		var hit_t: float = beat * _seconds_per_beat + song_offset
		var end_t: float = (beat + dur) * _seconds_per_beat + song_offset

		_notes.append({
			"lanes": lanes,
			"beat": beat,
			"duration_beats": dur,
			"hit_time": hit_t,
			"end_time": end_t,
			"is_hold": dur >= HOLD_THRESHOLD,
			"state": &"pending",
		})

		var end_beat: float = beat + dur
		if end_beat > last_end_beat:
			last_end_beat = end_beat

	_notes.sort_custom(func(a, b): return a["hit_time"] < b["hit_time"])
	_total_notes = _notes.size()

	# Song ends 1 beat after the last event resolves (the final rest beat)
	_song_duration = (last_end_beat + 1.0) * _seconds_per_beat + song_offset


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
	App.play_main_music()
	App.go("res://scenes/ui/game_intro.tscn")

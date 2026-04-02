extends Node2D

## Cadence — 3-lane rhythm minigame.
##
## Notes scroll down toward a hit line. Player presses A/S/D or J/K/L
## to hit notes in the matching lane. One continuous ~25-second performance.
## Win if accuracy (hits / total notes) >= 75%.
##
## No lives or retry mechanic — single pass, binary win/lose outcome.
## Structure supports future real music: swap in AudioStreamPlayer,
## call play() in _start_song(), and author beat-synced charts.

var game_over: bool = false
var player_won: bool = false
var _has_returned: bool = false

# ── TUNING (exported for editor tweaking) ──

## Fallback BPM when the selected chart doesn't specify one.
@export var default_bpm: float = 120.0
## Pixels per second that notes travel downward.
@export var note_scroll_speed: float = 400.0
## Half-window (in seconds) around perfect hit time. A press within
## +/- this many seconds of the target beat counts as a hit.
@export var hit_window_secs: float = 0.15
## Minimum accuracy (0-1) required to win.
@export var win_accuracy: float = 0.75
## Number of lanes.
@export var lane_count: int = 3
## Seconds of intro/countdown before the song starts.
@export var intro_duration: float = 4.0

# ── TIMING (derived at runtime) ──

var _bpm: float
var _seconds_per_beat: float
var _song_duration: float  # seconds, derived from active chart
var _song_elapsed: float = 0.0
var _intro_elapsed: float = 0.0
var _scroll_distance: float
var _travel_time: float

# ── LAYOUT ──

const LANE_WIDTH: float = 90.0
const LANE_GAP: float = 8.0
const LANE_TOP_Y: float = -280.0
const HIT_LINE_Y: float = 200.0
const NOTE_SIZE: float = 36.0

var _total_lane_width: float
var _lane_area_left: float

# ── GAME STATE ──

enum Phase { INTRO, PLAYING, RESULTS }
var _phase: int = Phase.INTRO

# ── SCORING ──

var _total_notes: int = 0
var _hits: int = 0
var _misses: int = 0

# ── NOTES ──
## Runtime note list. Each entry:
## { "lane": int, "beat": float, "hit_time": float,
##   "node": Node2D or null, "state": &"pending" / &"active" / &"hit" / &"missed" }
var _notes: Array = []
var _next_spawn_index: int = 0

# ── VISUAL NODES (built at runtime) ──

var _lane_bg_rects: Array = []
var _hit_line_rect: ColorRect = null
var _lane_flash_rects: Array = []
var _key_labels: Array = []
var _intro_label: Label = null
var _countdown_label: Label = null
var _pixel_font: Font = null

# ── COLORS (medieval / fantasy palette) ──

const LANE_COLORS: Array = [
	Color(0.65, 0.16, 0.16),
	Color(0.16, 0.32, 0.65),
	Color(0.14, 0.52, 0.22),
]
const NOTE_COLORS: Array = [
	Color(1.0, 0.4, 0.4),
	Color(0.45, 0.68, 1.0),
	Color(0.4, 0.92, 0.5),
]
const LANE_BG_COLOR := Color(0.06, 0.05, 0.1, 0.9)
const HIT_LINE_COLOR := Color(0.92, 0.82, 0.5, 0.8)
const FLASH_COLOR := Color(1.0, 0.95, 0.7, 0.35)

# ── SONG CHARTS ──
## Array of Dictionaries. Each: { "name": String, "bpm": float,
##   "duration_beats": float, "notes": Array[{ "lane": int, "beat": float }] }
## Replace / extend these when real music is available.
var _song_charts: Array = []
var _active_chart: Dictionary = {}

# ── AUDIO HOOKS ──
# TODO: Add an AudioStreamPlayer child (or export var) for song playback.
# var _music_player: AudioStreamPlayer
# In _start_song(): _music_player.play()
# In _end_song():   _music_player.stop()
# Each chart could reference a specific audio resource path.
# Sync: _song_elapsed should track _music_player.get_playback_position()
# for drift-free timing once real audio is connected.


# ══════════════════════════════════════════════════════════════
#  LIFECYCLE
# ══════════════════════════════════════════════════════════════

func _ready() -> void:
	_pixel_font = load("res://fonts/m5x7.ttf") as Font

	App.reset_lives()
	App.minigame_time_remaining = -1.0

	_total_lane_width = lane_count * LANE_WIDTH + (lane_count - 1) * LANE_GAP
	_lane_area_left = -_total_lane_width / 2.0
	_scroll_distance = HIT_LINE_Y - LANE_TOP_Y
	_travel_time = _scroll_distance / note_scroll_speed

	_build_song_charts()
	_select_random_song()
	_prepare_notes()
	_build_visuals()
	_build_intro_overlay()

	_phase = Phase.INTRO
	print("[Minigame:Cadence] Starting (%s, BPM %.0f, %d notes)" % [_active_chart.get("name", "?"), _bpm, _total_notes])


func _process(delta: float) -> void:
	match _phase:
		Phase.INTRO:
			_process_intro(delta)
		Phase.PLAYING:
			_process_playing(delta)


# ══════════════════════════════════════════════════════════════
#  INTRO / COUNTDOWN
# ══════════════════════════════════════════════════════════════

func _process_intro(delta: float) -> void:
	_intro_elapsed += delta
	var remaining := intro_duration - _intro_elapsed
	if remaining > 3.0:
		if _countdown_label:
			_countdown_label.text = ""
	elif remaining > 2.0:
		if _countdown_label:
			_countdown_label.text = "3"
	elif remaining > 1.0:
		if _countdown_label:
			_countdown_label.text = "2"
	elif remaining > 0.0:
		if _countdown_label:
			_countdown_label.text = "1"
	if _intro_elapsed >= intro_duration:
		_start_song()


func _start_song() -> void:
	_phase = Phase.PLAYING
	_song_elapsed = 0.0

	if _intro_label:
		_intro_label.visible = false
	if _countdown_label:
		_countdown_label.visible = false

	# TODO: Start music playback here.
	# if _music_player and _music_player.stream:
	#     _music_player.play()

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

func _process_playing(delta: float) -> void:
	_song_elapsed += delta

	var ui := get_node_or_null("UI")
	if ui and ui.has_method("update_timer_display"):
		ui.update_timer_display(max(0.0, _song_duration - _song_elapsed))

	_spawn_pending_notes()
	_update_note_positions()
	_check_missed_notes()

	if ui and ui.has_method("update_accuracy_display"):
		ui.update_accuracy_display(_hits, _total_notes)

	var all_done := _song_elapsed >= _song_duration and _all_notes_resolved()
	var hard_cap := _song_elapsed >= _song_duration + 2.0
	if all_done or hard_cap:
		_end_song()


func _spawn_pending_notes() -> void:
	while _next_spawn_index < _notes.size():
		var note: Dictionary = _notes[_next_spawn_index]
		var spawn_time: float = note["hit_time"] - _travel_time
		if _song_elapsed < spawn_time:
			break
		_spawn_note_visual(note)
		note["state"] = &"active"
		_next_spawn_index += 1


func _spawn_note_visual(note: Dictionary) -> void:
	var lane: int = note["lane"]
	var lane_center_x: float = _lane_area_left + lane * (LANE_WIDTH + LANE_GAP) + LANE_WIDTH / 2.0
	var half := NOTE_SIZE / 2.0

	var note_node := Node2D.new()
	note_node.position = Vector2(lane_center_x, LANE_TOP_Y)
	note_node.z_index = 5

	var rect := ColorRect.new()
	rect.color = NOTE_COLORS[lane]
	rect.size = Vector2(NOTE_SIZE, NOTE_SIZE)
	rect.position = Vector2(-half, -half)
	note_node.add_child(rect)

	var inner := ColorRect.new()
	inner.color = Color(1.0, 1.0, 1.0, 0.25)
	var inset := NOTE_SIZE * 0.25
	inner.size = Vector2(NOTE_SIZE - inset * 2, NOTE_SIZE - inset * 2)
	inner.position = Vector2(-half + inset, -half + inset)
	note_node.add_child(inner)

	add_child(note_node)
	note["node"] = note_node


func _update_note_positions() -> void:
	for note in _notes:
		if note["state"] == &"active" and note.has("node") and is_instance_valid(note["node"]):
			var time_until_hit: float = note["hit_time"] - _song_elapsed
			note["node"].position.y = HIT_LINE_Y - time_until_hit * note_scroll_speed


func _check_missed_notes() -> void:
	for note in _notes:
		if note["state"] != &"active":
			continue
		if _song_elapsed - note["hit_time"] > hit_window_secs:
			note["state"] = &"missed"
			_misses += 1
			_fade_note(note)


func _all_notes_resolved() -> bool:
	for note in _notes:
		if note["state"] == &"pending" or note["state"] == &"active":
			return false
	return true


func _end_song() -> void:
	if _phase == Phase.RESULTS:
		return
	_phase = Phase.RESULTS
	game_over = true

	var accuracy: float = 0.0
	if _total_notes > 0:
		accuracy = float(_hits) / float(_total_notes)

	player_won = accuracy >= win_accuracy

	# TODO: Stop music playback.
	# if _music_player: _music_player.stop()

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

	if event is InputEventKey and event.pressed and not event.echo:
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
		if note["state"] != &"active" or note["lane"] != lane:
			continue
		var diff: float = absf(_song_elapsed - note["hit_time"])
		if diff <= hit_window_secs and diff < best_diff:
			best_note = note
			best_diff = diff

	if not best_note.is_empty():
		best_note["state"] = &"hit"
		_hits += 1
		_pop_note(best_note)
		# TODO: Play hit sound effect.


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
	node.modulate = Color(1, 1, 1, 0.5)
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
		var cx: float = _lane_area_left + i * (LANE_WIDTH + LANE_GAP) + LANE_WIDTH / 2.0
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
#  SONG CHARTS — placeholder data
# ══════════════════════════════════════════════════════════════

func _build_song_charts() -> void:
	## Populate _song_charts with placeholder beat-based charts.
	## Each chart: { name, bpm, duration_beats, notes: [{lane, beat}] }.
	## Replace these with real music-synced charts later.

	_song_charts.append({
		"name": "The March",
		"bpm": 120,
		"duration_beats": 50,
		"notes": [
			{"lane": 0, "beat": 2.0}, {"lane": 1, "beat": 4.0}, {"lane": 2, "beat": 6.0},
			{"lane": 1, "beat": 7.0}, {"lane": 0, "beat": 8.0},
			{"lane": 2, "beat": 10.0}, {"lane": 0, "beat": 11.0}, {"lane": 1, "beat": 12.0},
			{"lane": 2, "beat": 14.0}, {"lane": 1, "beat": 15.0}, {"lane": 0, "beat": 16.0},
			{"lane": 1, "beat": 18.0}, {"lane": 2, "beat": 19.0}, {"lane": 0, "beat": 20.0},
			{"lane": 2, "beat": 22.0}, {"lane": 0, "beat": 23.0}, {"lane": 1, "beat": 24.0},
			{"lane": 0, "beat": 25.0}, {"lane": 2, "beat": 26.0},
			{"lane": 1, "beat": 28.0}, {"lane": 0, "beat": 29.0}, {"lane": 2, "beat": 30.0},
			{"lane": 1, "beat": 31.0}, {"lane": 0, "beat": 32.0},
			{"lane": 2, "beat": 34.0}, {"lane": 1, "beat": 35.0}, {"lane": 0, "beat": 36.0},
			{"lane": 1, "beat": 38.0}, {"lane": 2, "beat": 39.0}, {"lane": 0, "beat": 40.0},
			{"lane": 2, "beat": 42.0}, {"lane": 1, "beat": 44.0},
			{"lane": 0, "beat": 46.0}, {"lane": 1, "beat": 47.0}, {"lane": 2, "beat": 48.0},
		],
	})

	_song_charts.append({
		"name": "The Reel",
		"bpm": 140,
		"duration_beats": 56,
		"notes": [
			{"lane": 0, "beat": 2.0}, {"lane": 2, "beat": 3.0}, {"lane": 1, "beat": 4.0},
			{"lane": 0, "beat": 5.0}, {"lane": 1, "beat": 6.0}, {"lane": 2, "beat": 6.5},
			{"lane": 0, "beat": 8.0}, {"lane": 2, "beat": 9.0}, {"lane": 1, "beat": 10.0},
			{"lane": 0, "beat": 11.0}, {"lane": 2, "beat": 12.0}, {"lane": 1, "beat": 12.5},
			{"lane": 0, "beat": 14.0}, {"lane": 1, "beat": 15.0}, {"lane": 2, "beat": 16.0},
			{"lane": 0, "beat": 17.0}, {"lane": 2, "beat": 18.0}, {"lane": 1, "beat": 18.5},
			{"lane": 0, "beat": 20.0}, {"lane": 1, "beat": 21.0}, {"lane": 2, "beat": 22.0},
			{"lane": 0, "beat": 23.0}, {"lane": 1, "beat": 24.0}, {"lane": 2, "beat": 24.5},
			{"lane": 1, "beat": 26.0}, {"lane": 0, "beat": 27.0}, {"lane": 2, "beat": 28.0},
			{"lane": 0, "beat": 29.0}, {"lane": 1, "beat": 30.0}, {"lane": 2, "beat": 30.5},
			{"lane": 0, "beat": 32.0}, {"lane": 2, "beat": 33.0}, {"lane": 1, "beat": 34.0},
			{"lane": 0, "beat": 36.0}, {"lane": 2, "beat": 37.0}, {"lane": 1, "beat": 38.0},
			{"lane": 0, "beat": 40.0}, {"lane": 1, "beat": 42.0}, {"lane": 2, "beat": 44.0},
			{"lane": 0, "beat": 46.0}, {"lane": 1, "beat": 48.0}, {"lane": 2, "beat": 50.0},
			{"lane": 0, "beat": 52.0}, {"lane": 1, "beat": 54.0},
		],
	})

	_song_charts.append({
		"name": "The Ballad",
		"bpm": 100,
		"duration_beats": 42,
		"notes": [
			{"lane": 1, "beat": 2.0}, {"lane": 0, "beat": 4.0}, {"lane": 2, "beat": 6.0},
			{"lane": 1, "beat": 8.0}, {"lane": 0, "beat": 10.0},
			{"lane": 2, "beat": 12.0}, {"lane": 1, "beat": 14.0},
			{"lane": 0, "beat": 16.0}, {"lane": 2, "beat": 17.0}, {"lane": 1, "beat": 18.0},
			{"lane": 0, "beat": 20.0}, {"lane": 1, "beat": 22.0},
			{"lane": 2, "beat": 24.0}, {"lane": 0, "beat": 25.0}, {"lane": 1, "beat": 26.0},
			{"lane": 2, "beat": 28.0}, {"lane": 0, "beat": 30.0},
			{"lane": 1, "beat": 32.0}, {"lane": 2, "beat": 33.0}, {"lane": 0, "beat": 34.0},
			{"lane": 1, "beat": 36.0}, {"lane": 2, "beat": 38.0}, {"lane": 0, "beat": 40.0},
		],
	})


func _select_random_song() -> void:
	_active_chart = _song_charts[randi() % _song_charts.size()]
	_bpm = _active_chart.get("bpm", default_bpm)
	_seconds_per_beat = 60.0 / _bpm
	var duration_beats: float = _active_chart.get("duration_beats", 50)
	_song_duration = duration_beats * _seconds_per_beat


func _prepare_notes() -> void:
	_notes.clear()
	_next_spawn_index = 0
	_hits = 0
	_misses = 0

	for entry in _active_chart.get("notes", []):
		var beat: float = float(entry["beat"])
		_notes.append({
			"lane": int(entry["lane"]),
			"beat": beat,
			"hit_time": beat * _seconds_per_beat,
			"state": &"pending",
		})

	_notes.sort_custom(func(a, b): return a["hit_time"] < b["hit_time"])
	_total_notes = _notes.size()


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

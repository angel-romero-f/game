extends Node2D

## Courtly Cuisine — Timing-based sandwich stacking minigame.
## Place moving ingredients onto a stack by pressing SPACE at the right moment.
## A failed drop (insufficient overlap) costs one life; recipe stays the same across retries.

var game_over: bool = false
var player_won: bool = false
var _has_returned: bool = false
const COURTLY_MUSIC_PATH := "res://music/s'mores.mp3"
const PERSISTENT_COURTLY_PLAYER_NAME := "PersistentCourtlyCuisineMusic"
var _courtly_music_player: AudioStreamPlayer = null

# ── Timer (10-second countdown) ──
const MINIGAME_TIME_LIMIT: float = 10.0
var _minigame_timer: float = MINIGAME_TIME_LIMIT
var _timer_active: bool = false

# ── Tuning knobs (tweak these freely) ────────────────────────
## Dimensions of each ingredient rectangle.
## These get auto-scaled from the s'mores sprite sizes in _ready().
var INGREDIENT_WIDTH: float = 130.0
var INGREDIENT_HEIGHT: float = 26.0
var BREAD_HEIGHT: float = 30.0

const SMORES_VISUAL_SCALE: float = 3.0
const STACK_SPACING: float = 0.33
const PLATE_CONTACT_ADJUST: float = 165.0
const LAYER_CONTACT_ADJUST: float = 20.0

## Fraction of ingredient width that must overlap the layer below to succeed.
## 0.55 = 55% overlap required. Lower = easier, higher = harder.
const OVERLAP_THRESHOLD: float = 0.55

## Horizontal bounds for the moving ingredient's center position.
## These get widened automatically once we know ingredient width.
var MOVE_LEFT: float = -200.0
var MOVE_RIGHT: float = 200.0

## Vertical layout anchors.
var STACK_BASE_Y: float = 70.0
var HOVER_GAP: float = 70.0

# ── S'mores setup ────────────────────────────────────────────
const SMORES_FRAMES_PATH := "res://assets/smores.pxo"
const FRAME_CHOCOLATE := 0
const FRAME_MARSHMALLOW := 1
const FRAME_GRAHAM := 2
const FRAME_SMORE := 3
const FRAME_PLATE := 4

const PLATE_SCALE: float = 2.0

## "speed" controls horizontal oscillation in pixels/second.
const SMORES_RECIPE: Array = [
	{ "name": "Graham Cracker", "frame": FRAME_GRAHAM, "speed": 390.0 },
	{ "name": "Chocolate", "frame": FRAME_CHOCOLATE, "speed": 435.0 },
	{ "name": "Marshmallow", "frame": FRAME_MARSHMALLOW, "speed": 465.0 },
	{ "name": "Graham Cracker", "frame": FRAME_GRAHAM, "speed": 495.0 },
]

# ── Runtime state ────────────────────────────────────────────
var _recipe: Array = []
var _current_layer: int = 0
var _placed_x: Array = []          # Center-X of every placed layer (index 0 = bottom bread)
var _moving: Node2D = null         # The oscillating ingredient (top-left anchored)
var _moving_dir: float = 1.0
var _dropping: bool = false
var _moving_width: float = 0.0
var _label: Label = null
var _target_indicator: ColorRect = null
var _pixel_font: Font = null
var _smores_frames: SpriteFrames = null
var _base_height: float = 30.0


func _ready():
	_setup_courtly_music()

	_pixel_font = load("res://fonts/m5x7.ttf") as Font
	_smores_frames = load(SMORES_FRAMES_PATH) as SpriteFrames
	_apply_smores_scaling()

	# Recipe persistence: keep the same order across retries.
	if App.minigame_time_remaining <= 0.0:
		App.reset_lives()
		_recipe = SMORES_RECIPE.duplicate(true)
		App.set_meta("cc_recipe", _recipe)
	else:
		_recipe = App.get_meta("cc_recipe", SMORES_RECIPE.duplicate(true))

	# Timer (persists across retries)
	if App.minigame_time_remaining > 0.0:
		_minigame_timer = App.minigame_time_remaining
	else:
		_minigame_timer = MINIGAME_TIME_LIMIT
		App.minigame_time_remaining = _minigame_timer
	_timer_active = true

	_build_visuals()
	_spawn_moving()
	print("[Minigame:CourtlyCuisine] Timer started (%.1fs)" % _minigame_timer)

func _setup_courtly_music() -> void:
	# S'mores music is exclusive to Courtly Cuisine.
	App.stop_gameplay_music()

	var root := get_tree().root
	var existing := root.get_node_or_null(PERSISTENT_COURTLY_PLAYER_NAME)
	if existing and existing is AudioStreamPlayer:
		_courtly_music_player = existing as AudioStreamPlayer
		if not _courtly_music_player.playing:
			_courtly_music_player.play()
		return

	var stream := load(COURTLY_MUSIC_PATH)
	if not stream is AudioStream:
		push_warning("[Minigame:CourtlyCuisine] Missing or invalid music at %s" % COURTLY_MUSIC_PATH)
		return

	_courtly_music_player = AudioStreamPlayer.new()
	_courtly_music_player.name = PERSISTENT_COURTLY_PLAYER_NAME
	_courtly_music_player.bus = "Music"
	_courtly_music_player.stream = stream
	root.add_child(_courtly_music_player)

	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true

	_courtly_music_player.play()

func _stop_courtly_music() -> void:
	if _courtly_music_player and is_instance_valid(_courtly_music_player):
		_courtly_music_player.stop()
		_courtly_music_player.queue_free()
	_courtly_music_player = null


# ── Visual construction ──────────────────────────────────────

func _build_visuals():
	# Dark wooden table surface
	var table := ColorRect.new()
	table.color = Color(0.22, 0.14, 0.08)
	var table_w := maxf(340.0, INGREDIENT_WIDTH + 220.0)
	table.size = Vector2(table_w, 180)
	table.position = Vector2(-table_w / 2.0, STACK_BASE_Y - 160)
	table.z_index = -2
	add_child(table)

	# Table front edge highlight
	var edge := ColorRect.new()
	edge.color = Color(0.32, 0.20, 0.11)
	edge.size = Vector2(table_w + 20.0, 18)
	edge.position = Vector2(-(table_w + 20.0) / 2.0, STACK_BASE_Y + 10)
	edge.z_index = -1
	add_child(edge)

	# Plate (always pre-placed) — uses the 5th frame.
	var plate_data := { "name": "Plate", "frame": FRAME_PLATE }
	var plate := _build_layer_visual(plate_data, STACK_BASE_Y - _base_height, 1)
	plate.position.x = -(INGREDIENT_WIDTH * PLATE_SCALE) / 2.0
	add_child(plate)
	_placed_x.append(0.0)

	# Current ingredient name label
	_label = Label.new()
	if _pixel_font:
		_label.add_theme_font_override("font", _pixel_font)
	_label.add_theme_font_size_override("font_size", 34)
	_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.55))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_label.add_theme_constant_override("outline_size", 4)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Keep "Place: ..." below the plate but still visible on-screen.
	_label.position = Vector2(-220, STACK_BASE_Y - 4)
	_label.size = Vector2(440, 36)
	_label.z_index = 10
	add_child(_label)

	# Semi-transparent target indicator showing the landing zone
	_target_indicator = ColorRect.new()
	_target_indicator.color = Color(1, 1, 1, 0.1)
	_target_indicator.z_index = 0
	add_child(_target_indicator)
	_update_target_indicator()


func _slot_y() -> float:
	return STACK_BASE_Y - _base_height - (_current_layer + 1) * (INGREDIENT_HEIGHT * STACK_SPACING) + PLATE_CONTACT_ADJUST + (_current_layer * LAYER_CONTACT_ADJUST)


func _layer_height(layer_index: int) -> float:
	if layer_index < _recipe.size() and _is_bread_like(_recipe[layer_index].get("name", "")):
		return BREAD_HEIGHT
	return INGREDIENT_HEIGHT


func _is_bread_like(name: String) -> bool:
	return name == "Graham Cracker" or name == "S'more"


func _is_plate(name: String) -> bool:
	return name == "Plate"


func _apply_smores_scaling() -> void:
	if not _smores_frames or not _smores_frames.has_animation("default"):
		return

	var max_w := 0.0
	var max_h := 0.0
	for idx in [FRAME_CHOCOLATE, FRAME_MARSHMALLOW, FRAME_GRAHAM, FRAME_SMORE]:
		var tex := _smores_frames.get_frame_texture("default", idx)
		if tex:
			max_w = maxf(max_w, tex.get_width())
			max_h = maxf(max_h, tex.get_height())

	if max_w <= 0.0 or max_h <= 0.0:
		return

	# Clamp visual size so large sprite canvases don't break the minigame layout.
	INGREDIENT_WIDTH = clampf(max_w * SMORES_VISUAL_SCALE, 140.0, 760.0)
	INGREDIENT_HEIGHT = clampf(max_h * SMORES_VISUAL_SCALE, 32.0, 280.0)
	BREAD_HEIGHT = INGREDIENT_HEIGHT
	_base_height = INGREDIENT_HEIGHT * PLATE_SCALE

	# Keep travel range screen-safe instead of scaling endlessly with texture size.
	MOVE_LEFT = -220.0
	MOVE_RIGHT = 220.0

	# Keep stack and hover positions playable after size changes.
	# Keep the stack lower so ingredients don't cover top UI text or go off-screen while hovering.
	STACK_BASE_Y = clampf(250.0 + (INGREDIENT_HEIGHT - 26.0) * 0.25, 220.0, 320.0)
	HOVER_GAP = maxf(70.0, INGREDIENT_HEIGHT + 16.0)


func _build_layer_visual(data: Dictionary, y: float, z: int) -> Node2D:
	var name := str(data.get("name", ""))
	var h := BREAD_HEIGHT if _is_bread_like(name) else INGREDIENT_HEIGHT
	var w := INGREDIENT_WIDTH
	if _is_plate(name):
		w *= PLATE_SCALE
		h *= PLATE_SCALE

	var holder := Node2D.new()
	holder.position = Vector2(-w / 2.0, y)
	holder.z_index = z
	holder.set_meta("w", w)

	var frame_idx: int = int(data.get("frame", -1))
	if _smores_frames and _smores_frames.has_animation("default") and frame_idx >= 0 and frame_idx < _smores_frames.get_frame_count("default"):
		var tex := _smores_frames.get_frame_texture("default", frame_idx)
		if tex:
			var spr := Sprite2D.new()
			spr.name = "Sprite2D"
			spr.centered = false
			spr.texture = tex
			spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			var tex_w := float(tex.get_width())
			var tex_h := float(tex.get_height())
			if tex_w > 0.0 and tex_h > 0.0:
				var scale_factor := minf(w / tex_w, h / tex_h)
				var draw_w := tex_w * scale_factor
				var draw_h := tex_h * scale_factor
				spr.scale = Vector2(scale_factor, scale_factor)
				# Center sprite in its holder so visuals are not biased to the left.
				spr.position = Vector2((w - draw_w) * 0.5, (h - draw_h) * 0.5)
			holder.add_child(spr)
			return holder

	# Fallback rectangle if the SpriteFrames resource cannot be loaded.
	var fallback := ColorRect.new()
	fallback.color = Color(0.8, 0.7, 0.55)
	fallback.size = Vector2(w, h)
	holder.add_child(fallback)
	return holder


func _node_width(n: Node) -> float:
	if n and n.has_meta("w"):
		return float(n.get_meta("w"))
	return INGREDIENT_WIDTH


func _update_target_indicator():
	if not _target_indicator:
		return
	var below_x: float = _placed_x[_placed_x.size() - 1]
	var h := _layer_height(_current_layer)
	_target_indicator.size = Vector2(INGREDIENT_WIDTH, h)
	_target_indicator.position = Vector2(below_x - INGREDIENT_WIDTH / 2.0, _slot_y())


# ── Moving ingredient ────────────────────────────────────────

func _spawn_moving():
	if _current_layer >= _recipe.size():
		return

	var data: Dictionary = _recipe[_current_layer]
	_moving = _build_layer_visual(data, _slot_y() - HOVER_GAP, 5)
	_moving_width = _node_width(_moving)
	_moving.position.x = MOVE_LEFT - _moving_width / 2.0
	_moving_dir = 1.0
	_dropping = false
	add_child(_moving)

	if _label:
		_label.text = "Place: %s" % data["name"]
	_update_target_indicator()


# ── Game loop ────────────────────────────────────────────────

func _process(delta: float) -> void:
	# Countdown timer (keeps running during death screens, same as Bridge)
	if _timer_active:
		_minigame_timer -= delta
		App.minigame_time_remaining = _minigame_timer
		var ui := get_node_or_null("UI")
		if ui and ui.has_method("update_timer_display"):
			ui.update_timer_display(_minigame_timer)
		if _minigame_timer <= 0.0:
			_on_timeout()
			return

	if game_over or _dropping or not _moving:
		return

	# Oscillate the moving ingredient horizontally
	var data: Dictionary = _recipe[_current_layer] if _current_layer < _recipe.size() else {}
	var spd: float = data.get("speed", 200.0)
	var cx: float = _moving.position.x + _moving_width / 2.0
	cx += spd * _moving_dir * delta

	if cx >= MOVE_RIGHT:
		cx = MOVE_RIGHT
		_moving_dir = -1.0
	elif cx <= MOVE_LEFT:
		cx = MOVE_LEFT
		_moving_dir = 1.0

	_moving.position.x = cx - _moving_width / 2.0


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("attack") and not game_over and not _dropping:
		_do_drop()
	if event is InputEventKey and event.keycode == KEY_R and event.pressed:
		handle_continue()


# ── Drop / overlap logic ────────────────────────────────────

func _do_drop():
	if not _moving or _current_layer >= _recipe.size():
		return

	_dropping = true
	var target_y := _slot_y()

	# Animate the ingredient falling to the target slot
	var tween := create_tween()
	tween.tween_property(_moving, "position:y", target_y, 0.12).set_ease(Tween.EASE_IN)
	tween.tween_callback(_check_overlap)


func _check_overlap():
	if not _moving:
		return

	var drop_cx: float = _moving.position.x + _moving_width / 2.0
	var below_cx: float = _placed_x[_placed_x.size() - 1]

	# Calculate horizontal overlap between the dropped piece and the layer below
	var left1 := drop_cx - _moving_width / 2.0
	var right1 := drop_cx + _moving_width / 2.0
	var left2 := below_cx - INGREDIENT_WIDTH / 2.0
	var right2 := below_cx + INGREDIENT_WIDTH / 2.0
	var overlap := maxf(0.0, minf(right1, right2) - maxf(left1, left2))

	if overlap >= OVERLAP_THRESHOLD * INGREDIENT_WIDTH:
		_placement_success(drop_cx)
	else:
		_placement_fail()


func _placement_success(cx: float):
	# Snap ingredient into the stack
	_moving.z_index = 1
	_placed_x.append(cx)
	_current_layer += 1
	_dropping = false

	# SFX hook: play success sound here
	# e.g. $SuccessSound.play()

	if _current_layer >= _recipe.size():
		_win()
	else:
		_spawn_moving()


func _placement_fail():
	# Animate the ingredient tumbling off
	if _moving:
		var tw := create_tween()
		tw.tween_property(_moving, "position:y", _moving.position.y + 300, 0.35)
		tw.parallel().tween_property(_moving, "modulate:a", 0.0, 0.35)
		tw.tween_callback(_moving.queue_free)
		_moving = null

	# SFX hook: play fail sound here
	# e.g. $FailSound.play()

	_dropping = false
	game_over = true
	player_won = false
	App.lose_life()

	var ui := get_node_or_null("UI")
	if ui and ui.has_method("show_game_over"):
		ui.show_game_over(App.get_lives() <= 0)


func _win():
	_timer_active = false
	game_over = true
	player_won = true

	if _label:
		_label.text = "Perfect S'more Stack! Toasty victory!"
	if _target_indicator:
		_target_indicator.visible = false

	var ui := get_node_or_null("UI")
	if ui and ui.has_method("show_win"):
		ui.show_win()


# ── Timeout / continue / return (matches Bridge/IceFishing pattern) ──

func _on_timeout() -> void:
	_timer_active = false
	if _has_returned:
		return
	_has_returned = true
	print("[Minigame:CourtlyCuisine] Time's up! Returning to map.")
	game_over = true
	player_won = false
	App.minigame_time_remaining = -1.0
	App.reset_lives()
	App.pending_minigame_reward.clear()
	App.on_minigame_completed()
	_return_to_map()


func handle_continue():
	if not game_over:
		return
	if _has_returned:
		return
	_has_returned = true

	if player_won:
		App.minigame_time_remaining = -1.0
		App.add_card_from_pending_reward()
		App.on_minigame_completed()
		_return_to_map()
	elif App.get_lives() <= 0:
		App.minigame_time_remaining = -1.0
		App.reset_lives()
		App.pending_minigame_reward.clear()
		App.pending_bonus_reward.clear()
		App.region_bonus_active = false
		App.on_minigame_completed()
		_return_to_map()
	else:
		# Still have lives — retry with same recipe, timer continues
		App.minigame_time_remaining = _minigame_timer
		get_tree().reload_current_scene()


func _return_to_map():
	_stop_courtly_music()
	App.go("res://scenes/ui/game_intro.tscn")

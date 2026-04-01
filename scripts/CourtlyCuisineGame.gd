extends Node2D

## Courtly Cuisine — Timing-based sandwich stacking minigame.
## Place 3 moving ingredients onto a stack by pressing SPACE at the right moment.
## A failed drop (insufficient overlap) costs one life; recipe stays the same across retries.

var game_over: bool = false
var player_won: bool = false
var _has_returned: bool = false

# ── Timer (shared 30-second countdown, same as all minigames) ──
const MINIGAME_TIME_LIMIT: float = 30.0
var _minigame_timer: float = MINIGAME_TIME_LIMIT
var _timer_active: bool = false

# ── Tuning knobs (tweak these freely) ────────────────────────
## Dimensions of each ingredient rectangle.
const INGREDIENT_WIDTH: float = 130.0
const INGREDIENT_HEIGHT: float = 26.0
const BREAD_HEIGHT: float = 30.0

## Fraction of ingredient width that must overlap the layer below to succeed.
## 0.40 = 40% overlap required.  Lower = easier, higher = harder.
const OVERLAP_THRESHOLD: float = 0.40

## Horizontal bounds for the moving ingredient's center position.
const MOVE_LEFT: float = -200.0
const MOVE_RIGHT: float = 200.0

## Vertical layout anchors.
const STACK_BASE_Y: float = 70.0
const HOVER_GAP: float = 70.0

# ── Recipe pool ──────────────────────────────────────────────
## Each recipe is an array of 3 layers: [ingredient1, ingredient2, top_bread].
## "speed" controls horizontal oscillation in pixels/second.
const RECIPES: Array = [
	[
		{ "name": "Beef",      "color": [0.62, 0.22, 0.12], "speed": 180.0 },
		{ "name": "Cheese",    "color": [1.00, 0.85, 0.20], "speed": 240.0 },
		{ "name": "Top Bread", "color": [0.82, 0.63, 0.35], "speed": 290.0 },
	],
	[
		{ "name": "Egg",       "color": [1.00, 0.93, 0.65], "speed": 200.0 },
		{ "name": "Herbs",     "color": [0.25, 0.55, 0.18], "speed": 260.0 },
		{ "name": "Top Bread", "color": [0.82, 0.63, 0.35], "speed": 310.0 },
	],
	[
		{ "name": "Mushroom",  "color": [0.60, 0.48, 0.32], "speed": 190.0 },
		{ "name": "Cheese",    "color": [1.00, 0.85, 0.20], "speed": 250.0 },
		{ "name": "Top Bread", "color": [0.82, 0.63, 0.35], "speed": 300.0 },
	],
]

# ── Runtime state ────────────────────────────────────────────
var _recipe: Array = []
var _current_layer: int = 0
var _placed_x: Array = []          # Center-X of every placed layer (index 0 = bottom bread)
var _moving: ColorRect = null      # The oscillating ingredient
var _moving_dir: float = 1.0
var _dropping: bool = false
var _label: Label = null
var _target_indicator: ColorRect = null
var _pixel_font: Font = null


func _ready():
	_pixel_font = load("res://fonts/m5x7.ttf") as Font

	# Recipe persistence: pick randomly on fresh start, reuse on retry.
	if App.minigame_time_remaining <= 0.0:
		App.reset_lives()
		_recipe = RECIPES[randi() % RECIPES.size()].duplicate(true)
		App.set_meta("cc_recipe", _recipe)
	else:
		_recipe = App.get_meta("cc_recipe", RECIPES[0].duplicate(true))

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


# ── Visual construction ──────────────────────────────────────

func _build_visuals():
	# Dark wooden table surface
	var table := ColorRect.new()
	table.color = Color(0.22, 0.14, 0.08)
	table.size = Vector2(340, 180)
	table.position = Vector2(-170, STACK_BASE_Y - 160)
	table.z_index = -2
	add_child(table)

	# Table front edge highlight
	var edge := ColorRect.new()
	edge.color = Color(0.32, 0.20, 0.11)
	edge.size = Vector2(360, 18)
	edge.position = Vector2(-180, STACK_BASE_Y + 10)
	edge.z_index = -1
	add_child(edge)

	# Bottom bread (always pre-placed)
	var bread := ColorRect.new()
	bread.color = Color(0.82, 0.63, 0.35)
	bread.size = Vector2(INGREDIENT_WIDTH, BREAD_HEIGHT)
	bread.position = Vector2(-INGREDIENT_WIDTH / 2.0, STACK_BASE_Y - BREAD_HEIGHT)
	bread.z_index = 1
	add_child(bread)
	_placed_x.append(0.0)

	# Thin bread crust outline
	var crust := ColorRect.new()
	crust.color = Color(0.65, 0.45, 0.22)
	crust.size = Vector2(INGREDIENT_WIDTH + 4, BREAD_HEIGHT + 4)
	crust.position = Vector2(-INGREDIENT_WIDTH / 2.0 - 2, STACK_BASE_Y - BREAD_HEIGHT - 2)
	crust.z_index = 0
	add_child(crust)

	# Current ingredient name label
	_label = Label.new()
	if _pixel_font:
		_label.add_theme_font_override("font", _pixel_font)
	_label.add_theme_font_size_override("font_size", 26)
	_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.55))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_label.add_theme_constant_override("outline_size", 4)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.position = Vector2(-160, STACK_BASE_Y - 220)
	_label.size = Vector2(320, 36)
	_label.z_index = 10
	add_child(_label)

	# Semi-transparent target indicator showing the landing zone
	_target_indicator = ColorRect.new()
	_target_indicator.color = Color(1, 1, 1, 0.1)
	_target_indicator.z_index = 0
	add_child(_target_indicator)
	_update_target_indicator()


func _slot_y() -> float:
	return STACK_BASE_Y - BREAD_HEIGHT - (_current_layer + 1) * INGREDIENT_HEIGHT


func _layer_height(layer_index: int) -> float:
	if layer_index < _recipe.size() and _recipe[layer_index]["name"] == "Top Bread":
		return BREAD_HEIGHT
	return INGREDIENT_HEIGHT


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
	var c: Array = data.get("color", [0.5, 0.5, 0.5])
	var h := _layer_height(_current_layer)

	_moving = ColorRect.new()
	_moving.color = Color(c[0], c[1], c[2])
	_moving.size = Vector2(INGREDIENT_WIDTH, h)
	_moving.position = Vector2(MOVE_LEFT - INGREDIENT_WIDTH / 2.0, _slot_y() - HOVER_GAP)
	_moving.z_index = 5
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
	var cx: float = _moving.position.x + INGREDIENT_WIDTH / 2.0
	cx += spd * _moving_dir * delta

	if cx >= MOVE_RIGHT:
		cx = MOVE_RIGHT
		_moving_dir = -1.0
	elif cx <= MOVE_LEFT:
		cx = MOVE_LEFT
		_moving_dir = 1.0

	_moving.position.x = cx - INGREDIENT_WIDTH / 2.0


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

	var drop_cx: float = _moving.position.x + INGREDIENT_WIDTH / 2.0
	var below_cx: float = _placed_x[_placed_x.size() - 1]

	# Calculate horizontal overlap between the dropped piece and the layer below
	var left1 := drop_cx - INGREDIENT_WIDTH / 2.0
	var right1 := drop_cx + INGREDIENT_WIDTH / 2.0
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
		_label.text = "Sandwich Served!"
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
	App.play_main_music()
	App.go("res://scenes/ui/game_intro.tscn")

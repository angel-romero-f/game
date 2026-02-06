extends CharacterBody2D

# Fishing bar settings
@export var bar_rise_speed: float = 380.0  # How fast bar rises when holding space
@export var bar_fall_speed: float = 200.0  # How fast bar falls when not holding
@export var bar_height: float = 50.0  # Height of the catch zone bar
@export var fishing_area_height: float = 300.0  # Total height of the fishing area

# Fish movement settings
@export var fish_base_speed: float = 280.0
@export var fish_direction_change_time: float = 0.25  # How often fish changes direction

# Progress settings
@export var progress_fill_rate: float = 25.0  # How fast progress fills when fish in zone
@export var progress_drain_rate: float = 22.0  # How fast progress drains when fish outside

# Fish tired mechanic - fish slows down periodically
@export var fish_tired_interval: float = 3.0  # How often fish gets tired
@export var fish_tired_duration: float = 1.2  # How long fish stays tired
@export var fish_tired_speed_mult: float = 0.25  # Speed multiplier when tired
@export var win_progress: float = 100.0

# State
var bar_position: float = 0.0  # 0 = bottom, fishing_area_height = top
var fish_position: float = 150.0  # Fish Y position in the fishing area
var fish_velocity: float = 0.0
var fish_target_velocity: float = 100.0
var fish_direction_timer: float = 0.0
var fish_tired_timer: float = 0.0  # Counts up to fish_tired_interval
var fish_is_tired: bool = false
var fish_tired_remaining: float = 0.0  # Time left being tired
var catch_progress: float = 50.0  # Start at 50%
var game_over: bool = false
var is_fishing: bool = true

# References to visual elements (set by scene)
var fishing_area: Control = null
var bar_visual: ColorRect = null
var fish_visual: ColorRect = null
var progress_bar: ProgressBar = null

signal player_died
signal player_won
signal progress_updated(progress: float)

func _ready():
	add_to_group("player")
	_apply_selected_race_visual()
	
	# Get references to fishing UI elements
	await get_tree().process_frame
	var game_scene = get_tree().current_scene
	fishing_area = game_scene.get_node_or_null("FishingArea")
	bar_visual = game_scene.get_node_or_null("FishingArea/CatchBar")
	fish_visual = game_scene.get_node_or_null("FishingArea/FishIndicator")
	progress_bar = game_scene.get_node_or_null("FishingArea/ProgressBar")
	
	# Initialize positions
	bar_position = fishing_area_height / 2.0 - bar_height / 2.0
	fish_position = fishing_area_height / 2.0
	_randomize_fish_direction()

func _apply_selected_race_visual() -> void:
	var visual := get_node_or_null("Visual") as Sprite2D
	if not visual:
		return

	var race := String(App.selected_race).strip_edges()
	if race.is_empty():
		race = "Elf"

	var texture_paths: Array[String] = []
	match race:
		"Fairy":
			texture_paths = ["res://pictures/fairy_girl_1/fg1_south.png"]
		"Orc":
			texture_paths = ["res://pictures/orc_boy_1/ob1_south.png"]
		"Infernal":
			texture_paths = ["res://pictures/infernal_boy_1/ib1_south.png"]
		_:
			texture_paths = ["res://pictures/elf_girl_1/eg1_south.png"]

	for p in texture_paths:
		if FileAccess.file_exists(p):
			var tex := load(p) as Texture2D
			if tex:
				visual.texture = tex
				return

func _process(delta):
	if game_over or not is_fishing:
		return
	
	# Handle bar movement (hold space to rise, release to fall)
	if Input.is_action_pressed("ui_accept") or Input.is_action_pressed("attack"):
		bar_position += bar_rise_speed * delta
	else:
		bar_position -= bar_fall_speed * delta
	
	# Clamp bar position
	bar_position = clamp(bar_position, 0, fishing_area_height - bar_height)
	
	# Update fish movement
	_update_fish_movement(delta)
	
	# Check if fish is in the catch zone
	var fish_in_zone = _is_fish_in_zone()
	
	# Update progress
	if fish_in_zone:
		catch_progress += progress_fill_rate * delta
	else:
		catch_progress -= progress_drain_rate * delta
	
	catch_progress = clamp(catch_progress, 0, win_progress)
	progress_updated.emit(catch_progress)
	
	# Update visuals
	_update_visuals()
	
	# Check win/lose conditions
	if catch_progress >= win_progress:
		win_game()
	elif catch_progress <= 0:
		lose_game()

func _update_fish_movement(delta: float):
	# Handle tired state
	if fish_is_tired:
		fish_tired_remaining -= delta
		if fish_tired_remaining <= 0:
			fish_is_tired = false
			fish_tired_timer = 0.0
	else:
		# Count up to next tired period
		fish_tired_timer += delta
		if fish_tired_timer >= fish_tired_interval:
			fish_is_tired = true
			fish_tired_remaining = fish_tired_duration
	
	# Fish direction change timer
	fish_direction_timer -= delta
	if fish_direction_timer <= 0:
		_randomize_fish_direction()
	
	# Smoothly move fish velocity towards target (faster response)
	fish_velocity = lerp(fish_velocity, fish_target_velocity, delta * 6.0)
	
	# Apply tired speed multiplier
	var actual_velocity = fish_velocity
	if fish_is_tired:
		actual_velocity *= fish_tired_speed_mult
	
	# Move fish
	fish_position += actual_velocity * delta
	
	# Bounce off edges
	if fish_position <= 10:
		fish_position = 10
		fish_target_velocity = abs(fish_target_velocity)
		_randomize_fish_direction()
	elif fish_position >= fishing_area_height - 10:
		fish_position = fishing_area_height - 10
		fish_target_velocity = -abs(fish_target_velocity)
		_randomize_fish_direction()

func _randomize_fish_direction():
	fish_direction_timer = randf_range(0.1, fish_direction_change_time)
	# Random speed and direction - more erratic movements
	var speed = randf_range(fish_base_speed * 0.7, fish_base_speed * 1.8)
	if randf() > 0.4:
		fish_target_velocity = speed * (1 if randf() > 0.5 else -1)
	else:
		# Sudden reversal
		fish_target_velocity = -fish_velocity * randf_range(0.8, 1.5)

func _is_fish_in_zone() -> bool:
	var bar_top = bar_position + bar_height
	var bar_bottom = bar_position
	return fish_position >= bar_bottom and fish_position <= bar_top

func _update_visuals():
	if bar_visual:
		bar_visual.position.y = fishing_area_height - bar_position - bar_height
	
	if fish_visual:
		fish_visual.position.y = fishing_area_height - fish_position - fish_visual.size.y / 2
	
	if progress_bar:
		progress_bar.value = catch_progress

func win_game():
	game_over = true
	is_fishing = false
	player_won.emit()

func lose_game():
	game_over = true
	is_fishing = false
	player_died.emit()

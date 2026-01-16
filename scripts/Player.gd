extends CharacterBody2D

# Jump settings
@export var jump_duration: float = 0.2

# How far along the flow direction to search for a rock (timing window)
@export var rock_catch_range: float = 100.0

# Current lane (-1 = starting bank, 0-3 = river lanes, 4+ = safe zone)
var current_lane: int = -1
var max_lane: int = 4  # 4 lanes (0-3), then victory

# State
var is_jumping: bool = false
var game_over: bool = false
var current_rock: Area2D = null

# Reference to spawner
var rock_spawner: Node2D = null

signal player_died
signal player_won

func _ready():
	add_to_group("player")
	await get_tree().process_frame
	rock_spawner = get_tree().current_scene.get_node_or_null("RockSpawner")

func _process(_delta):
	if game_over:
		return
	
	# Follow the rock we're standing on
	if current_rock and is_instance_valid(current_rock) and not is_jumping:
		global_position = current_rock.global_position
		
		# Fell off screen?
		if global_position.x < -350 or global_position.y > 350:
			fall_in_water()
			return
	
	# Jump input
	if not is_jumping:
		if Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("attack"):
			try_jump()

func try_jump():
	if is_jumping or game_over:
		return
	
	var next_lane = current_lane + 1
	
	# Jumping to victory?
	if next_lane > max_lane - 1:
		jump_to_victory()
		return
	
	# Find a rock in the next lane
	var target = find_rock_in_lane(next_lane)
	
	if target:
		jump_to_rock(target, next_lane)
	else:
		jump_to_water(next_lane)

func find_rock_in_lane(lane_idx: int) -> Area2D:
	if not rock_spawner:
		return null
	
	var rocks = rock_spawner.get_rocks_in_lane(lane_idx)
	var best_rock: Area2D = null
	var best_dist: float = rock_catch_range
	
	# River flow direction
	var flow_dir = Vector2(-1, 1).normalized()
	
	# Find a rock that's within catch range ALONG THE FLOW DIRECTION
	# This means timing matters, not distance perpendicular to flow
	for rock in rocks:
		if not is_instance_valid(rock):
			continue
		
		# Vector from player to rock
		var to_rock = rock.global_position - global_position
		
		# Project onto flow direction - this is the "timing" distance
		# Positive = rock is downstream, Negative = rock is upstream
		var flow_distance = to_rock.dot(flow_dir)
		
		# We want rocks that are roughly "aligned" with our jump
		# Check distance along flow direction (timing)
		var abs_flow_dist = abs(flow_distance)
		
		if abs_flow_dist < best_dist:
			best_dist = abs_flow_dist
			best_rock = rock
	
	return best_rock

func jump_to_rock(rock: Area2D, lane_idx: int):
	is_jumping = true
	current_rock = null
	current_lane = lane_idx
	
	# Animate jump to the rock
	var destination = rock.global_position
	var mid = (global_position + destination) / 2.0 + Vector2(0, -20)
	
	var tween = create_tween()
	tween.tween_property(self, "global_position", mid, jump_duration * 0.5)
	tween.tween_property(self, "global_position", destination, jump_duration * 0.5)
	tween.tween_callback(func(): land_on_rock(rock))

func land_on_rock(rock: Area2D):
	is_jumping = false
	if is_instance_valid(rock):
		current_rock = rock
		global_position = rock.global_position
	else:
		fall_in_water()

func jump_to_water(lane_idx: int):
	is_jumping = true
	current_rock = null
	current_lane = lane_idx
	
	# Jump to where we expected a rock to be
	var jump_offset = Vector2(80, 80)
	var destination = global_position + jump_offset
	var mid = (global_position + destination) / 2.0 + Vector2(0, -20)
	
	var tween = create_tween()
	tween.tween_property(self, "global_position", mid, jump_duration * 0.5)
	tween.tween_property(self, "global_position", destination, jump_duration * 0.5)
	tween.tween_callback(fall_in_water)

func jump_to_victory():
	is_jumping = true
	current_rock = null
	current_lane = max_lane
	
	var destination = global_position + Vector2(80, 60)
	var mid = (global_position + destination) / 2.0 + Vector2(0, -20)
	
	var tween = create_tween()
	tween.tween_property(self, "global_position", mid, jump_duration * 0.5)
	tween.tween_property(self, "global_position", destination, jump_duration * 0.5)
	tween.tween_callback(win_game)

func fall_in_water():
	if game_over:
		return
	
	game_over = true
	is_jumping = false
	current_rock = null
	
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.3)
	tween.tween_property(self, "global_position:y", global_position.y + 20, 0.3)
	tween.tween_callback(func(): player_died.emit())

func win_game():
	game_over = true
	is_jumping = false
	player_won.emit()

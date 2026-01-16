extends Node2D

@export var rock_scene: PackedScene

var move_direction: Vector2 = Vector2(-1, 1).normalized()

# Lane configuration
var num_lanes: int = 4
var lane_origins: Array = []

# Each lane has its own fixed speed (set randomly at start)
var lane_speeds: Array = []

# Spawning
var lane_timers: Array = []
var spawn_interval_min: float = 3.0
var spawn_interval_max: float = 5.5

# Spacing
var min_rock_spacing: float = 180.0

func _ready():
	if rock_scene == null:
		rock_scene = load("res://scenes/Rock.tscn")
	
	# Lane origins
	lane_origins = [
		Vector2(-80, -60),
		Vector2(0, 20),
		Vector2(80, 100),
		Vector2(160, 180),
	]
	
	# Assign a FIXED speed to each lane (high variance between lanes)
	# This way rocks in the same lane never catch up to each other
	lane_speeds = [
		randf_range(25, 70),  # Lane 0
		randf_range(25, 70),  # Lane 1
		randf_range(25, 70),  # Lane 2
		randf_range(25, 70),  # Lane 3
	]
	
	# Initialize timers
	for i in range(num_lanes):
		lane_timers.append(randf_range(0.5, 2.5))
	
	# Spawn initial rocks
	for i in range(num_lanes):
		spawn_initial_rocks_in_lane(i)

func _process(delta):
	for i in range(num_lanes):
		lane_timers[i] -= delta
		if lane_timers[i] <= 0:
			lane_timers[i] = randf_range(spawn_interval_min, spawn_interval_max)
			try_spawn_rock_in_lane(i)

func spawn_initial_rocks_in_lane(lane_idx: int):
	var origin = lane_origins[lane_idx]
	
	# Spawn 1-2 rocks with good spacing
	var num_rocks = randi_range(1, 2)
	
	for i in range(num_rocks):
		var offset = 220.0 * i + randf_range(50, 150)
		var pos = origin - move_direction * offset
		
		var perp = Vector2(move_direction.y, -move_direction.x)
		pos += perp * randf_range(-8, 8)
		
		spawn_rock_at_position(lane_idx, pos)

func try_spawn_rock_in_lane(lane_idx: int):
	var spawn_pos = lane_origins[lane_idx] - move_direction * 420
	
	var perp = Vector2(move_direction.y, -move_direction.x)
	spawn_pos += perp * randf_range(-8, 8)
	
	# Check spacing
	var rocks = get_rocks_in_lane(lane_idx)
	for rock in rocks:
		if not is_instance_valid(rock):
			continue
		if spawn_pos.distance_to(rock.global_position) < min_rock_spacing:
			return
	
	spawn_rock_at_position(lane_idx, spawn_pos)

func spawn_rock_at_position(lane_idx: int, pos: Vector2):
	var rock = rock_scene.instantiate()
	rock.global_position = pos
	rock.lane_index = lane_idx
	rock.move_speed = lane_speeds[lane_idx]  # All rocks in same lane = same speed
	rock.move_direction = move_direction
	add_child(rock)

func get_rocks_in_lane(lane_idx: int) -> Array:
	var result = []
	for child in get_children():
		if child is Area2D and child.has_method("get_lane_index"):
			if child.get_lane_index() == lane_idx:
				result.append(child)
	return result

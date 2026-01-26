extends Node2D

@export var rock_scene: PackedScene
@export var lane_paths: Array[NodePath] = []

# Lane configuration
var num_lanes: int = 3
var paths: Array[Path2D] = []

# Each lane has its own fixed speed (set randomly at start)
var lane_speeds: Array = []

# Spawning
var lane_timers: Array = []
var spawn_interval_min: float = 3.0
var spawn_interval_max: float = 5.5

# Spacing - minimum progress difference between rocks in same lane
var min_progress_spacing: float = 0.15

func _ready():
	if rock_scene == null:
		rock_scene = load("res://scenes/Rock.tscn")
	
	# Get Path2D references
	for path_node in lane_paths:
		var path = get_node_or_null(path_node) as Path2D
		if path:
			paths.append(path)
	
	num_lanes = paths.size()
	
	if num_lanes == 0:
		push_warning("RockSpawner: No lane paths assigned!")
		return
	
	# Assign a FIXED speed to each lane (high variance between lanes)
	# This way rocks in the same lane never catch up to each other
	# Speed varies significantly each game (30-120 range)
	for i in range(num_lanes):
		lane_speeds.append(randf_range(30, 120))
	
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
	# Spawn 1-2 rocks at different progress points along the path
	var num_rocks = randi_range(1, 2)
	
	for i in range(num_rocks):
		# Start at different points along the path (0.1 to 0.5)
		var start_progress = 0.1 + (0.2 * i) + randf_range(0, 0.1)
		spawn_rock_at_progress(lane_idx, start_progress)

func try_spawn_rock_in_lane(lane_idx: int):
	var spawn_progress = 0.0  # Start at the beginning of the path
	
	# Check spacing against other rocks in this lane
	var rocks = get_rocks_in_lane(lane_idx)
	for rock in rocks:
		if not is_instance_valid(rock):
			continue
		var rock_progress = rock.get_progress_ratio()
		if abs(rock_progress - spawn_progress) < min_progress_spacing:
			return  # Too close to another rock
	
	spawn_rock_at_progress(lane_idx, spawn_progress)

func spawn_rock_at_progress(lane_idx: int, progress_ratio: float):
	if lane_idx >= paths.size():
		return
	
	var path = paths[lane_idx]
	
	# Create a PathFollow2D for this rock
	var path_follow = PathFollow2D.new()
	path_follow.rotates = false
	path_follow.loop = false
	# Add to tree FIRST, then set progress_ratio
	path.add_child(path_follow)
	path_follow.progress_ratio = progress_ratio
	
	# Instantiate the rock as a child of the PathFollow2D
	var rock = rock_scene.instantiate()
	rock.lane_index = lane_idx
	rock.move_speed = lane_speeds[lane_idx]
	rock.path_follow = path_follow
	path_follow.add_child(rock)

func get_rocks_in_lane(lane_idx: int) -> Array:
	var result = []
	if lane_idx >= paths.size():
		return result
	
	var path = paths[lane_idx]
	for path_follow in path.get_children():
		if path_follow is PathFollow2D:
			for child in path_follow.get_children():
				if child is Area2D and child.has_method("get_lane_index"):
					result.append(child)
	return result

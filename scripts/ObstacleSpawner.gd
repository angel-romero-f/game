extends Node2D

@export var obstacle_scene: PackedScene

# Bridge configuration
var bridge_top: float = -80.0
var bridge_bottom: float = 80.0
var bridge_left: float = -250.0
var bridge_right: float = 250.0

# Obstacle spawn configuration
var num_obstacles: int = 4
var min_speed: float = 60.0
var max_speed: float = 120.0

func _ready():
	if obstacle_scene == null:
		obstacle_scene = load("res://scenes/Obstacle.tscn")
	
	# Spawn obstacles after a brief delay to let the scene initialize
	await get_tree().process_frame
	spawn_obstacles()

func spawn_obstacles():
	# Clear any existing obstacles
	for child in get_children():
		if child.is_in_group("obstacles"):
			child.queue_free()
	
	# Calculate spawn positions spread across the bridge
	var bridge_length = bridge_right - bridge_left
	var section_width = bridge_length / (num_obstacles + 1)
	
	for i in range(num_obstacles):
		var obstacle = obstacle_scene.instantiate()
		
		# Position along the bridge (spread evenly, with some randomness)
		var x_pos = bridge_left + section_width * (i + 1) + randf_range(-30, 30)
		
		# Random vertical position on the bridge
		var y_pos = randf_range(bridge_top + 20, bridge_bottom - 20)
		
		# Random speed (obstacles further along are slightly faster for difficulty curve)
		var difficulty_mult = 1.0 + (float(i) / num_obstacles) * 0.3
		var speed = randf_range(min_speed, max_speed) * difficulty_mult
		
		# Mostly vertical movement, occasional horizontal
		var is_vertical = randf() > 0.2
		
		# Set bounds based on movement type
		var bound_min: float
		var bound_max: float
		if is_vertical:
			bound_min = bridge_top + 10
			bound_max = bridge_bottom - 10
		else:
			# Horizontal obstacles have smaller range
			bound_min = x_pos - 60
			bound_max = x_pos + 60
		
		add_child(obstacle)
		obstacle.setup(Vector2(x_pos, y_pos), speed, is_vertical, bound_min, bound_max)

func set_bridge_bounds(top: float, bottom: float, left: float, right: float):
	bridge_top = top
	bridge_bottom = bottom
	bridge_left = left
	bridge_right = right

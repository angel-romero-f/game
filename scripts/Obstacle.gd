extends Area2D

# Movement settings
var move_speed: float = 150.0
var move_direction: Vector2 = Vector2(0, 1)  # Default: moves vertically

# Boundary for bouncing
var min_bound: float = -80.0
var max_bound: float = 80.0

# Whether this obstacle moves horizontally or vertically
var is_vertical: bool = true

func _ready():
	add_to_group("obstacles")
	
	# Connect collision signal
	body_entered.connect(_on_body_entered)

func _process(delta):
	# Move the obstacle
	global_position += move_direction * move_speed * delta
	
	# Bounce off boundaries
	if is_vertical:
		if global_position.y <= min_bound or global_position.y >= max_bound:
			move_direction.y *= -1
			# Clamp to prevent getting stuck
			global_position.y = clamp(global_position.y, min_bound, max_bound)
	else:
		if global_position.x <= min_bound or global_position.x >= max_bound:
			move_direction.x *= -1
			global_position.x = clamp(global_position.x, min_bound, max_bound)

func _on_body_entered(body: Node2D):
	# Check if it's the player
	if body.is_in_group("player") and body.has_method("hit_obstacle"):
		body.hit_obstacle()

func setup(pos: Vector2, speed: float, vertical: bool, bound_min: float, bound_max: float):
	global_position = pos
	move_speed = speed
	is_vertical = vertical
	min_bound = bound_min
	max_bound = bound_max
	
	if is_vertical:
		move_direction = Vector2(0, 1 if randf() > 0.5 else -1)
	else:
		move_direction = Vector2(1 if randf() > 0.5 else -1, 0)

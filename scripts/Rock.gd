extends Area2D

# Movement
var move_direction: Vector2 = Vector2(-1, 1).normalized()
var move_speed: float = 50.0

# Lane
var lane_index: int = 0

func _ready():
	add_to_group("rocks")

func _process(delta):
	# Move with the river
	global_position += move_direction * move_speed * delta
	
	# Remove when off screen (let spawner create new ones)
	if global_position.x < -450 or global_position.y > 450:
		queue_free()

func get_lane_index() -> int:
	return lane_index

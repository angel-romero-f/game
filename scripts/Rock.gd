extends Area2D

# Movement
var move_speed: float = 50.0

# Lane
var lane_index: int = 0

# Path following
var path_follow: PathFollow2D = null

func _ready():
	add_to_group("rocks")
	
	# If path_follow wasn't set externally, try to get parent
	if path_follow == null:
		var parent = get_parent()
		if parent is PathFollow2D:
			path_follow = parent

func _process(delta):
	if path_follow == null:
		return
	
	# Move along the path by increasing progress
	# move_speed acts as pixels per second along the curve
	path_follow.progress += move_speed * delta
	
	# Remove when we've reached the end of the path
	if path_follow.progress_ratio >= 1.0:
		# Free both the rock and its PathFollow2D parent
		path_follow.queue_free()

func get_lane_index() -> int:
	return lane_index

func get_progress_ratio() -> float:
	if path_follow:
		return path_follow.progress_ratio
	return 0.0

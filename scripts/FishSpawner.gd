extends Node2D

@export var min_spawn_interval: float = 2.0
@export var max_spawn_interval: float = 4.0
@export var min_fish_speed: float = 80.0
@export var max_fish_speed: float = 120.0
@export var spawn_y: float = 0.0  # Y position for fish (under the hole)
@export var spawn_offset_x: float = 300.0  # How far off-screen to spawn
@export var escape_x: float = 350.0  # Where fish escapes

var spawn_timer: float = 0.0
var next_spawn_time: float = 0.0
var active_fish: Array = []
var game_active: bool = true

# Reference to player for miss tracking
var player: Node2D = null

func _ready():
	_schedule_next_spawn()
	await get_tree().process_frame
	player = get_tree().get_first_node_in_group("player")

func _process(delta):
	if not game_active:
		return
	
	spawn_timer += delta
	
	if spawn_timer >= next_spawn_time:
		spawn_fish()
		_schedule_next_spawn()

func _schedule_next_spawn():
	spawn_timer = 0.0
	next_spawn_time = randf_range(min_spawn_interval, max_spawn_interval)

func spawn_fish():
	# Create fish as Area2D with visual
	var fish = Area2D.new()
	fish.name = "Fish"
	
	# Add collision shape
	var collision = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(40, 20)
	collision.shape = shape
	fish.add_child(collision)
	
	# Add visual (simple colored rectangle for now)
	var visual = ColorRect.new()
	visual.size = Vector2(40, 20)
	visual.position = Vector2(-20, -10)  # Center the visual
	visual.color = Color(0.2, 0.4, 0.7, 0.8)  # Blue-ish fish color
	fish.add_child(visual)
	
	# Add fish script behavior
	var fish_script = load("res://scripts/Fish.gd")
	fish.set_script(fish_script)
	
	# Determine spawn side (left or right)
	var from_left = randf() > 0.5
	var start_x = -spawn_offset_x if from_left else spawn_offset_x
	var direction = Vector2.RIGHT if from_left else Vector2.LEFT
	var speed = randf_range(min_fish_speed, max_fish_speed)
	
	add_child(fish)
	fish.setup(Vector2(start_x, spawn_y), direction, speed, escape_x)
	fish.fish_escaped.connect(_on_fish_escaped.bind(fish))
	active_fish.append(fish)

func _on_fish_escaped(fish: Node2D):
	# Fish escaped without being caught - count as a miss for the player
	if player and player.has_method("on_fish_escaped"):
		player.on_fish_escaped()
	active_fish.erase(fish)

func get_active_fish() -> Array:
	# Clean up invalid references
	var valid_fish: Array = []
	for fish in active_fish:
		if is_instance_valid(fish) and not fish.is_caught:
			valid_fish.append(fish)
	active_fish = valid_fish
	return active_fish

func stop_spawning():
	game_active = false

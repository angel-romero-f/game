extends Node2D

@export var enemy_scene: PackedScene
@export var spawn_interval: float = 3.0
@export var max_enemies: int = 10
@export var spawn_distance: float = 100.0  # Distance from screen edge

var spawn_timer: float = 0.0
var viewport_size: Vector2

func _ready():
	# Get viewport size
	viewport_size = get_viewport().get_visible_rect().size
	# Start spawning after a short delay
	spawn_timer = spawn_interval

func _process(delta):
	spawn_timer -= delta
	
	if spawn_timer <= 0:
		spawn_timer = spawn_interval
		try_spawn_enemy()

func try_spawn_enemy():
	# Count current enemies
	var current_enemies = get_tree().get_nodes_in_group("enemies").size()
	
	if current_enemies >= max_enemies:
		return
	
	if enemy_scene == null:
		enemy_scene = load("res://scenes/Enemy.tscn")
	
	# Spawn at random edge position
	var spawn_position = get_random_edge_position()
	var enemy = enemy_scene.instantiate()
	enemy.global_position = spawn_position
	# Add to Enemies container if it exists, otherwise add to scene root
	var enemies_container = get_tree().get_first_node_in_group("enemies_container")
	if enemies_container:
		enemies_container.add_child(enemy)
	else:
		get_tree().current_scene.add_child(enemy)

func get_random_edge_position() -> Vector2:
	# Play area is INSIDE the walls: x from -390 to 390, y from -290 to 290
	# Spawn enemies at random positions along the inner edges of the play area
	var edge = randi() % 4
	var pos = Vector2.ZERO
	
	match edge:
		0:  # Top edge (inside walls, near top)
			pos = Vector2(
				randf_range(-350, 350),
				randf_range(-280, -250)
			)
		1:  # Right edge (inside walls, near right)
			pos = Vector2(
				randf_range(320, 370),
				randf_range(-250, 250)
			)
		2:  # Bottom edge (inside walls, near bottom)
			pos = Vector2(
				randf_range(-350, 350),
				randf_range(250, 280)
			)
		3:  # Left edge (inside walls, near left)
			pos = Vector2(
				randf_range(-370, -320),
				randf_range(-250, 250)
			)
	
	return pos

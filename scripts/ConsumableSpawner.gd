extends Node2D

@export var consumable_scene: PackedScene
@export var spawn_interval: float = 2.0
@export var max_consumables: int = 15
@export var spawn_bounds: Rect2 = Rect2(-350, -250, 700, 500)  # Inside the walls

var spawn_timer: float = 0.0

func _ready():
	if consumable_scene == null:
		consumable_scene = load("res://scenes/Consumable.tscn")
	spawn_timer = spawn_interval
	# Spawn initial consumables
	for i in range(5):
		spawn_consumable()

func _process(delta):
	spawn_timer -= delta
	
	if spawn_timer <= 0:
		spawn_timer = spawn_interval
		try_spawn_consumable()

func try_spawn_consumable():
	var current_consumables = get_tree().get_nodes_in_group("consumables").size()
	
	if current_consumables >= max_consumables:
		return
	
	spawn_consumable()

func spawn_consumable():
	if consumable_scene == null:
		return
	
	var consumable = consumable_scene.instantiate()
	
	# Random position within bounds
	var x = randf_range(spawn_bounds.position.x, spawn_bounds.position.x + spawn_bounds.size.x)
	var y = randf_range(spawn_bounds.position.y, spawn_bounds.position.y + spawn_bounds.size.y)
	consumable.global_position = Vector2(x, y)
	
	# Random item type
	var types = ["health_potion", "mana_potion", "power_up", "gold"]
	consumable.item_type = types[randi() % types.size()]
	
	# Add to scene
	var consumables_container = get_tree().get_first_node_in_group("consumables_container")
	if consumables_container:
		consumables_container.add_child(consumable)
	else:
		get_tree().current_scene.add_child(consumable)
	
	# Connect signal
	if consumable.has_signal("consumable_collected"):
		consumable.consumable_collected.connect(_on_consumable_collected)

func _on_consumable_collected(item_type: String, value: int):
	# Notify player
	var player = get_tree().get_first_node_in_group("player")
	if player:
		player.collect_item(item_type)

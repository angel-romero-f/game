extends CharacterBody2D

@export var speed: float = 200.0
@export var max_health: int = 100

var health: int
var items_collected: int = 0

signal health_changed(new_health)
signal player_died
signal item_collected(item_type: String)
signal items_count_changed(count: int)

func _ready():
	health = max_health
	add_to_group("player")
	health_changed.emit(health)

func _physics_process(_delta):
	# Handle movement
	var input_vector = Vector2.ZERO
	if Input.is_action_pressed("move_up"):
		input_vector.y -= 1
	if Input.is_action_pressed("move_down"):
		input_vector.y += 1
	if Input.is_action_pressed("move_left"):
		input_vector.x -= 1
	if Input.is_action_pressed("move_right"):
		input_vector.x += 1
	
	# Normalize diagonal movement
	if input_vector.length() > 0:
		input_vector = input_vector.normalized()
		velocity = input_vector * speed
	else:
		velocity = Vector2.ZERO
	
	move_and_slide()
	
	# Check for collisions with enemies (contact damage)
	check_enemy_collisions()

func check_enemy_collisions():
	var enemies = get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		if enemy and is_instance_valid(enemy):
			var distance = enemy.global_position.distance_to(global_position)
			if distance < 45.0: # Contact range (player 16px + enemy 14px + buffer)
				if enemy.has_method("deal_contact_damage"):
					enemy.deal_contact_damage()

func take_damage(amount: int):
	health -= amount
	health = max(0, health)
	health_changed.emit(health)
	
	if health <= 0:
		die()

func die():
	player_died.emit()
	# Stop movement
	set_physics_process(false)
	# Could add death animation here

func heal(amount: int):
	health = min(max_health, health + amount)
	health_changed.emit(health)

func collect_item(item_type: String):
	items_collected += 1
	item_collected.emit(item_type)
	items_count_changed.emit(items_collected)

extends CharacterBody2D

@export var speed: float = 100.0
@export var contact_damage: int = 10
@export var damage_cooldown: float = 0.5
@export var separation_radius: float = 60.0  # Distance to maintain from other enemies
@export var separation_strength: float = 80.0  # How strongly to avoid other enemies

var player: Node2D = null
var damage_timer: float = 0.0

func _ready():
	add_to_group("enemies")
	# Find player in scene
	find_player()

func _physics_process(delta):
	# Update damage cooldown
	if damage_timer > 0:
		damage_timer -= delta
	
	# Find player if we don't have a reference
	if player == null or not is_instance_valid(player):
		find_player()
	
	# Move toward player with separation from other enemies
	if player != null and is_instance_valid(player):
		# Direction toward player
		var to_player = (player.global_position - global_position).normalized()
		
		# Calculate separation force from other enemies
		var separation = calculate_separation()
		
		# Combine movement: primarily toward player, but avoid other enemies
		var final_direction = (to_player * speed + separation * separation_strength).normalized()
		velocity = final_direction * speed
		move_and_slide()

func calculate_separation() -> Vector2:
	var separation_force = Vector2.ZERO
	var enemies = get_tree().get_nodes_in_group("enemies")
	
	for enemy in enemies:
		if enemy == self or not is_instance_valid(enemy):
			continue
		
		var to_self = global_position - enemy.global_position
		var distance = to_self.length()
		
		if distance < separation_radius and distance > 0:
			# Push away from nearby enemies, stronger when closer
			var push_strength = (separation_radius - distance) / separation_radius
			separation_force += to_self.normalized() * push_strength
	
	return separation_force

func find_player():
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player = players[0]

func deal_contact_damage():
	# Only deal damage if cooldown is ready
	if damage_timer > 0:
		return
	
	# Try to find player if we don't have reference
	if player == null or not is_instance_valid(player):
		find_player()
	
	if player == null or not is_instance_valid(player):
		return
	
	damage_timer = damage_cooldown
	if player.has_method("take_damage"):
		player.take_damage(contact_damage)

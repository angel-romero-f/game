extends CharacterBody2D

# Movement settings
@export var move_speed: float = 250.0

# Bridge boundaries (set by the game scene)
var bridge_top: float = -80.0
var bridge_bottom: float = 80.0
var bridge_left: float = -300.0
var bridge_right: float = 300.0
var win_x: float = 280.0

# State
var game_over: bool = false

# Walking animation
var walk_time: float = 0.0
var walk_bob_speed: float = 12.0
var walk_bob_amount: float = 3.0

signal player_died
signal player_won

func _ready():
	add_to_group("player")
	_apply_selected_race_visual()

func _apply_selected_race_visual() -> void:
	var visual := get_node_or_null("Visual") as Sprite2D
	if not visual:
		return

	var race := String(App.selected_race).strip_edges()
	if race.is_empty():
		race = "Elf"

	var texture_paths: Array[String] = []
	match race:
		"Fairy":
			texture_paths = [
				"res://pictures/fairy_girl_1/fg1_south.png",
				"res://pictures/fairy_girl_1/fg1_south-east.png",
			]
		"Orc":
			texture_paths = [
				"res://pictures/orc_boy_1/ob1_south.png",
				"res://pictures/orc_boy_1/south-east.png",
			]
		"Infernal":
			texture_paths = [
				"res://pictures/infernal_boy_1/ib1_south.png",
				"res://pictures/infernal_boy_1/south-east.png",
			]
		_:
			# Elf default
			texture_paths = [
				"res://pictures/elf_girl_1/eg1_south.png",
				"res://pictures/elf_girl_1/eg1_east.png",
			]

	for p in texture_paths:
		if FileAccess.file_exists(p):
			var tex := load(p) as Texture2D
			if tex:
				visual.texture = tex
				return

func _physics_process(delta):
	if game_over:
		return
	
	# Get WASD input
	var input_dir := Vector2.ZERO
	
	if Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W):
		input_dir.y -= 1
	if Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S):
		input_dir.y += 1
	if Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A):
		input_dir.x -= 1
	if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D):
		input_dir.x += 1
	
	# Normalize to prevent faster diagonal movement
	if input_dir.length() > 0:
		input_dir = input_dir.normalized()
	
	# Apply movement
	velocity = input_dir * move_speed
	move_and_slide()
	
	# Walking animation
	var visual = get_node_or_null("Visual")
	if visual:
		if input_dir.length() > 0:
			# Bobbing animation while moving
			walk_time += delta * walk_bob_speed
			visual.position.y = -10 + sin(walk_time) * walk_bob_amount
			
			# Flip sprite based on horizontal direction
			if input_dir.x < 0:
				visual.flip_h = true
			elif input_dir.x > 0:
				visual.flip_h = false
		else:
			# Reset to neutral position when not moving
			visual.position.y = -10
			walk_time = 0.0
	
	# Check boundaries
	_check_boundaries()
	
	# Check win condition
	if global_position.x >= win_x:
		win_game()

func _check_boundaries():
	# Check if player fell off the bridge (top or bottom)
	if global_position.y < bridge_top or global_position.y > bridge_bottom:
		fall_off_bridge()
		return
	
	# Clamp horizontal position (can't go backwards off the start)
	global_position.x = clamp(global_position.x, bridge_left, bridge_right + 50)

func fall_off_bridge():
	if game_over:
		return
	
	game_over = true
	
	# Fade out animation
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.3)
	tween.tween_callback(func(): player_died.emit())

func hit_obstacle():
	if game_over:
		return
	
	game_over = true
	
	# Flash red and fade out
	modulate = Color.RED
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.3)
	tween.tween_callback(func(): player_died.emit())

func win_game():
	if game_over:
		return
	
	game_over = true
	player_won.emit()

func set_bridge_bounds(top: float, bottom: float, left: float, right: float, win_threshold: float):
	bridge_top = top
	bridge_bottom = bottom
	bridge_left = left
	bridge_right = right
	win_x = win_threshold

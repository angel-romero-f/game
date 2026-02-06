extends Area2D

@export var speed: float = 100.0
var direction: Vector2 = Vector2.RIGHT
var is_caught: bool = false
var escape_x: float = 400.0  # X position where fish escapes

signal fish_escaped

func _ready():
	# Fish starts moving immediately
	pass

func _process(delta):
	if is_caught:
		return
	
	# Move the fish
	global_position += direction * speed * delta
	
	# Check if fish escaped (went past the catch zone)
	if direction.x > 0 and global_position.x > escape_x:
		_on_escaped()
	elif direction.x < 0 and global_position.x < -escape_x:
		_on_escaped()

func setup(start_pos: Vector2, move_direction: Vector2, move_speed: float, escape_position: float):
	global_position = start_pos
	direction = move_direction.normalized()
	speed = move_speed
	escape_x = escape_position

func on_caught():
	is_caught = true
	# Animate catch - scale up and fade out
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector2(1.5, 1.5), 0.2)
	tween.tween_property(self, "modulate:a", 0.0, 0.3)
	tween.chain().tween_callback(queue_free)

func _on_escaped():
	fish_escaped.emit()
	queue_free()

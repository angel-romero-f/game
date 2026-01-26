extends Node2D

var game_over: bool = false
var player_won: bool = false

@onready var background: AnimatedSprite2D = $Background

var waterfall_frame: int = 0
var waterfall_timer: float = 0.0
const WATERFALL_FRAME_DURATION: float = 0.15  # Time per frame in seconds

func _ready():
	# Setup waterfall background to only alternate between frames 0 and 1
	if background:
		background.stop()  # Stop the autoplay animation
		background.frame = 0
	
	# Connect to player signals
	var player = get_tree().get_first_node_in_group("player")
	if player:
		if player.has_signal("player_died"):
			player.player_died.connect(_on_player_died)
		if player.has_signal("player_won"):
			player.player_won.connect(_on_player_won)

func _process(delta: float) -> void:
	# Manually animate waterfall background between frames 0 and 1 only
	if background:
		waterfall_timer += delta
		if waterfall_timer >= WATERFALL_FRAME_DURATION:
			waterfall_timer = 0.0
			waterfall_frame = 1 - waterfall_frame  # Toggle between 0 and 1
			background.frame = waterfall_frame

func _on_player_died():
	game_over = true
	player_won = false
	# UI will handle showing game over panel

func _on_player_won():
	game_over = true
	player_won = true
	# UI will handle showing win panel

func _input(event):
	if event is InputEventKey and event.keycode == KEY_R and event.pressed:
		handle_continue()

func handle_continue():
	if not game_over:
		return
	
	if player_won:
		# Won - return to map
		_return_to_map()
	elif App.get_lives() <= 0:
		# Final death - reset lives and return to map
		App.reset_lives()
		_return_to_map()
	else:
		# Still have lives - restart minigame
		get_tree().reload_current_scene()

func _return_to_map():
	App.go("res://scenes/ui/GameIntro.tscn")

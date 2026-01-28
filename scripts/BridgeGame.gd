extends Node2D

var game_over: bool = false
var player_won: bool = false

# Bridge dimensions
const BRIDGE_TOP: float = -80.0
const BRIDGE_BOTTOM: float = 80.0
const BRIDGE_LEFT: float = -280.0
const BRIDGE_RIGHT: float = 280.0
const WIN_X: float = 260.0

func _ready():
	# Configure player bounds
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_method("set_bridge_bounds"):
		player.set_bridge_bounds(BRIDGE_TOP, BRIDGE_BOTTOM, BRIDGE_LEFT, BRIDGE_RIGHT, WIN_X)
	
	# Configure obstacle spawner
	var spawner = get_node_or_null("ObstacleSpawner")
	if spawner and spawner.has_method("set_bridge_bounds"):
		spawner.set_bridge_bounds(BRIDGE_TOP, BRIDGE_BOTTOM, BRIDGE_LEFT + 80, BRIDGE_RIGHT - 40)
	
	# Connect to player signals
	if player:
		if player.has_signal("player_died"):
			player.player_died.connect(_on_player_died)
		if player.has_signal("player_won"):
			player.player_won.connect(_on_player_won)

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
		# Won - report completion and return to map
		App.on_minigame_completed()
		_return_to_map()
	elif App.get_lives() <= 0:
		# Final death - reset lives, count as played, and return to map
		App.reset_lives()
		App.on_minigame_completed()
		_return_to_map()
	else:
		# Still have lives - restart minigame
		get_tree().reload_current_scene()

func _return_to_map():
	# Ensure main music is playing when returning to map
	# (Battle music only plays in the actual battle scene, not on the map)
	App.play_main_music()
	App.go("res://scenes/ui/GameIntro.tscn")

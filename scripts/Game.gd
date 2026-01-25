extends Node2D

var game_over: bool = false
var player_won: bool = false

func _ready():
	# Connect to player signals
	var player = get_tree().get_first_node_in_group("player")
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

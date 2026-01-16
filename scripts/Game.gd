extends Node2D

var game_over: bool = false

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
	# UI will handle showing game over panel

func _on_player_won():
	game_over = true
	# UI will handle showing win panel

func _input(event):
	if event is InputEventKey and event.keycode == KEY_R and event.pressed:
		restart_game()

func restart_game():
	get_tree().reload_current_scene()

extends Node2D

var game_over: bool = false
var player_won: bool = false
var _has_returned: bool = false

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
	if _has_returned:
		return
	_has_returned = true
	
	if player_won:
		# Won - award card, report completion and return to map
		App.add_card_from_minigame_win()
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
	App.play_main_music()
	App.go("res://scenes/ui/game_intro.tscn")

extends CanvasLayer

@onready var game_over_panel: Panel = $UI/GameOverPanel
@onready var game_over_label: Label = $UI/GameOverPanel/GameOverLabel
@onready var win_panel: Panel = $UI/WinPanel
@onready var win_label: Label = $UI/WinPanel/WinLabel

var player: Node2D = null

func _ready():
	game_over_panel.visible = false
	win_panel.visible = false
	
	# Wait a frame for scene to be ready
	await get_tree().process_frame
	
	# Find player and connect signals
	find_player()

func find_player():
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player = players[0]
		if player.has_signal("player_died"):
			player.player_died.connect(_on_player_died)
		if player.has_signal("player_won"):
			player.player_won.connect(_on_player_won)

func _on_player_died():
	show_game_over()

func _on_player_won():
	show_win()

func show_game_over():
	game_over_panel.visible = true
	if game_over_label:
		game_over_label.text = "Game Over!\nYou fell in the water!\nPress R to Restart"

func show_win():
	win_panel.visible = true
	if win_label:
		win_label.text = "You Made It!\nYou crossed the river!\nPress R to Play Again"

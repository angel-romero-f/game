extends CanvasLayer

@onready var health_bar: ProgressBar = $UI/HealthBar
@onready var items_label: Label = $UI/ItemsLabel
@onready var timer_label: Label = $UI/TimerLabel
@onready var game_over_panel: Panel = $UI/GameOverPanel
@onready var game_over_label: Label = $UI/GameOverPanel/GameOverLabel
@onready var phase_complete_panel: Panel = $UI/PhaseCompletePanel
@onready var phase_complete_label: Label = $UI/PhaseCompletePanel/PhaseCompleteLabel

var player: Node2D = null
var game_manager: Node2D = null
var phase_complete: bool = false

func _ready():
	game_over_panel.visible = false
	phase_complete_panel.visible = false
	# Wait a frame for scene to be ready
	await get_tree().process_frame
	# Find player and connect signals
	find_player()
	# Find game manager
	find_game_manager()
	# Connect to enemy deaths
	connect_enemy_signals()

func find_player():
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player = players[0]
		# Set health bar max value
		if health_bar and player:
			# Access max_health directly since it's an exported variable
			health_bar.max_value = player.max_health
			health_bar.value = player.health
		if player.has_signal("health_changed"):
			player.health_changed.connect(_on_player_health_changed)
		if player.has_signal("player_died"):
			player.player_died.connect(_on_player_died)
		if player.has_signal("items_count_changed"):
			player.items_count_changed.connect(_on_items_count_changed)

func find_game_manager():
	game_manager = get_tree().current_scene
	if game_manager and game_manager.has_signal("time_up"):
		game_manager.time_up.connect(_on_time_up)
	if game_manager and game_manager.has_signal("phase_completed"):
		game_manager.phase_completed.connect(_on_phase_completed)

func connect_enemy_signals():
	# Connect to existing enemies
	var enemies = get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		if enemy.has_signal("enemy_died") and not enemy.enemy_died.is_connected(_on_enemy_died):
			enemy.enemy_died.connect(_on_enemy_died)
	
	# Set up to connect to new enemies
	get_tree().node_added.connect(_on_node_added)

func _on_node_added(node: Node):
	if node.is_in_group("enemies") and node.has_signal("enemy_died"):
		if not node.enemy_died.is_connected(_on_enemy_died):
			node.enemy_died.connect(_on_enemy_died)

func _on_player_health_changed(new_health: int):
	if health_bar:
		health_bar.value = new_health

func _on_player_died():
	show_game_over()

func _on_enemy_died():
	pass  # No longer tracking enemy kills

func _on_items_count_changed(count: int):
	if items_label:
		items_label.text = "Items Collected: " + str(count)

func _process(delta):
	if game_manager and not phase_complete:
		update_timer()

func update_timer():
	if timer_label and game_manager:
		var time = game_manager.time_remaining
		var seconds = int(time)
		var milliseconds = int((time - seconds) * 100)
		timer_label.text = "Time: %02d.%02d" % [seconds, milliseconds]

func _on_time_up():
	phase_complete = true

func _on_phase_completed(items_collected: int):
	show_phase_complete(items_collected)

func show_phase_complete(items_collected: int):
	phase_complete_panel.visible = true
	if phase_complete_label:
		phase_complete_label.text = "Phase Complete!\nItems Collected: " + str(items_collected) + "\nPress R or Enter to Restart"

func is_phase_complete() -> bool:
	return phase_complete

func show_game_over():
	game_over_panel.visible = true
	if game_over_label:
		game_over_label.text = "Game Over!\nPress R or Enter to Restart"

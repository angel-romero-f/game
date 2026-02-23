extends Node2D

var game_over: bool = false
var player_won: bool = false
var _has_returned: bool = false

# ---------- 30-SECOND TIMER ----------
const MINIGAME_TIME_LIMIT: float = 30.0
var _minigame_timer: float = MINIGAME_TIME_LIMIT
var _timer_active: bool = false

@onready var background: AnimatedSprite2D = $Background

var waterfall_frame: int = 0
var waterfall_timer: float = 0.0
const WATERFALL_FRAME_DURATION: float = 0.15  # Time per frame in seconds

func _ready():
	# Setup waterfall background to only alternate between frames 0 and 1
	if background:
		background.stop()  # Stop the autoplay animation
		background.frame = 0
	
	# Reset lives for a fresh minigame session
	App.reset_lives()
	
	# Connect to player signals
	var player = get_tree().get_first_node_in_group("player")
	if player:
		if player.has_signal("player_died"):
			player.player_died.connect(_on_player_died)
		if player.has_signal("player_won"):
			player.player_won.connect(_on_player_won)
	
	# Start the countdown timer
	_minigame_timer = MINIGAME_TIME_LIMIT
	_timer_active = true
	print("[Minigame:River] Timer started (%.0fs)" % MINIGAME_TIME_LIMIT)

func _process(delta: float) -> void:
	# Manually animate waterfall background between frames 0 and 1 only
	if background:
		waterfall_timer += delta
		if waterfall_timer >= WATERFALL_FRAME_DURATION:
			waterfall_timer = 0.0
			waterfall_frame = 1 - waterfall_frame  # Toggle between 0 and 1
			background.frame = waterfall_frame

	# Countdown timer
	if _timer_active and not game_over:
		_minigame_timer -= delta
		# Update UI — CanvasLayer node is named "UI" in the scene tree
		var ui := get_node_or_null("UI")
		if ui and ui.has_method("update_timer_display"):
			ui.update_timer_display(_minigame_timer)
		if _minigame_timer <= 0.0:
			_on_timeout()

func _on_timeout() -> void:
	_timer_active = false
	if game_over:
		return
	print("[Minigame:River] Time's up! Treating as loss.")
	game_over = true
	player_won = false
	var ui := get_node_or_null("UI")
	if ui and ui.has_method("show_timeout"):
		ui.show_timeout()

func _on_player_died():
	_timer_active = false
	game_over = true
	player_won = false
	# UI will handle showing game over panel

func _on_player_won():
	_timer_active = false
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
		# Won - award pre-rolled card, report completion and return to map
		App.add_card_from_pending_reward()
		App.on_minigame_completed()
		_return_to_map()
	elif App.get_lives() <= 0:
		# Final death / timeout exhausted lives - reset and return
		App.reset_lives()
		App.pending_minigame_reward.clear()
		App.on_minigame_completed()
		_return_to_map()
	else:
		# Still have lives - restart minigame (timer + lives persist via App)
		get_tree().reload_current_scene()

func _return_to_map():
	# Ensure main music is playing when returning to map
	App.play_main_music()
	App.go("res://scenes/ui/GameIntro.tscn")

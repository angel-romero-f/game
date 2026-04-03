extends Node2D

var game_over: bool = false
var player_won: bool = false
var _has_returned: bool = false

# ---------- 20-SECOND TIMER ----------
const MINIGAME_TIME_LIMIT: float = 20.0
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
	
	# Only reset lives on first load (not on retry reloads)
	if App.minigame_time_remaining <= 0.0:
		App.reset_lives()
	
	# Connect to player signals
	var player = get_tree().get_first_node_in_group("player")
	if player:
		if player.has_signal("player_died"):
			player.player_died.connect(_on_player_died)
		if player.has_signal("player_won"):
			player.player_won.connect(_on_player_won)
	
	# Start countdown timer — persist across retries
	if App.minigame_time_remaining > 0.0:
		_minigame_timer = App.minigame_time_remaining
	else:
		_minigame_timer = MINIGAME_TIME_LIMIT
		App.minigame_time_remaining = _minigame_timer
	_timer_active = true
	print("[Minigame:River] Timer started (%.1fs)" % _minigame_timer)

func _process(delta: float) -> void:
	# Manually animate waterfall background between frames 0 and 1 only
	if background:
		waterfall_timer += delta
		if waterfall_timer >= WATERFALL_FRAME_DURATION:
			waterfall_timer = 0.0
			waterfall_frame = 1 - waterfall_frame  # Toggle between 0 and 1
			background.frame = waterfall_frame

	# Countdown timer — keeps running even during death screen
	if _timer_active:
		_minigame_timer -= delta
		App.minigame_time_remaining = _minigame_timer
		# Update UI
		var ui := get_node_or_null("UI")
		if ui and ui.has_method("update_timer_display"):
			ui.update_timer_display(_minigame_timer)
		if _minigame_timer <= 0.0:
			_on_timeout()

func _on_timeout() -> void:
	_timer_active = false
	if _has_returned:
		return
	_has_returned = true
	print("[Minigame:River] Time's up! Returning to map.")
	game_over = true
	player_won = false
	# Timeout = loss, return to map immediately
	App.minigame_time_remaining = -1.0
	App.reset_lives()
	App.pending_minigame_reward.clear()
	App.on_minigame_completed()
	_return_to_map()

func _on_player_died():
	# Don't stop the timer — it keeps counting down during the retry prompt
	game_over = true
	player_won = false
	App.lose_life()

func _on_player_won():
	_timer_active = false
	game_over = true
	player_won = true

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
		App.minigame_time_remaining = -1.0
		App.add_card_from_pending_reward()
		App.on_minigame_completed()
		_return_to_map()
	elif App.get_lives() <= 0:
		App.minigame_time_remaining = -1.0
		App.reset_lives()
		App.pending_minigame_reward.clear()
		App.pending_bonus_reward.clear()
		App.region_bonus_active = false
		App.on_minigame_completed()
		_return_to_map()
	else:
		# Save timer and reload — timer + lives persist
		App.minigame_time_remaining = _minigame_timer
		get_tree().reload_current_scene()

func _return_to_map():
	App.play_main_music()
	App.go("res://scenes/ui/game_intro.tscn")

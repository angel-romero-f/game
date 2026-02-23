extends Node2D

var game_over: bool = false
var player_won: bool = false
var _has_returned: bool = false

# ---------- 30-SECOND TIMER ----------
const MINIGAME_TIME_LIMIT: float = 30.0
var _minigame_timer: float = MINIGAME_TIME_LIMIT
var _timer_active: bool = false

func _ready():
	# Reset lives for a fresh minigame session
	App.reset_lives()
	
	# Connect to player signals
	var player = get_tree().get_first_node_in_group("player")
	if player:
		if player.has_signal("player_died"):
			player.player_died.connect(_on_player_died)
		if player.has_signal("player_won"):
			player.player_won.connect(_on_player_won)
	
	# Start countdown timer
	_minigame_timer = MINIGAME_TIME_LIMIT
	_timer_active = true
	print("[Minigame:IceFishing] Timer started (%.0fs)" % MINIGAME_TIME_LIMIT)

func _process(delta: float) -> void:
	# Countdown timer
	if _timer_active and not game_over:
		_minigame_timer -= delta
		var ui := get_node_or_null("UI")
		if ui and ui.has_method("update_timer_display"):
			ui.update_timer_display(_minigame_timer)
		if _minigame_timer <= 0.0:
			_on_timeout()

func _on_timeout() -> void:
	_timer_active = false
	if game_over:
		return
	print("[Minigame:IceFishing] Time's up! Treating as loss.")
	game_over = true
	player_won = false
	var ui := get_node_or_null("UI")
	if ui and ui.has_method("show_timeout"):
		ui.show_timeout()

func _on_player_died():
	_timer_active = false
	game_over = true
	player_won = false

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
		App.add_card_from_pending_reward()
		App.on_minigame_completed()
		_return_to_map()
	elif App.get_lives() <= 0:
		App.reset_lives()
		App.pending_minigame_reward.clear()
		App.on_minigame_completed()
		_return_to_map()
	else:
		get_tree().reload_current_scene()

func _return_to_map():
	App.play_main_music()
	App.go("res://scenes/ui/GameIntro.tscn")

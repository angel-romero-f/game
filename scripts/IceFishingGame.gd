extends Node2D

var game_over: bool = false
var player_won: bool = false
var _has_returned: bool = false
const ICE_FISHING_MUSIC_PATH := "res://music/ice fishing.mp3"
const PERSISTENT_ICE_FISHING_PLAYER_NAME := "PersistentIceFishingMusic"
var _ice_fishing_music_player: AudioStreamPlayer = null

# ---------- 30-SECOND TIMER ----------
const MINIGAME_TIME_LIMIT: float = 30.0
var _minigame_timer: float = MINIGAME_TIME_LIMIT
var _timer_active: bool = false

func _ready():
	_setup_ice_fishing_music()

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
	print("[Minigame:IceFishing] Timer started (%.1fs)" % _minigame_timer)

func _setup_ice_fishing_music() -> void:
	# Ice fishing music is exclusive to this minigame.
	App.stop_gameplay_music()

	var root := get_tree().root
	var existing := root.get_node_or_null(PERSISTENT_ICE_FISHING_PLAYER_NAME)
	if existing and existing is AudioStreamPlayer:
		_ice_fishing_music_player = existing as AudioStreamPlayer
		if not _ice_fishing_music_player.playing:
			_ice_fishing_music_player.play()
		return

	var stream := load(ICE_FISHING_MUSIC_PATH)
	if not stream is AudioStream:
		push_warning("[Minigame:IceFishing] Missing or invalid music at %s" % ICE_FISHING_MUSIC_PATH)
		return

	_ice_fishing_music_player = AudioStreamPlayer.new()
	_ice_fishing_music_player.name = PERSISTENT_ICE_FISHING_PLAYER_NAME
	_ice_fishing_music_player.bus = "Music"
	_ice_fishing_music_player.stream = stream
	root.add_child(_ice_fishing_music_player)

	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true

	_ice_fishing_music_player.play()

func _stop_ice_fishing_music() -> void:
	if _ice_fishing_music_player and is_instance_valid(_ice_fishing_music_player):
		_ice_fishing_music_player.stop()
		_ice_fishing_music_player.queue_free()
	_ice_fishing_music_player = null

func _process(delta: float) -> void:
	# Countdown timer — keeps running even during death screen
	if _timer_active:
		_minigame_timer -= delta
		App.minigame_time_remaining = _minigame_timer
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
	print("[Minigame:IceFishing] Time's up! Returning to map.")
	game_over = true
	player_won = false
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
		App.minigame_time_remaining = _minigame_timer
		get_tree().reload_current_scene()

func _return_to_map():
	_stop_ice_fishing_music()
	App.go("res://scenes/ui/game_intro.tscn")

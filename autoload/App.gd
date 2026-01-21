extends Node

## Simple scene navigation helper + small UI state
var player_name: String = ""
var next_scene: String = ""

var main_music: AudioStreamPlayer
var ui_sfx: AudioStreamPlayer
var blip_select_stream: AudioStream

func _ready() -> void:
	# Create and start main music immediately on game launch
	main_music = AudioStreamPlayer.new()
	main_music.name = "MainMusic"
	add_child(main_music)
	
	# Load the music stream
	var stream: AudioStreamMP3 = load("res://music/main_music.mp3")
	if stream == null and FileAccess.file_exists("res://music/main_music.mp3"):
		stream = AudioStreamMP3.new()
		stream.data = FileAccess.get_file_as_bytes("res://music/main_music.mp3")
	
	if stream:
		stream.loop = true
		main_music.stream = stream
		main_music.play()
		print("Main music started from App autoload")

	# UI SFX (button blips, etc.)
	ui_sfx = AudioStreamPlayer.new()
	ui_sfx.name = "UISfx"
	add_child(ui_sfx)
	blip_select_stream = load("res://sounds/blipSelect.wav")
	if blip_select_stream:
		ui_sfx.stream = blip_select_stream

	# Auto-hook any buttons added to the scene tree (covers all screens/scenes).
	if not get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.connect(_on_node_added)
	call_deferred("_hook_buttons_on_current_scene")

func go(path: String) -> void:
	get_tree().change_scene_to_file(path)
	call_deferred("_hook_buttons_on_current_scene")

func set_player_name(name: String) -> void:
	player_name = name.strip_edges()

func set_next_scene(path: String) -> void:
	next_scene = path

func stop_main_music() -> void:
	if main_music and main_music.playing:
		main_music.stop()

func play_main_music() -> void:
	if main_music and not main_music.playing:
		main_music.play()

func play_blip_select() -> void:
	if not ui_sfx or not ui_sfx.stream:
		return
	# Restart so rapid presses still feel responsive.
	if ui_sfx.playing:
		ui_sfx.stop()
	ui_sfx.play()

func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		_connect_button_sfx(node)

func _hook_buttons_on_current_scene() -> void:
	var scene := get_tree().current_scene
	if scene:
		_hook_buttons_recursive(scene)

func _hook_buttons_recursive(root: Node) -> void:
	if root is BaseButton:
		_connect_button_sfx(root)
	for child in root.get_children():
		_hook_buttons_recursive(child)

func _connect_button_sfx(button: BaseButton) -> void:
	var cb := Callable(self, "play_blip_select")
	if not button.pressed.is_connected(cb):
		button.pressed.connect(cb)

extends Node

## WinConditionManager
## Monitors territory claims each frame. When any player owns a colony in
## 5 of the 6 regions, that player wins. Uses its own CanvasLayer so the
## victory overlay renders on top of ALL scenes (map, minigames, battles).

const REGIONS_TO_WIN: int = 5

## Territory -> Region mapping (mirrors TerritoryManager.TERRITORY_REGIONS)
const TERRITORY_REGIONS: Dictionary = {
	2: 1, 4: 1,
	5: 2, 6: 2,
	3: 3, 1: 3,
	8: 4, 10: 4,
	11: 5, 7: 5,
	9: 6, 12: 6
}

signal player_won(player_id: int)

var monitoring: bool = false

# ---- CanvasLayer UI nodes ----
var _canvas_layer: CanvasLayer
var _victory_overlay: ColorRect
var _victory_background: TextureRect
var _victory_label: Label
var _main_menu_button: Button


func _ready() -> void:
	_build_ui()


func _process(_delta: float) -> void:
	if not monitoring:
		return

	var winner_id: int = _determine_winner()
	if winner_id != -1:
		monitoring = false
		player_won.emit(winner_id)
		_show_victory(winner_id)
		get_tree().paused = true


# ---------- PUBLIC API ----------

## Call once after intro completes. Enables per-frame region ownership checks.
## In multiplayer the host broadcasts via RPC; in single-player starts directly.
func start_timer() -> void:
	if monitoring:
		return
	if App.is_multiplayer and App.get_tree().get_multiplayer().has_multiplayer_peer():
		if App.get_tree().get_multiplayer().is_server():
			rpc_start_monitoring.rpc()
	else:
		monitoring = true


@rpc("authority", "call_local", "reliable")
func rpc_start_monitoring() -> void:
	monitoring = true


# ---------- INTERNALS ----------

func _determine_winner() -> int:
	var tcs: Node = get_node_or_null("/root/TerritoryClaimState")
	if not tcs:
		return -1

	var claims_val: Variant = tcs.get("claims")
	if not claims_val is Dictionary:
		return -1

	var claims: Dictionary = claims_val
	var player_regions: Dictionary = {}  # player_id -> { region_id: true }

	for tid_key in claims:
		var claim_data: Dictionary = claims[tid_key]
		var owner_id: Variant = claim_data.get("owner_player_id", null)
		if owner_id == null:
			continue
		var pid: int = int(owner_id)
		var region_id: int = TERRITORY_REGIONS.get(int(tid_key), -1)
		if region_id < 0:
			continue
		if not player_regions.has(pid):
			player_regions[pid] = {}
		player_regions[pid][region_id] = true

	for p in App.turn_order:
		var pid: int = int(p.get("id", -1))
		if player_regions.has(pid) and player_regions[pid].size() >= REGIONS_TO_WIN:
			return pid

	return -1


func _show_victory(player_id: int) -> void:
	var player_name: String = "Player"
	for p in App.game_players:
		if int(p.get("id", -1)) == player_id:
			player_name = str(p.get("name", "Player"))
			break

	if _victory_label:
		_victory_label.text = "%s Wins!" % player_name
	if _victory_overlay:
		_victory_overlay.visible = true

	# Determine if the local player is the winner and play the appropriate music.
	var local_id: int
	if App.is_multiplayer and multiplayer.has_multiplayer_peer():
		local_id = multiplayer.get_unique_id()
	else:
		local_id = -1
		for p in App.game_players:
			if p.get("is_local", false):
				local_id = int(p.get("id", -1))
				break

	if local_id == player_id:
		App.play_win_music()
	else:
		App.play_lose_music()


func _on_main_menu_pressed() -> void:
	get_tree().paused = false
	monitoring = false
	if _victory_overlay:
		_victory_overlay.visible = false
	App.stop_all_music()
	App._menu_music_stopped = false
	App.play_menu_music()
	App.go("res://scenes/ui/MainMenu.tscn")


# ---------- UI CONSTRUCTION ----------

func _build_ui() -> void:
	_canvas_layer = CanvasLayer.new()
	_canvas_layer.name = "WinTimerCanvas"
	_canvas_layer.layer = 100
	_canvas_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_canvas_layer)

	# ---- Victory overlay (full-screen, hidden) ----
	_victory_overlay = ColorRect.new()
	_victory_overlay.name = "VictoryOverlay"
	_victory_overlay.visible = false
	_victory_overlay.color = Color(0, 0, 0, 0.8)
	_victory_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas_layer.add_child(_victory_overlay)

	# Background image for win screen (first frame of assets/win_screen_bg.pxo)
	_victory_background = TextureRect.new()
	_victory_background.name = "VictoryBackground"
	_victory_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_victory_background.stretch_mode = TextureRect.STRETCH_SCALE
	_victory_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_victory_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_victory_overlay.add_child(_victory_background)

	var bg_frames: SpriteFrames = load("res://assets/win_screen_bg.pxo") as SpriteFrames
	if bg_frames and bg_frames.has_animation("default") and bg_frames.get_frame_count("default") > 0:
		var bg_tex: Texture2D = bg_frames.get_frame_texture("default", 0)
		_victory_background.texture = bg_tex

	_victory_label = Label.new()
	_victory_label.name = "VictoryLabel"
	_victory_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_victory_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_victory_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_victory_label.add_theme_font_override("font", load("res://fonts/m5x7.ttf"))
	_victory_label.add_theme_font_size_override("font_size", 64)
	_victory_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.55, 1.0))
	_victory_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	_victory_label.add_theme_constant_override("outline_size", 6)
	_victory_label.text = ""
	_victory_overlay.add_child(_victory_label)

	_main_menu_button = Button.new()
	_main_menu_button.name = "MainMenuButton"
	_main_menu_button.text = "Main Menu"
	_main_menu_button.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_main_menu_button.offset_left = -80.0
	_main_menu_button.offset_top = -100.0
	_main_menu_button.offset_right = 80.0
	_main_menu_button.offset_bottom = -60.0
	_main_menu_button.add_theme_font_override("font", load("res://fonts/m5x7.ttf"))
	_main_menu_button.add_theme_font_size_override("font_size", 28)
	_main_menu_button.pressed.connect(_on_main_menu_pressed)
	_victory_overlay.add_child(_main_menu_button)

extends Node

## WinConditionManager
## 6-minute game timer. When the timer expires, the player with the most
## territories wins. Uses its own CanvasLayer so the timer label and victory
## overlay render on top of ALL scenes (map, minigames, battles).

const GAME_DURATION: float = 360.0  # 6 minutes

var time_remaining: float = 0.0
var timer_active: bool = false

# ---- CanvasLayer UI nodes ----
var _canvas_layer: CanvasLayer
var _timer_label: Label
var _victory_overlay: ColorRect
var _victory_background: TextureRect
var _victory_label: Label
var _main_menu_button: Button


func _ready() -> void:
	_build_ui()


func _process(delta: float) -> void:
	if not timer_active:
		return

	time_remaining -= delta

	# Update label text
	if _timer_label:
		var clamped: float = maxf(time_remaining, 0.0)
		var minutes: int = int(clamped) / 60
		var seconds: int = int(clamped) % 60
		_timer_label.text = "%d:%02d" % [minutes, seconds]
		if time_remaining <= 30.0:
			_timer_label.add_theme_color_override("font_color", Color(1.0, 0.25, 0.2, 1.0))

	if time_remaining <= 0.0:
		_on_timer_expired()


# ---------- PUBLIC API ----------

## Call once after intro completes. In multiplayer the host broadcasts via RPC;
## in single-player it starts directly. Guards against double-start.
func start_timer() -> void:
	if timer_active:
		return
	if App.is_multiplayer and App.get_tree().get_multiplayer().has_multiplayer_peer():
		if App.get_tree().get_multiplayer().is_server():
			rpc_start_timer.rpc(GAME_DURATION)
	else:
		_activate_timer(GAME_DURATION)


@rpc("authority", "call_local", "reliable")
func rpc_start_timer(duration: float) -> void:
	_activate_timer(duration)


# ---------- INTERNALS ----------

func _activate_timer(duration: float) -> void:
	if timer_active:
		return
	time_remaining = duration
	timer_active = true
	if _timer_label:
		_timer_label.visible = true


func _on_timer_expired() -> void:
	timer_active = false
	time_remaining = 0.0
	var winner_id: int = _determine_winner()
	_show_victory(winner_id)
	get_tree().paused = true


func _determine_winner() -> int:
	var tcs: Node = get_node_or_null("/root/TerritoryClaimState")
	if not tcs:
		# Fallback: first in turn order
		if App.turn_order.size() > 0:
			return int(App.turn_order[0].get("id", -1))
		return -1

	var claims_val: Variant = tcs.get("claims")
	if not claims_val is Dictionary:
		if App.turn_order.size() > 0:
			return int(App.turn_order[0].get("id", -1))
		return -1

	var claims: Dictionary = claims_val
	var counts: Dictionary = {}  # player_id -> territory count

	for tid_key in claims:
		var claim_data: Dictionary = claims[tid_key]
		var owner_id: Variant = claim_data.get("owner_player_id", null)
		if owner_id == null:
			continue
		var pid: int = int(owner_id)
		counts[pid] = counts.get(pid, 0) + 1

	# Find max count
	var best_id: int = -1
	var best_count: int = -1
	# Iterate in turn_order for deterministic tie-breaking (first in order wins)
	for p in App.turn_order:
		var pid: int = int(p.get("id", -1))
		var c: int = counts.get(pid, 0)
		if c > best_count:
			best_count = c
			best_id = pid

	return best_id


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


func _on_main_menu_pressed() -> void:
	get_tree().paused = false
	timer_active = false
	time_remaining = 0.0
	if _victory_overlay:
		_victory_overlay.visible = false
	if _timer_label:
		_timer_label.visible = false
	App.go("res://scenes/ui/MainMenu.tscn")


# ---------- UI CONSTRUCTION ----------

func _build_ui() -> void:
	_canvas_layer = CanvasLayer.new()
	_canvas_layer.name = "WinTimerCanvas"
	_canvas_layer.layer = 100
	_canvas_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_canvas_layer)

	# ---- Timer label (top-center, right of phase indicator bar) ----
	_timer_label = Label.new()
	_timer_label.name = "TimerLabel"
	_timer_label.visible = false
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_timer_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_timer_label.add_theme_font_override("font", load("res://fonts/m5x7.ttf"))
	_timer_label.add_theme_font_size_override("font_size", 36)
	_timer_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	_timer_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	_timer_label.add_theme_constant_override("outline_size", 4)
	_timer_label.anchor_left = 0.5
	_timer_label.anchor_right = 0.5
	_timer_label.offset_left = 260.0
	_timer_label.offset_top = 8.0
	_timer_label.offset_right = 380.0
	_timer_label.offset_bottom = 44.0
	_timer_label.text = "6:00"
	_canvas_layer.add_child(_timer_label)

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

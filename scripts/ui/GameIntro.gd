extends Control

const RACES := ["Elf", "Orc", "Fairy", "Infernal"]

const D20_SPRITESHEET_PATH := "res://pictures/d20_roll_sprite.png"
const D20_FRAME_SIZE := Vector2i(450, 450)
const D20_COLS := 5
const D20_ROWS := 11
const D20_FPS := 24.0
const UI_FONT := preload("res://fonts/m5x7.ttf")

enum Phase { SHOWCASE, ROLLING, SHOW_PLAYER_ROLL, SHOW_ORDER, GAME_READY }
var current_phase: Phase = Phase.SHOWCASE

# Node references
var map_bg: TextureRect
var map_overlay: ColorRect
var showcase_container: CenterContainer
var showcase_race_image: TextureRect
var showcase_name_label: Label
var d20_container: CenterContainer
var d20_sprite: Panel
var d20_anim: TextureRect
var roll_result_label: Label
var player_roll_container: CenterContainer
var order_center_container: CenterContainer
var order_list_center: VBoxContainer
var order_corner_container: VBoxContainer
var minigame_button: Button
var bridge_minigame_button: Button
var battle_button: Button
var skip_to_battle_button: Button
var rolling_label: Label
var settings_button: Button
var settings_panel: Panel
var phase_overlay: ColorRect
var phase_label: Label
var minigames_counter_label: Label

var is_paused: bool = false

# Animation timers
var showcase_timer: float = 0.0
var roll_animation_timer: float = 0.0
var roll_duration: float = 2.5
var current_rolling_player_idx: int = 0
var roll_display_value: int = 1
var roll_tick_timer: float = 0.0

# D20 spritesheet animation state
var _d20_frames: Array[Texture2D] = []
var _d20_frame_idx: int = 0
var _d20_frame_timer: float = 0.0

# Order display
var order_items_center: Array = []  # Array of Control nodes in center display
var order_items_corner: Array = []  # Array of Control nodes in corner display

func _ready() -> void:
	# Get node references
	map_bg = $MapBackground
	map_overlay = $MapOverlay
	showcase_container = $ShowcaseContainer
	showcase_race_image = $ShowcaseContainer/VBoxContainer/RaceImageContainer/RaceImage
	showcase_name_label = $ShowcaseContainer/VBoxContainer/NameLabel
	d20_container = $D20Container
	d20_sprite = $D20Container/VBoxContainer/D20Sprite
	d20_anim = $D20Container/VBoxContainer/D20Sprite/D20Anim
	roll_result_label = $D20Container/VBoxContainer/RollResultLabel
	rolling_label = $D20Container/VBoxContainer/RollingLabel
	order_center_container = $OrderCenterContainer
	order_list_center = $OrderCenterContainer/Panel/MarginContainer/VBoxContainer/OrderList
	order_corner_container = $OrderCornerContainer/VBoxContainer
	minigame_button = $MinigameButton
	bridge_minigame_button = $BridgeMinigameButton
	battle_button = $BattleButton
	skip_to_battle_button = $SkipToBattleButton
	settings_button = $SettingsButton
	settings_panel = $SettingsPanel
	player_roll_container = $PlayerRollContainer
	phase_overlay = $PhaseOverlay
	phase_label = $PhaseOverlay/PhaseLabel
	minigames_counter_label = $MinigamesCounterLabel
	
	# Initial state
	map_overlay.modulate.a = 0.6  # Gray out map
	showcase_container.visible = true
	showcase_container.modulate.a = 1.0
	d20_container.visible = false
	order_center_container.visible = false
	order_corner_container.get_parent().visible = false
	minigame_button.visible = false
	bridge_minigame_button.visible = false
	battle_button.visible = false
	skip_to_battle_button.visible = false
	settings_button.visible = false
	settings_panel.visible = false
	player_roll_container.visible = false
	phase_overlay.visible = false
	minigames_counter_label.visible = false
	
	_load_d20_spritesheet_frames()
	
	# Setup showcase with local player
	_setup_showcase()
	
	# Connect minigame buttons
	minigame_button.pressed.connect(_on_minigame_pressed)
	bridge_minigame_button.pressed.connect(_on_bridge_minigame_pressed)
	battle_button.pressed.connect(_on_battle_button_pressed)
	skip_to_battle_button.pressed.connect(_on_skip_to_battle_pressed)
	
	# Connect settings
	if settings_button:
		settings_button.pressed.connect(_on_settings_pressed)
	_setup_settings_panel()
	
	# Check if we're returning from minigame (skip intro if turn_order already set)
	if App.turn_order.size() > 0:
		_skip_to_game_ready()
		return
	
	# Start the intro sequence
	current_phase = Phase.SHOWCASE
	showcase_timer = 0.0

func _setup_showcase() -> void:
	# Find local player
	var local_player: Dictionary = {}
	for p in App.game_players:
		if p.get("is_local", false):
			local_player = p
			break
	
	if local_player.is_empty():
		return
	
	# Set race image
	var texture_path := App.get_race_texture_path(local_player.get("race", "Elf"))
	var texture = load(texture_path)
	if texture:
		showcase_race_image.texture = texture
	
	# Set name
	showcase_name_label.text = local_player.get("name", "Player")

func _process(delta: float) -> void:
	match current_phase:
		Phase.SHOWCASE:
			_process_showcase(delta)
		Phase.ROLLING:
			_process_rolling(delta)
		Phase.SHOW_PLAYER_ROLL:
			pass  # Handled by tween callbacks
		Phase.SHOW_ORDER:
			pass  # Handled by tween callbacks
		Phase.GAME_READY:
			pass  # Just waiting for player interaction

func _process_showcase(delta: float) -> void:
	showcase_timer += delta
	
	# Show showcase for 2.5 seconds, then fade out
	if showcase_timer >= 2.5 and showcase_container.modulate.a >= 1.0:
		var tween := create_tween()
		tween.tween_property(showcase_container, "modulate:a", 0.0, 0.8)
		tween.tween_callback(_start_rolling_phase)

func _start_rolling_phase() -> void:
	showcase_container.visible = false
	d20_container.visible = true
	d20_container.modulate.a = 0.0
	
	# Fade in d20
	var tween := create_tween()
	tween.tween_property(d20_container, "modulate:a", 1.0, 0.5)
	tween.tween_callback(_begin_rolling_sequence)

func _begin_rolling_sequence() -> void:
	current_phase = Phase.ROLLING
	current_rolling_player_idx = 0
	_start_d20_anim()
	
	# In multiplayer, host generates all rolls and syncs to clients
	if App.is_multiplayer:
		rolling_label.text = "Rolling for turn order..."
		rolling_label.visible = true
		roll_result_label.visible = false
		
		# Connect to roll sync signal
		if not Net.player_rolls_updated.is_connected(_on_rolls_synced):
			Net.player_rolls_updated.connect(_on_rolls_synced)
		
		# Request roll generation (host will generate and sync)
		Net.request_roll_generation()
	else:
		# Single player: use animated rolling sequence
		_roll_for_player(current_rolling_player_idx)

func _on_rolls_synced() -> void:
	# Disconnect the signal to avoid duplicate calls
	if Net.player_rolls_updated.is_connected(_on_rolls_synced):
		Net.player_rolls_updated.disconnect(_on_rolls_synced)
	
	print("Rolls synced, displaying results...")
	
	# Show a quick animation of the final rolls
	_display_multiplayer_rolls()

func _display_multiplayer_rolls() -> void:
	# Display each player's roll with a brief delay between them
	for i in range(App.game_players.size()):
		var player = App.game_players[i]
		var player_name: String = player.get("name", "Player")
		var roll_value: int = player.get("roll", 0)
		
		# Animate the roll display briefly
		roll_animation_timer = 0.0
		roll_tick_timer = 0.0
		var anim_duration := 0.8  # Shorter animation for multiplayer
		_start_d20_anim()
		
		rolling_label.text = player_name + " rolling..."
		rolling_label.visible = true
		
		# Quick roll animation
		while roll_animation_timer < anim_duration:
			await get_tree().process_frame
			var delta := get_process_delta_time()
			roll_animation_timer += delta
			roll_tick_timer += delta
			_advance_d20_anim(delta)
			
			if roll_tick_timer >= 0.06:
				roll_tick_timer = 0.0
				roll_result_label.text = str(randi_range(1, 20))
				roll_result_label.visible = true
		
		# Show final synced roll
		roll_result_label.text = str(roll_value)
		rolling_label.text = player_name + " rolled " + str(roll_value) + "!"
		
		# Wait before next player
		await get_tree().create_timer(0.8).timeout
	
	# All rolls displayed, finalize turn order
	_finalize_turn_order()

func _roll_for_player(idx: int) -> void:
	if idx >= App.game_players.size():
		# All players have rolled, determine order
		_finalize_turn_order()
		return
	
	var player = App.game_players[idx]
	rolling_label.text = player.get("name", "Player") + " rolling..."
	rolling_label.visible = true
	roll_result_label.visible = false
	_start_d20_anim()
	
	roll_animation_timer = 0.0
	roll_tick_timer = 0.0
	roll_display_value = randi_range(1, 20)

func _process_rolling(delta: float) -> void:
	roll_animation_timer += delta
	roll_tick_timer += delta
	_advance_d20_anim(delta)
	
	# Animate the displayed number
	if roll_tick_timer >= 0.08:
		roll_tick_timer = 0.0
		roll_display_value = randi_range(1, 20)
		roll_result_label.text = str(roll_display_value)
		roll_result_label.visible = true
	
	# After roll duration, show final result
	if roll_animation_timer >= roll_duration:
		_finish_current_roll()

func _finish_current_roll() -> void:
	if current_rolling_player_idx >= App.game_players.size():
		push_warning("Invalid rolling player index: ", current_rolling_player_idx)
		_finalize_turn_order()
		return
	
	# Generate actual roll (always 1-20, never 0)
	var final_roll := randi_range(1, 20)
	
	# Update the player's roll directly by index
	App.game_players[current_rolling_player_idx]["roll"] = final_roll
	
	var player_name: String = App.game_players[current_rolling_player_idx].get("name", "Player")
	print("Roll complete: ", player_name, " rolled ", final_roll)
	
	roll_result_label.text = str(final_roll)
	rolling_label.text = player_name + " rolled " + str(final_roll) + "!"
	
	# Wait a moment then move to next player
	await get_tree().create_timer(1.2).timeout
	
	current_rolling_player_idx += 1
	if current_rolling_player_idx < App.game_players.size():
		_roll_for_player(current_rolling_player_idx)
	else:
		_finalize_turn_order()

func _finalize_turn_order() -> void:
	# In single player, handle ties locally. In multiplayer, host already resolved ties.
	if not App.is_multiplayer:
		_resolve_ties()
	
	# Sort players by roll (highest first)
	var sorted_players := App.game_players.duplicate()
	sorted_players.sort_custom(func(a, b): return a.get("roll", 0) > b.get("roll", 0))
	App.turn_order = sorted_players
	
	print("Turn order finalized:")
	for i in range(App.turn_order.size()):
		var p = App.turn_order[i]
		print("  ", i + 1, ". ", p.get("name", "Unknown"), " - Roll: ", p.get("roll", 0))
	
	# First show the player's roll by itself
	current_phase = Phase.SHOW_PLAYER_ROLL
	_display_player_roll()

func _display_player_roll() -> void:
	# Hide d20 rolling UI
	d20_container.visible = false
	
	# Find local player's roll
	var local_player: Dictionary = {}
	for p in App.game_players:
		if p.get("is_local", false):
			local_player = p
			break
	
	if local_player.is_empty():
		# No local player found, skip to turn order
		_display_center_order()
		return
	
	# Show player roll container
	player_roll_container.visible = true
	player_roll_container.modulate.a = 0.0
	
	# Update the labels
	var roll_value_label = player_roll_container.get_node_or_null("Panel/VBoxContainer/RollValueLabel")
	var roll_text_label = player_roll_container.get_node_or_null("Panel/VBoxContainer/RollTextLabel")
	
	if roll_value_label:
		roll_value_label.text = str(local_player.get("roll", 0))
	if roll_text_label:
		roll_text_label.text = "Your Roll"
	
	# Fade in and show for a moment
	var tween := create_tween()
	tween.tween_property(player_roll_container, "modulate:a", 1.0, 0.5)
	tween.tween_interval(2.0)  # Show for 2 seconds
	tween.tween_property(player_roll_container, "modulate:a", 0.0, 0.3)
	tween.tween_callback(_show_turn_order_after_player_roll)

func _show_turn_order_after_player_roll() -> void:
	player_roll_container.visible = false
	current_phase = Phase.SHOW_ORDER
	_display_center_order()

func _resolve_ties() -> void:
	var max_attempts := 10  # Prevent infinite loops
	var attempts := 0
	
	# First, ensure all players have valid rolls (no zeros)
	for i in range(App.game_players.size()):
		var current_roll = App.game_players[i].get("roll", 0)
		if current_roll <= 0:
			App.game_players[i]["roll"] = randi_range(1, 20)
			print("Fixed invalid roll for player: ", App.game_players[i].get("name", "Unknown"))
	
	while attempts < max_attempts:
		var has_ties := false
		var rolls_count := {}
		
		# Count rolls by value, storing player indices
		for i in range(App.game_players.size()):
			var roll = App.game_players[i].get("roll", 0)
			if not rolls_count.has(roll):
				rolls_count[roll] = []
			rolls_count[roll].append(i)  # Store index instead of reference
		
		# Check for ties and re-roll
		for roll in rolls_count.keys():
			if rolls_count[roll].size() > 1:
				has_ties = true
				print("Tie detected at roll ", roll, " - rerolling for tied players")
				# Re-roll for tied players
				for idx in rolls_count[roll]:
					var new_roll := randi_range(1, 20)
					App.game_players[idx]["roll"] = new_roll
					print("  ", App.game_players[idx].get("name", "Unknown"), " rerolled: ", new_roll)
		
		if not has_ties:
			break
		attempts += 1
	
	if attempts >= max_attempts:
		push_warning("Reached max tie resolution attempts - some ties may remain")

func _display_center_order() -> void:
	rolling_label.visible = false
	roll_result_label.visible = false
	d20_container.visible = false
	
	order_center_container.visible = true
	order_center_container.modulate.a = 0.0
	
	# Clear existing items
	for child in order_list_center.get_children():
		child.queue_free()
	order_items_center.clear()
	
	# Create order items
	for i in range(App.turn_order.size()):
		var player = App.turn_order[i]
		var item := _create_order_item(player, i + 1, true)
		order_list_center.add_child(item)
		order_items_center.append(item)
	
	# Fade in
	var tween := create_tween()
	tween.tween_property(order_center_container, "modulate:a", 1.0, 0.5)
	tween.tween_interval(3.0)  # Show for 3 seconds
	tween.tween_callback(_minimize_to_corner)

func _create_order_item(player: Dictionary, order_position: int, is_center: bool) -> HBoxContainer:
	var container := HBoxContainer.new()
	container.add_theme_constant_override("separation", 10)
	
	# Position number
	var pos_label := Label.new()
	pos_label.text = str(order_position) + "."
	pos_label.add_theme_font_override("font", UI_FONT)
	pos_label.add_theme_font_size_override("font_size", 24 if is_center else 16)
	pos_label.add_theme_color_override("font_color", Color.WHITE)
	pos_label.custom_minimum_size.x = 30 if is_center else 20
	container.add_child(pos_label)
	
	# Race icon
	var race_icon := TextureRect.new()
	var texture_path := App.get_race_texture_path(player.get("race", "Elf"))
	var texture = load(texture_path)
	if texture:
		race_icon.texture = texture
	race_icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	race_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	race_icon.custom_minimum_size = Vector2(40, 40) if is_center else Vector2(24, 24)
	container.add_child(race_icon)
	
	# Player name
	var name_label := Label.new()
	name_label.text = player.get("name", "Player")
	name_label.add_theme_font_override("font", UI_FONT)
	name_label.add_theme_font_size_override("font_size", 22 if is_center else 14)
	name_label.add_theme_color_override("font_color", App.get_race_color(player.get("race", "Elf")))
	container.add_child(name_label)
	
	# Roll value (only for center display)
	if is_center:
		var roll_label := Label.new()
		roll_label.text = "(" + str(player.get("roll", 0)) + ")"
		roll_label.add_theme_font_override("font", UI_FONT)
		roll_label.add_theme_font_size_override("font_size", 18)
		roll_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		container.add_child(roll_label)
	
	# Highlight local player
	if player.get("is_local", false):
		var you_label := Label.new()
		you_label.text = " (You)" if is_center else "*"
		you_label.add_theme_font_override("font", UI_FONT)
		you_label.add_theme_font_size_override("font_size", 18 if is_center else 12)
		you_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))
		container.add_child(you_label)
	
	return container

func _minimize_to_corner() -> void:
	# Fade out center display
	var tween := create_tween()
	tween.tween_property(order_center_container, "modulate:a", 0.0, 0.3)
	tween.tween_callback(_show_corner_order)

func _show_corner_order() -> void:
	order_center_container.visible = false
	
	# Setup corner display
	var corner_parent = order_corner_container.get_parent()
	corner_parent.visible = true
	corner_parent.modulate.a = 0.0
	
	# Clear existing items
	for child in order_corner_container.get_children():
		if child.name != "TitleLabel":
			child.queue_free()
	order_items_corner.clear()
	
	# Create compact order items
	for i in range(App.turn_order.size()):
		var player = App.turn_order[i]
		var item := _create_order_item(player, i + 1, false)
		order_corner_container.add_child(item)
		order_items_corner.append(item)
	
	# Un-gray the map
	var map_tween := create_tween()
	map_tween.set_parallel(true)
	map_tween.tween_property(map_overlay, "modulate:a", 0.0, 0.8)
	map_tween.tween_property(corner_parent, "modulate:a", 1.0, 0.5)
	
	await map_tween.finished
	
	# Apply phase-aware UI visibility
	_apply_phase_ui()
	
	# Animate buttons fading in
	var btn_tween := create_tween()
	btn_tween.set_parallel(true)
	if minigame_button.visible:
		minigame_button.modulate.a = 0.0
		btn_tween.tween_property(minigame_button, "modulate:a", 1.0, 0.3)
	if bridge_minigame_button.visible:
		bridge_minigame_button.modulate.a = 0.0
		btn_tween.tween_property(bridge_minigame_button, "modulate:a", 1.0, 0.3)
	if battle_button.visible:
		battle_button.modulate.a = 0.0
		btn_tween.tween_property(battle_button, "modulate:a", 1.0, 0.3)
	if skip_to_battle_button.visible:
		skip_to_battle_button.modulate.a = 0.0
		btn_tween.tween_property(skip_to_battle_button, "modulate:a", 1.0, 0.3)
	settings_button.visible = true
	settings_button.modulate.a = 0.0
	btn_tween.tween_property(settings_button, "modulate:a", 1.0, 0.3)
	if minigames_counter_label.visible:
		minigames_counter_label.modulate.a = 0.0
		btn_tween.tween_property(minigames_counter_label, "modulate:a", 1.0, 0.3)
	
	current_phase = Phase.GAME_READY

func _on_minigame_pressed() -> void:
	App.go("res://scenes/Game.tscn")

func _on_bridge_minigame_pressed() -> void:
	App.go("res://scenes/BridgeGame.tscn")

func _on_battle_button_pressed() -> void:
	App.go("res://scenes/card_battle.tscn")

func _skip_to_game_ready() -> void:
	# Skip all intro animations and go directly to game ready state
	showcase_container.visible = false
	d20_container.visible = false
	order_center_container.visible = false
	map_overlay.modulate.a = 0.0
	
	# Show corner order
	var corner_parent = order_corner_container.get_parent()
	corner_parent.visible = true
	
	# Clear and rebuild corner order
	for child in order_corner_container.get_children():
		if child.name != "TitleLabel":
			child.queue_free()
	
	for i in range(App.turn_order.size()):
		var player = App.turn_order[i]
		var item := _create_order_item(player, i + 1, false)
		order_corner_container.add_child(item)
	
	# Check if we need to show phase transition overlay
	if App.show_phase_transition:
		App.show_phase_transition = false
		_show_phase_transition_overlay()
	else:
		# Just apply phase-aware UI immediately with animation
		_apply_phase_ui()
		_animate_phase_buttons()
	
	current_phase = Phase.GAME_READY

func _on_settings_pressed() -> void:
	toggle_pause()

func toggle_pause() -> void:
	is_paused = !is_paused
	settings_panel.visible = is_paused
	get_tree().paused = is_paused
	
	if settings_button:
		settings_button.visible = !is_paused

func _setup_settings_panel() -> void:
	# Connect settings panel buttons
	var resume_button = get_node_or_null("SettingsPanel/SettingsContainer/ButtonContainer/ResumeButton")
	var main_menu_button = get_node_or_null("SettingsPanel/SettingsContainer/ButtonContainer/MainMenuButton")
	
	if resume_button:
		resume_button.pressed.connect(_on_resume_pressed)
	if main_menu_button:
		main_menu_button.pressed.connect(_on_main_menu_pressed)
	
	# Connect volume sliders
	_setup_volume_sliders()

func _on_resume_pressed() -> void:
	toggle_pause()

func _on_main_menu_pressed() -> void:
	get_tree().paused = false
	App.go("res://scenes/ui/MainMenu.tscn")

func _setup_volume_sliders() -> void:
	var master_slider = get_node_or_null("SettingsPanel/SettingsContainer/MasterVolume/Slider")
	var music_slider = get_node_or_null("SettingsPanel/SettingsContainer/MusicVolume/Slider")
	var sfx_slider = get_node_or_null("SettingsPanel/SettingsContainer/SFXVolume/Slider")
	var ui_slider = get_node_or_null("SettingsPanel/SettingsContainer/UIVolume/Slider")
	
	if master_slider:
		master_slider.value = _db_to_linear(AudioServer.get_bus_volume_db(0))
		master_slider.value_changed.connect(_on_master_volume_changed)
	
	if music_slider:
		var music_bus_idx = AudioServer.get_bus_index("Music")
		if music_bus_idx >= 0:
			music_slider.value = _db_to_linear(AudioServer.get_bus_volume_db(music_bus_idx))
		music_slider.value_changed.connect(_on_music_volume_changed)
	
	if sfx_slider:
		var sfx_bus_idx = AudioServer.get_bus_index("SFX")
		if sfx_bus_idx >= 0:
			sfx_slider.value = _db_to_linear(AudioServer.get_bus_volume_db(sfx_bus_idx))
		sfx_slider.value_changed.connect(_on_sfx_volume_changed)
	
	if ui_slider:
		var ui_bus_idx = AudioServer.get_bus_index("UI")
		if ui_bus_idx >= 0:
			ui_slider.value = _db_to_linear(AudioServer.get_bus_volume_db(ui_bus_idx))
		ui_slider.value_changed.connect(_on_ui_volume_changed)

func _on_master_volume_changed(value: float) -> void:
	AudioServer.set_bus_volume_db(0, _linear_to_db(value))

func _on_music_volume_changed(value: float) -> void:
	var music_bus_idx = AudioServer.get_bus_index("Music")
	if music_bus_idx >= 0:
		AudioServer.set_bus_volume_db(music_bus_idx, _linear_to_db(value))

func _on_sfx_volume_changed(value: float) -> void:
	var sfx_bus_idx = AudioServer.get_bus_index("SFX")
	if sfx_bus_idx >= 0:
		AudioServer.set_bus_volume_db(sfx_bus_idx, _linear_to_db(value))

func _on_ui_volume_changed(value: float) -> void:
	var ui_bus_idx = AudioServer.get_bus_index("UI")
	if ui_bus_idx >= 0:
		AudioServer.set_bus_volume_db(ui_bus_idx, _linear_to_db(value))

func _linear_to_db(value: float) -> float:
	if value <= 0:
		return -80
	return 20 * log(value) / log(10)

func _db_to_linear(db: float) -> float:
	if db <= -80:
		return 0
	return pow(10, db / 20)

## ========== PHASE SYSTEM UI ==========

func _apply_phase_ui() -> void:
	## Shows/hides buttons based on current game phase
	match App.current_game_phase:
		App.GamePhase.RESOURCE_PHASE:
			# Show minigame buttons, skip button, hide battle button
			minigame_button.visible = true
			bridge_minigame_button.visible = true
			skip_to_battle_button.visible = true
			battle_button.visible = false
			minigames_counter_label.visible = true
			_update_minigames_counter()
		App.GamePhase.BATTLE_PHASE:
			# Hide minigame buttons, show battle button
			minigame_button.visible = false
			bridge_minigame_button.visible = false
			skip_to_battle_button.visible = false
			battle_button.visible = true
			minigames_counter_label.visible = false
	
	# Settings is always visible when game is ready
	settings_button.visible = true

func _show_phase_transition_overlay() -> void:
	## Shows a brief overlay announcing the current phase
	if not phase_overlay or not phase_label:
		_apply_phase_ui()
		return
	
	phase_label.text = App.phase_transition_text
	phase_overlay.visible = true
	phase_overlay.modulate.a = 0.0
	
	# Fade in
	var tween := create_tween()
	tween.tween_property(phase_overlay, "modulate:a", 1.0, 0.4)
	tween.tween_interval(1.5)  # Hold for 1.5 seconds
	tween.tween_property(phase_overlay, "modulate:a", 0.0, 0.4)
	tween.tween_callback(_on_phase_transition_finished)

func _on_phase_transition_finished() -> void:
	phase_overlay.visible = false
	_apply_phase_ui()
	_animate_phase_buttons()

func _animate_phase_buttons() -> void:
	## Fade in visible buttons with animation
	var btn_tween := create_tween()
	btn_tween.set_parallel(true)
	
	if minigame_button.visible:
		minigame_button.modulate.a = 0.0
		btn_tween.tween_property(minigame_button, "modulate:a", 1.0, 0.3)
	if bridge_minigame_button.visible:
		bridge_minigame_button.modulate.a = 0.0
		btn_tween.tween_property(bridge_minigame_button, "modulate:a", 1.0, 0.3)
	if battle_button.visible:
		battle_button.modulate.a = 0.0
		btn_tween.tween_property(battle_button, "modulate:a", 1.0, 0.3)
	if skip_to_battle_button.visible:
		skip_to_battle_button.modulate.a = 0.0
		btn_tween.tween_property(skip_to_battle_button, "modulate:a", 1.0, 0.3)
	if minigames_counter_label.visible:
		minigames_counter_label.modulate.a = 0.0
		btn_tween.tween_property(minigames_counter_label, "modulate:a", 1.0, 0.3)
	
	# Settings always visible
	settings_button.modulate.a = 0.0
	btn_tween.tween_property(settings_button, "modulate:a", 1.0, 0.3)

func _update_minigames_counter() -> void:
	## Updates the minigames counter label
	if minigames_counter_label:
		var remaining := App.MAX_MINIGAMES_PER_PHASE - App.minigames_completed_this_phase
		minigames_counter_label.text = "Minigames: %d/%d" % [App.minigames_completed_this_phase, App.MAX_MINIGAMES_PER_PHASE]

func _on_skip_to_battle_pressed() -> void:
	## Handle skip to battle button press
	App.skip_to_battle_phase()
	App.go("res://scenes/ui/GameIntro.tscn")
## ========== END PHASE SYSTEM UI ==========

func _load_d20_spritesheet_frames() -> void:
	_d20_frames.clear()
	# NOTE: This project currently doesn't have an import file for the spritesheet,
	# so ResourceLoader.load() may fail. Load the PNG directly via Image instead.
	var img := Image.new()
	var err := img.load(D20_SPRITESHEET_PATH)
	if err != OK:
		push_warning("Could not load d20 spritesheet: ", D20_SPRITESHEET_PATH, " (err=", err, ")")
		return
	var atlas: Texture2D = ImageTexture.create_from_image(img)
	
	for y in range(D20_ROWS):
		for x in range(D20_COLS):
			var rect := Rect2i(x * D20_FRAME_SIZE.x, y * D20_FRAME_SIZE.y, D20_FRAME_SIZE.x, D20_FRAME_SIZE.y)
			# Some spritesheets have unused/blank cells at the end; skip those so the animation never flashes empty frames.
			if not _d20_frame_has_content(img, rect):
				continue
			var frame := AtlasTexture.new()
			frame.atlas = atlas
			frame.region = rect
			_d20_frames.append(frame)
	
	if d20_anim and not _d20_frames.is_empty():
		d20_anim.texture = _d20_frames[0]

func _d20_frame_has_content(img: Image, rect: Rect2i) -> bool:
	# Fast heuristic: sample pixels; if everything is near-black, treat as empty.
	# (Our spritesheet background is black; the die has brighter pixels.)
	var step := 16
	var x0 := rect.position.x
	var y0 := rect.position.y
	var x1 := rect.position.x + rect.size.x
	var y1 := rect.position.y + rect.size.y
	
	for y in range(y0, y1, step):
		for x in range(x0, x1, step):
			var c := img.get_pixel(x, y)
			if (c.r + c.g + c.b) > 0.06:
				return true
	return false

func _start_d20_anim() -> void:
	if d20_anim == null or _d20_frames.is_empty():
		return
	
	var label := d20_sprite.get_node_or_null("D20Label")
	if label is CanvasItem:
		label.visible = false
	
	# Start at the first frame to feel like a real roll animation.
	_d20_frame_idx = 0
	_d20_frame_timer = 0.0
	d20_anim.texture = _d20_frames[_d20_frame_idx]

func _advance_d20_anim(delta: float) -> void:
	if d20_anim == null or _d20_frames.is_empty():
		return
	
	_d20_frame_timer += delta
	var frame_time := 1.0 / D20_FPS
	while _d20_frame_timer >= frame_time:
		_d20_frame_timer -= frame_time
		_d20_frame_idx = (_d20_frame_idx + 1) % _d20_frames.size()
		d20_anim.texture = _d20_frames[_d20_frame_idx]

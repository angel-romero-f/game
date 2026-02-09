extends Control

const RACES := ["Elf", "Orc", "Fairy", "Infernal"]

const D20_SPRITESHEET_PATH := "res://pictures/d20_roll_sprite.png"
const D20_FRAME_SIZE := Vector2i(450, 450)
const D20_COLS := 5
const D20_ROWS := 11
const D20_FPS := 24.0
const UI_FONT := preload("res://fonts/m5x7.ttf")

enum Phase { SHOWCASE, ROLLING, SHOW_PLAYER_ROLL, SHOW_ORDER, GAME_READY }
enum MapSubPhase { CLAIMING, RESOURCE_COLLECTION, BATTLE_READY }
var current_phase: Phase = Phase.SHOWCASE
var map_sub_phase: MapSubPhase = MapSubPhase.CLAIMING

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
var ice_fishing_button: Button
var play_minigames_button: Button
var battle_button: Button
var skip_to_battle_button: Button
var rolling_label: Label
var settings_button: Button
var settings_panel: Panel
var phase_overlay: ColorRect
var phase_label: Label
var minigames_counter_label: Label

# Hand display nodes
var card_icon_button: Button
var hand_display_panel: PanelContainer
var hand_container: HBoxContainer
var is_hand_visible: bool = false

# Claim territory panel
var claim_territory_panel: PanelContainer
var claim_slots_container: HBoxContainer
var claim_hand_container: HBoxContainer
var claim_cancel_button: Button
var claim_button: Button
var claim_play_minigame_button: Button
var finish_claiming_button: Button
var ready_for_battle_button: Button
var current_claim_territory_id: int = -1
var claim_panel_play_only_mode: bool = false
var claim_slot_cards: Array = [null, null, null]  # 3 slots, each Dictionary or null
var claim_hand_cards: Array = []  # working copy of hand when panel is open
var claim_selected_hand_index: int = -1

# Message panel for info/error messages
var message_panel: PanelContainer
var message_label: Label
var message_close_button: Button

# Battle selection UI nodes (multiplayer)
var battle_button_right: Button
var left_battle_selectors: VBoxContainer
var right_battle_selectors: VBoxContainer
var waiting_overlay: ColorRect
var waiting_label: Label
var current_decider_label: Label
var skip_battle_decision_button: Button

# Multiplayer waiting state
var is_waiting_for_others: bool = false
var local_done_count: int = 0
var local_total_count: int = 0

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

# Territory system
var territory_manager: TerritoryManager = null
var territories_container: Control = null
var _territory_claim_state: Node = null  # Autoload for territory claims (runtime lookup)
const TerritoryMapConfigScript := preload("res://scripts/TerritoryMapConfig.gd")
# Claim panel size: full (claiming) vs compact (play minigame only)
const CLAIM_PANEL_FULL_OFFSET := Vector4(-220.0, -180.0, 220.0, 180.0)   # left, top, right, bottom
const CLAIM_PANEL_PLAY_ONLY_OFFSET := Vector4(-160.0, -55.0, 160.0, 55.0)

## Region ID (1-6) -> minigame. Each TerritoryNode's region_id_override picks which minigame runs when you click "Play [name]". Add more territories in the scene and set their Region Id Override to 1/2/3 (or 4-6 once you add scenes here).
const REGION_MINIGAMES: Dictionary = {
	1: { "name": "Bridge", "scene": "res://scenes/BridgeGame.tscn" },
	6: { "name": "Ice fishing", "scene": "res://scenes/IceFishingGame.tscn" },
	5: { "name": "River crossing", "scene": "res://scenes/Game.tscn" },  # Replace with your river crossing scene when ready
	4: { "name": "", "scene": "" },
	3: { "name": "", "scene": "" },
	2: { "name": "", "scene": "" }
}

func _ready() -> void:
	# Build path without literal autoload name to avoid parse errors in some Godot setups
	_territory_claim_state = get_node_or_null("/root/" + "Territory" + "Claim" + "State")
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
	ice_fishing_button = $IceFishingButton
	play_minigames_button = $PlayMinigamesButton
	battle_button = $BattleButton
	skip_to_battle_button = $SkipToBattleButton
	settings_button = $SettingsButton
	settings_panel = $SettingsPanel
	player_roll_container = $PlayerRollContainer
	phase_overlay = $PhaseOverlay
	phase_label = $PhaseOverlay/PhaseLabel
	minigames_counter_label = $MinigamesCounterLabel

	# Hand display nodes
	card_icon_button = $CardIconButton
	hand_display_panel = $HandDisplayPanel
	hand_container = $HandDisplayPanel/MarginContainer/VBoxContainer/HandContainer

	# Claim territory panel
	claim_territory_panel = $ClaimTerritoryPanel
	claim_slots_container = $ClaimTerritoryPanel/MarginContainer/VBoxContainer/SlotsContainer
	claim_hand_container = $ClaimTerritoryPanel/MarginContainer/VBoxContainer/ClaimHandContainer
	claim_cancel_button = $ClaimTerritoryPanel/MarginContainer/VBoxContainer/ButtonsContainer/CancelButton
	claim_button = $ClaimTerritoryPanel/MarginContainer/VBoxContainer/ButtonsContainer/ClaimButton
	if claim_cancel_button:
		claim_cancel_button.pressed.connect(_on_claim_cancel_clicked)
	if claim_button:
		claim_button.pressed.connect(_on_claim_territory_clicked)
	claim_play_minigame_button = get_node_or_null("ClaimTerritoryPanel/MarginContainer/VBoxContainer/ButtonsContainer/PlayMinigameButton") as Button
	if claim_play_minigame_button:
		claim_play_minigame_button.pressed.connect(_on_claim_play_minigame_pressed)
	finish_claiming_button = get_node_or_null("FinishClaimingButton") as Button
	if finish_claiming_button:
		finish_claiming_button.pressed.connect(_on_finish_claiming_pressed)
	ready_for_battle_button = get_node_or_null("ReadyForBattleButton") as Button
	if ready_for_battle_button:
		ready_for_battle_button.pressed.connect(_on_ready_for_battle_pressed)

	# Message panel for info/error messages
	message_panel = get_node_or_null("MessagePanel") as PanelContainer
	if not message_panel:
		# Create message panel programmatically if it doesn't exist in scene
		message_panel = PanelContainer.new()
		message_panel.name = "MessagePanel"
		message_panel.set_anchors_preset(Control.PRESET_CENTER)
		message_panel.offset_left = -200
		message_panel.offset_top = -80
		message_panel.offset_right = 200
		message_panel.offset_bottom = 80
		add_child(message_panel)
		
		var margin := MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 20)
		margin.add_theme_constant_override("margin_top", 20)
		margin.add_theme_constant_override("margin_right", 20)
		margin.add_theme_constant_override("margin_bottom", 20)
		message_panel.add_child(margin)
		
		var vbox := VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 15)
		margin.add_child(vbox)
		
		message_label = Label.new()
		message_label.add_theme_font_override("font", UI_FONT)
		message_label.add_theme_font_size_override("font_size", 20)
		message_label.add_theme_color_override("font_color", Color.WHITE)
		message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(message_label)
		
		var button_container := HBoxContainer.new()
		button_container.alignment = BoxContainer.ALIGNMENT_CENTER
		vbox.add_child(button_container)
		
		message_close_button = Button.new()
		message_close_button.text = "Close"
		message_close_button.pressed.connect(_on_message_close_pressed)
		button_container.add_child(message_close_button)
	else:
		# Get references if panel exists in scene
		message_label = message_panel.get_node_or_null("MarginContainer/VBoxContainer/MessageLabel") as Label
		message_close_button = message_panel.get_node_or_null("MarginContainer/VBoxContainer/ButtonContainer/CloseButton") as Button
		if message_close_button:
			message_close_button.pressed.connect(_on_message_close_pressed)
		if not message_label:
			message_label = Label.new()
			message_label.name = "MessageLabel"
			message_label.add_theme_font_override("font", UI_FONT)
			message_label.add_theme_font_size_override("font_size", 20)
			message_label.add_theme_color_override("font_color", Color.WHITE)
			message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			if message_panel.get_child_count() > 0:
				var vbox = message_panel.get_child(0).get_node_or_null("VBoxContainer")
				if vbox:
					vbox.add_child(message_label)
	
	if message_panel:
		message_panel.visible = false

	# Battle selection UI nodes (multiplayer)
	battle_button_right = $BattleButtonRight
	left_battle_selectors = $LeftBattleSelectors
	right_battle_selectors = $RightBattleSelectors
	waiting_overlay = $WaitingOverlay
	waiting_label = $WaitingOverlay/WaitingLabel
	current_decider_label = $CurrentDeciderLabel
	skip_battle_decision_button = $SkipBattleDecisionButton

	# Initial state
	map_overlay.modulate.a = 0.6  # Gray out map
	showcase_container.visible = true
	showcase_container.modulate.a = 1.0
	d20_container.visible = false
	order_center_container.visible = false
	order_corner_container.get_parent().visible = false
	minigame_button.visible = false
	bridge_minigame_button.visible = false
	ice_fishing_button.visible = false
	play_minigames_button.visible = false
	battle_button.visible = false
	skip_to_battle_button.visible = false
	settings_button.visible = false
	settings_panel.visible = false
	player_roll_container.visible = false
	phase_overlay.visible = false
	minigames_counter_label.visible = false
	card_icon_button.visible = false
	hand_display_panel.visible = false

	# Battle selection UI initial state
	battle_button_right.visible = false
	left_battle_selectors.visible = false
	right_battle_selectors.visible = false
	waiting_overlay.visible = false
	current_decider_label.visible = false
	skip_battle_decision_button.visible = false

	# Setup card icon button texture (use cardback)
	_setup_card_icon_button()

	# Connect card icon button
	if card_icon_button:
		card_icon_button.pressed.connect(_on_card_icon_pressed)

	_load_d20_spritesheet_frames()

	# Setup showcase with local player
	_setup_showcase()

	# Connect minigame buttons
	minigame_button.pressed.connect(_on_minigame_pressed)
	bridge_minigame_button.pressed.connect(_on_bridge_minigame_pressed)
	ice_fishing_button.pressed.connect(_on_ice_fishing_pressed)
	play_minigames_button.pressed.connect(_on_play_minigames_pressed)
	battle_button.pressed.connect(_on_left_battle_pressed)
	skip_to_battle_button.pressed.connect(_on_skip_to_battle_pressed)

	# Connect battle selection buttons (multiplayer)
	battle_button_right.pressed.connect(_on_right_battle_pressed)
	skip_battle_decision_button.pressed.connect(_on_skip_battle_decision_pressed)

	# Connect settings
	if settings_button:
		settings_button.pressed.connect(_on_settings_pressed)
	_setup_settings_panel()

	# Connect Net signals for multiplayer phase/battle sync
	if App.is_multiplayer:
		_connect_net_signals()
		
	# After connecting Net signals:
	if App.is_multiplayer and multiplayer.has_multiplayer_peer():
		# Force local App phase to match host-synced Net phase
		_on_net_phase_changed(Net.current_phase)

	# Initialize territory system
	_initialize_territory_system()

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
	var texture_path: String = App.get_race_texture_path(String(local_player.get("race", "Elf")))
	var texture = load(texture_path)
	if texture:
		showcase_race_image.texture = texture

	# Set name
	showcase_name_label.text = local_player.get("name", "Player")

func _initialize_territory_system() -> void:
	## Initialize territory system for map ↔ territory linkage
	## Creates TerritoryManager and container if they don't exist
	## Territories can be initialized from editor-placed nodes or config data
	
	# Get or create TerritoryManager
	territory_manager = get_node_or_null("TerritoryManager") as TerritoryManager
	if not territory_manager:
		territory_manager = TerritoryManager.new()
		territory_manager.name = "TerritoryManager"
		add_child(territory_manager)
	
	# Get or create container for TerritoryNodes
	# TerritoryNodes are Control nodes, so they can be direct children of GameIntro
	territories_container = get_node_or_null("TerritoriesContainer") as Control
	if not territories_container:
		territories_container = Control.new()
		territories_container.name = "TerritoriesContainer"
		territories_container.set_anchors_preset(Control.PRESET_FULL_RECT)
		territories_container.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Let territories handle input
		
		# Add as child of GameIntro (before MapOverlay so territories are above map but below UI)
		var map_overlay_index := get_child_count()
		for i in range(get_child_count()):
			if get_child(i) == map_overlay:
				map_overlay_index = i
				break
		add_child(territories_container)
		move_child(territories_container, map_overlay_index)
	
	# Connect territory signals (for external systems to listen)
	if not territory_manager.territory_selected.is_connected(_on_territory_selected):
		territory_manager.territory_selected.connect(_on_territory_selected)
	if not territory_manager.card_placed.is_connected(_on_card_placed):
		territory_manager.card_placed.connect(_on_card_placed)
	
	# Initialize territories from editor-placed nodes (if any exist)
	# Or use config data if provided
	# This can be customized based on how territories are defined
	_initialize_territories()

func _initialize_territories() -> void:
	## Initialize territories on map load
	## Creates all 31 territories based on the gray outlines on the map
	
	# Option 1: Initialize from editor-placed TerritoryNode children (if any exist)
	if territories_container and territories_container.get_child_count() > 0:
		var has_territory_nodes := false
		for child in territories_container.get_children():
			if child is TerritoryNode:
				has_territory_nodes = true
				break
		
		if has_territory_nodes:
			territory_manager.initialize_from_editor_nodes(territories_container)
			_apply_saved_territory_claims()
			_refresh_territory_claimed_visuals()
			return
	
	# Option 2: Initialize from TerritoryMapConfig resource (if exists)
	var map_config_path := "res://scripts/TerritoryMapConfig.tres"
	if ResourceLoader.exists(map_config_path):
		var config = load(map_config_path)
		if config and config.has_method("get_territory_configs"):
			territory_manager.initialize_territories(config.get_territory_configs(), territories_container)
			_apply_saved_territory_claims()
			_refresh_territory_claimed_visuals()
			return
	
	# Option 3: Initialize from default configuration (creates 31 territories)
	# Call static method directly on the script class
	if TerritoryMapConfigScript:
		var default_config = TerritoryMapConfigScript.create_default_config()
		if default_config and default_config.has_method("get_territory_configs"):
			territory_manager.initialize_territories(default_config.get_territory_configs(), territories_container)
			_apply_saved_territory_claims()
			_refresh_territory_claimed_visuals()
			print("[GameIntro] Initialized territories from default configuration")
			return
	
	# Fallback: Create basic territories if config system fails
	push_warning("[GameIntro] Could not load TerritoryMapConfig, creating basic territories")
	var basic_configs: Array[Dictionary] = []
	for i in range(31):
		var default_size := Vector2(150, 120)
		var default_polygon := PackedVector2Array([
			Vector2(0, 0),
			Vector2(default_size.x, 0),
			Vector2(default_size.x, default_size.y),
			Vector2(0, default_size.y)
		])
		
		basic_configs.append({
			"territory_id": i + 1,
			"region_id": 1,
			"position": Vector2(400.0 + float(i % 6) * 150.0, 300.0 + float(i) / 6.0 * 120.0),
			"size": default_size,
			"polygon_points": default_polygon,
			"adjacent_territory_ids": []
		})
	territory_manager.initialize_territories(basic_configs, territories_container)
	_apply_saved_territory_claims()
	_refresh_territory_claimed_visuals()
	print("[GameIntro] Initialized %d basic territories" % basic_configs.size())

func _are_territories_interactable() -> bool:
	## False during dice roll, phase overlay, or any non-map phase so players don't click territories by accident.
	if current_phase != Phase.GAME_READY:
		return false
	if phase_overlay and phase_overlay.visible:
		return false
	if player_roll_container and player_roll_container.visible:
		return false
	return true

func _on_territory_selected(territory_id: int) -> void:
	if not _are_territories_interactable() or not claim_territory_panel:
		return
	# RESOURCE_COLLECTION: only claimed territories can play minigame; open play-only panel or show message.
	if map_sub_phase == MapSubPhase.RESOURCE_COLLECTION:
		var is_claimed: bool = _territory_claim_state != null and _territory_claim_state.call("is_claimed", territory_id)
		var owner_id: Variant = _territory_claim_state.call("get_owner_id", territory_id) if _territory_claim_state else null
		var local_id: Variant = _get_local_player_id()
		if not is_claimed or owner_id != local_id:
			_show_unclaimed_territory_message()
			return
		_open_play_only_panel(territory_id)
	else:
		_open_claim_panel(territory_id)

func _open_play_only_panel(territory_id: int) -> void:
	## Panel with just "Play [minigame]" and Close (no slots, no claiming) - compact size
	current_claim_territory_id = territory_id
	claim_panel_play_only_mode = true
	# Shrink panel to fit just title + two buttons
	claim_territory_panel.offset_left = CLAIM_PANEL_PLAY_ONLY_OFFSET.x
	claim_territory_panel.offset_top = CLAIM_PANEL_PLAY_ONLY_OFFSET.y
	claim_territory_panel.offset_right = CLAIM_PANEL_PLAY_ONLY_OFFSET.z
	claim_territory_panel.offset_bottom = CLAIM_PANEL_PLAY_ONLY_OFFSET.w
	var title_label: Label = claim_territory_panel.get_node_or_null("MarginContainer/VBoxContainer/TitleLabel") as Label
	if title_label:
		title_label.text = "Collect resources"
	# Hide claim UI, show only play minigame + cancel
	if claim_slots_container:
		claim_slots_container.visible = false
	var hand_label: Control = claim_territory_panel.get_node_or_null("MarginContainer/VBoxContainer/HandLabel")
	if hand_label:
		hand_label.visible = false
	if claim_hand_container:
		claim_hand_container.visible = false
	if claim_button:
		claim_button.visible = false
	if claim_cancel_button:
		claim_cancel_button.visible = true
		claim_cancel_button.text = "Close"
	var region_id: int = 1
	if territory_manager and territory_manager.territory_data.has(territory_id):
		region_id = territory_manager.territory_data[territory_id].region_id
	var region_info: Dictionary = REGION_MINIGAMES.get(region_id, { "name": "", "scene": "" })
	var scene_path: String = region_info.get("scene", "")
	var region_name: String = region_info.get("name", "")
	if claim_play_minigame_button:
		if scene_path != "" and region_name != "":
			claim_play_minigame_button.text = "Play %s" % region_name
			claim_play_minigame_button.visible = true
		else:
			claim_play_minigame_button.visible = false
	claim_territory_panel.visible = true

func _open_claim_panel(territory_id: int) -> void:
	claim_panel_play_only_mode = false
	# Restore full panel size
	claim_territory_panel.offset_left = CLAIM_PANEL_FULL_OFFSET.x
	claim_territory_panel.offset_top = CLAIM_PANEL_FULL_OFFSET.y
	claim_territory_panel.offset_right = CLAIM_PANEL_FULL_OFFSET.z
	claim_territory_panel.offset_bottom = CLAIM_PANEL_FULL_OFFSET.w
	current_claim_territory_id = territory_id
	claim_selected_hand_index = -1
	var title_label: Label = claim_territory_panel.get_node_or_null("MarginContainer/VBoxContainer/TitleLabel") as Label
	if title_label:
		title_label.text = "Claim Territory"
	# Restore claim UI visibility
	if claim_slots_container:
		claim_slots_container.visible = true
	var hand_label: Control = claim_territory_panel.get_node_or_null("MarginContainer/VBoxContainer/HandLabel")
	if hand_label:
		hand_label.visible = true
	if claim_hand_container:
		claim_hand_container.visible = true
	if claim_cancel_button:
		claim_cancel_button.visible = true
		claim_cancel_button.text = "Cancel"
	# If already claimed, show saved cards; else empty slots
	if _territory_claim_state and _territory_claim_state.call("is_claimed", territory_id):
		var saved: Array = _territory_claim_state.call("get_cards", territory_id) as Array
		claim_slot_cards = []
		for i in range(3):
			claim_slot_cards.append(saved[i] if i < saved.size() and saved[i] != null else null)
		claim_hand_cards = App.player_card_collection.duplicate()
		claim_button.visible = false
	else:
		claim_slot_cards = [null, null, null]
		claim_hand_cards = App.player_card_collection.duplicate()
		claim_button.visible = true
	_populate_claim_slots()
	_populate_claim_hand()
	_update_claim_button_state()
	# Play minigame button: only in BATTLE_READY (not during initial CLAIMING)
	var show_play_minigame: bool = (map_sub_phase == MapSubPhase.BATTLE_READY)
	var region_id: int = 1
	if territory_manager and territory_manager.territory_data.has(territory_id):
		region_id = territory_manager.territory_data[territory_id].region_id
	var region_info: Dictionary = REGION_MINIGAMES.get(region_id, { "name": "", "scene": "" })
	var scene_path: String = region_info.get("scene", "")
	var region_name: String = region_info.get("name", "")
	if claim_play_minigame_button:
		if show_play_minigame and scene_path != "" and region_name != "":
			claim_play_minigame_button.text = "Play %s" % region_name
			claim_play_minigame_button.visible = true
		else:
			claim_play_minigame_button.visible = false
	claim_territory_panel.visible = true

func _close_claim_panel() -> void:
	current_claim_territory_id = -1
	claim_territory_panel.visible = false
	claim_panel_play_only_mode = false
	# Restore full panel size for next open
	claim_territory_panel.offset_left = CLAIM_PANEL_FULL_OFFSET.x
	claim_territory_panel.offset_top = CLAIM_PANEL_FULL_OFFSET.y
	claim_territory_panel.offset_right = CLAIM_PANEL_FULL_OFFSET.z
	claim_territory_panel.offset_bottom = CLAIM_PANEL_FULL_OFFSET.w
	# Restore claim UI for next open
	if claim_slots_container:
		claim_slots_container.visible = true
	var hand_label: Control = claim_territory_panel.get_node_or_null("MarginContainer/VBoxContainer/HandLabel")
	if hand_label:
		hand_label.visible = true
	if claim_hand_container:
		claim_hand_container.visible = true
	if claim_cancel_button:
		claim_cancel_button.visible = true
		claim_cancel_button.text = "Cancel"

func _populate_claim_slots() -> void:
	for child in claim_slots_container.get_children():
		child.queue_free()
	var slot_size := Vector2(70, 100)
	for i in range(3):
		var panel := Panel.new()
		panel.custom_minimum_size = slot_size
		panel.set_meta("slot_index", i)
		var tex := TextureRect.new()
		tex.set_anchors_preset(Control.PRESET_FULL_RECT)
		tex.offset_left = 4
		tex.offset_top = 4
		tex.offset_right = -4
		tex.offset_bottom = -4
		tex.expand_mode = TextureRect.EXPAND_FIT_HEIGHT_PROPORTIONAL
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		if claim_slot_cards[i] != null and claim_slot_cards[i] is Dictionary:
			var path: String = claim_slot_cards[i].get("path", "")
			var frame: int = int(claim_slot_cards[i].get("frame", 0))
			if path != "" and ResourceLoader.exists(path):
				var sf: SpriteFrames = load(path) as SpriteFrames
				if sf and sf.has_animation("default"):
					tex.texture = sf.get_frame_texture("default", frame)
		panel.add_child(tex)
		panel.gui_input.connect(_on_claim_slot_gui_input.bind(i))
		claim_slots_container.add_child(panel)

func _on_claim_slot_gui_input(event: InputEvent, slot_index: int) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			if claim_selected_hand_index >= 0 and claim_selected_hand_index < claim_hand_cards.size():
				# Place selected card in slot
				var card: Dictionary = claim_hand_cards[claim_selected_hand_index]
				claim_slot_cards[slot_index] = card
				claim_hand_cards.remove_at(claim_selected_hand_index)
				claim_selected_hand_index = -1
				_populate_claim_slots()
				_populate_claim_hand()
				_update_claim_button_state()
			elif claim_slot_cards[slot_index] != null:
				# Return card from slot to hand
				claim_hand_cards.append(claim_slot_cards[slot_index])
				claim_slot_cards[slot_index] = null
				_populate_claim_slots()
				_populate_claim_hand()
				_update_claim_button_state()

func _update_claim_button_state() -> void:
	if not claim_button:
		return
	var has_any: bool = false
	for slot_idx in range(3):
		if claim_slot_cards[slot_idx] != null:
			has_any = true
			break
	claim_button.disabled = not has_any

func _populate_claim_hand() -> void:
	for child in claim_hand_container.get_children():
		child.queue_free()
	var card_size := Vector2(60, 90)
	for i in range(claim_hand_cards.size()):
		var card_data: Dictionary = claim_hand_cards[i]
		var btn := Button.new()
		btn.custom_minimum_size = card_size
		btn.flat = true
		btn.set_meta("hand_index", i)
		var tex := TextureRect.new()
		tex.set_anchors_preset(Control.PRESET_FULL_RECT)
		tex.offset_left = 4
		tex.offset_top = 4
		tex.offset_right = -4
		tex.offset_bottom = -4
		tex.expand_mode = TextureRect.EXPAND_FIT_HEIGHT_PROPORTIONAL
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var path: String = card_data.get("path", "")
		var frame: int = int(card_data.get("frame", 0))
		if path != "" and ResourceLoader.exists(path):
			var sf: SpriteFrames = load(path) as SpriteFrames
			if sf and sf.has_animation("default"):
				tex.texture = sf.get_frame_texture("default", frame)
		btn.add_child(tex)
		btn.pressed.connect(_on_claim_hand_card_clicked.bind(i))
		claim_hand_container.add_child(btn)

func _on_claim_hand_card_clicked(hand_index: int) -> void:
	claim_selected_hand_index = hand_index

func _on_finish_claiming_pressed() -> void:
	_close_claim_panel()
	_show_collect_resources_overlay()

func _show_collect_resources_overlay() -> void:
	if finish_claiming_button:
		finish_claiming_button.visible = false
	if not phase_overlay or not phase_label:
		_enter_resource_collection()
		return
	phase_label.text = "Collect your resources!"
	phase_overlay.visible = true
	phase_overlay.modulate.a = 0.0
	# Auto-dismiss like battle phase: fade in, hold, fade out, then enter resource collection
	var tween := create_tween()
	tween.tween_property(phase_overlay, "modulate:a", 1.0, 0.4)
	tween.tween_interval(1.5)
	tween.tween_property(phase_overlay, "modulate:a", 0.0, 0.4)
	tween.tween_callback(_on_collect_resources_overlay_finished)

func _on_collect_resources_overlay_finished() -> void:
	phase_overlay.visible = false
	_enter_resource_collection()

func _show_unclaimed_territory_message() -> void:
	## Show message panel: you can only play minigames on territories you've claimed.
	if not message_panel or not message_label:
		return
	message_label.text = "You can only play minigames on territories you've claimed."
	message_panel.visible = true
	message_panel.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(message_panel, "modulate:a", 1.0, 0.2)

func _on_message_close_pressed() -> void:
	## Close the message panel
	if not message_panel:
		return
	var tween := create_tween()
	tween.tween_property(message_panel, "modulate:a", 0.0, 0.15)
	tween.tween_callback(func(): message_panel.visible = false)

func _enter_resource_collection() -> void:
	map_sub_phase = MapSubPhase.RESOURCE_COLLECTION
	_apply_phase_ui()
	_animate_phase_buttons()

func _on_ready_for_battle_pressed() -> void:
	map_sub_phase = MapSubPhase.BATTLE_READY
	_apply_phase_ui()
	_animate_phase_buttons()

func _on_claim_play_minigame_pressed() -> void:
	if current_claim_territory_id < 0 or not territory_manager or not territory_manager.territory_data.has(current_claim_territory_id):
		return
	var territory: Territory = territory_manager.territory_data[current_claim_territory_id]
	var region_id: int = territory.region_id
	var region_info: Dictionary = REGION_MINIGAMES.get(region_id, { "scene": "" })
	var scene_path: String = region_info.get("scene", "")
	if scene_path != "" and ResourceLoader.exists(scene_path):
		_close_claim_panel()
		# So when we return, GameIntro restores RESOURCE_COLLECTION and increments minigame count
		App.pending_return_map_sub_phase = MapSubPhase.RESOURCE_COLLECTION
		App.returning_from_territory_minigame = true
		App.go(scene_path)

func _on_claim_territory_clicked() -> void:
	if current_claim_territory_id < 0 or not territory_manager.territory_data.has(current_claim_territory_id):
		_close_claim_panel()
		return
	# Require at least 1 card to claim (1-3 cards allowed)
	var has_any_card: bool = false
	for slot_idx in range(3):
		if claim_slot_cards[slot_idx] != null:
			has_any_card = true
			break
	if not has_any_card:
		return
	var territory: Territory = territory_manager.territory_data[current_claim_territory_id]
	var local_id: Variant = _get_local_player_id()
	if local_id == null:
		_close_claim_panel()
		return
	# Place cards in territory data (only the slots that have cards)
	for slot_idx in range(3):
		if claim_slot_cards[slot_idx] != null:
			territory.place_card(local_id, claim_slot_cards[slot_idx], slot_idx)
	territory.set_owner(local_id)
	# Persist
	if _territory_claim_state and _territory_claim_state.has_method("set_claim"):
		_territory_claim_state.set_claim(current_claim_territory_id, local_id, claim_slot_cards)
	# Remove only the placed cards from player collection (1-3 cards)
	var placed_slots: Dictionary = {}
	for slot_idx in range(3):
		if claim_slot_cards[slot_idx] != null:
			placed_slots[slot_idx] = claim_slot_cards[slot_idx]
	App.remove_placed_cards_from_collection_for_slots(placed_slots)
	_refresh_territory_claimed_visuals()
	_close_claim_panel()

func _on_claim_cancel_clicked() -> void:
	_close_claim_panel()

func _get_local_player_id() -> Variant:
	for p in App.game_players:
		if p.get("is_local", false):
			return p.get("id", 1)
	return 1

func _apply_saved_territory_claims() -> void:
	if not territory_manager:
		return
	if not _territory_claim_state:
		return
	var claims_dict: Variant = _territory_claim_state.get("claims")
	if not (claims_dict is Dictionary):
		return
	for tid_key in claims_dict:
		var tid: int = int(tid_key)
		var claim_data: Dictionary = (claims_dict as Dictionary)[tid_key]
		var owner_id: Variant = claim_data.get("owner_player_id", null)
		var cards: Array = claim_data.get("cards", [])
		if owner_id == null or not territory_manager.territory_data.has(tid):
			continue
		var territory: Territory = territory_manager.territory_data[tid]
		territory.set_owner(owner_id)
		for slot_idx in range(min(3, cards.size())):
			if cards[slot_idx] != null:
				territory.place_card(owner_id, cards[slot_idx], slot_idx)
	_refresh_territory_claimed_visuals()

func _refresh_territory_claimed_visuals() -> void:
	if not territory_manager:
		return
	for tid_key in territory_manager.territories:
		var node: TerritoryNode = territory_manager.territories[tid_key]
		node.update_claimed_visual()

func _on_card_placed(territory_id: int, player_id: int) -> void:
	## Called when a card is placed on a territory
	## No gameplay logic - just map ↔ territory linkage
	print("[GameIntro] Card placed on territory %d by player %d" % [territory_id, player_id])

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
		var current_roll: int = int(App.game_players[i].get("roll", 0))
		if current_roll <= 0:
			App.game_players[i]["roll"] = randi_range(1, 20)
			print("Fixed invalid roll for player: ", App.game_players[i].get("name", "Unknown"))

	while attempts < max_attempts:
		var has_ties := false
		var rolls_count := {}

		# Count rolls by value, storing player indices
		for i in range(App.game_players.size()):
			var roll: int = int(App.game_players[i].get("roll", 0))
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
	var texture_path: String = App.get_race_texture_path(String(player.get("race", "Elf")))
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
	if play_minigames_button.visible:
		play_minigames_button.modulate.a = 0.0
		btn_tween.tween_property(play_minigames_button, "modulate:a", 1.0, 0.3)
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
	if card_icon_button.visible:
		card_icon_button.modulate.a = 0.0
		btn_tween.tween_property(card_icon_button, "modulate:a", 1.0, 0.3)

	current_phase = Phase.GAME_READY
	if not App.is_multiplayer:
		map_sub_phase = MapSubPhase.CLAIMING

func _on_minigame_pressed() -> void:
	App.go("res://scenes/Game.tscn")

func _on_bridge_minigame_pressed() -> void:
	App.go("res://scenes/BridgeGame.tscn")

func _on_ice_fishing_pressed() -> void:
	App.go("res://scenes/IceFishingGame.tscn")

func _on_play_minigames_pressed() -> void:
	## Mock button: 50/50 chance of giving a card or not
	var got_card := randi() % 2 == 0
	
	play_minigames_button.disabled = true
	
	if got_card:
		# Add a card to the player's collection
		App.add_card_from_minigame_win()
		play_minigames_button.text = "You got a card!"
		# Show/update the card icon button
		if card_icon_button:
			card_icon_button.visible = true
	else:
		play_minigames_button.text = "No card this time..."
	
	# Reset button after a short delay
	await get_tree().create_timer(1.5).timeout
	play_minigames_button.text = "Play Minigames"
	play_minigames_button.disabled = false

func _on_battle_button_pressed() -> void:
	# Single-player quick battle entry (using a default territory id for now).
	if BattleStateManager:
		BattleStateManager.set_current_territory("default")
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
	if not App.is_multiplayer:
		if App.pending_return_map_sub_phase >= 0:
			map_sub_phase = App.pending_return_map_sub_phase as MapSubPhase
			App.pending_return_map_sub_phase = -1
		else:
			map_sub_phase = MapSubPhase.CLAIMING
		if App.returning_from_territory_minigame:
			App.returning_from_territory_minigame = false
			App.on_minigame_completed()

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
	## Single-player map flow: CLAIMING -> RESOURCE_COLLECTION -> BATTLE_READY
	if not App.is_multiplayer and current_phase == Phase.GAME_READY:
		# Hide the three standalone minigame buttons (Bridge / Ice fishing / River); minigames are played via territories
		minigame_button.visible = false
		bridge_minigame_button.visible = false
		ice_fishing_button.visible = false
		play_minigames_button.visible = false
		skip_to_battle_button.visible = false
		# Show minigame counter only in resource collection so player sees e.g. 1/2, 2/2
		minigames_counter_label.visible = (map_sub_phase == MapSubPhase.RESOURCE_COLLECTION)
		if minigames_counter_label.visible:
			_update_minigames_counter()
		battle_button.visible = false
		battle_button_right.visible = false
		left_battle_selectors.visible = false
		right_battle_selectors.visible = false
		if finish_claiming_button:
			finish_claiming_button.visible = (map_sub_phase == MapSubPhase.CLAIMING)
		if ready_for_battle_button:
			ready_for_battle_button.visible = (map_sub_phase == MapSubPhase.RESOURCE_COLLECTION)
		if map_sub_phase == MapSubPhase.BATTLE_READY:
			battle_button.visible = true
		settings_button.visible = true
		if App.player_card_collection.size() > 0:
			card_icon_button.visible = true
		return

	## Multiplayer or non-GAME_READY: use App phase
	match App.current_game_phase:
		App.GamePhase.RESOURCE_PHASE:
			# Show all minigame buttons in a row
			minigame_button.visible = true
			bridge_minigame_button.visible = true
			ice_fishing_button.visible = true
			play_minigames_button.visible = false  # Hide mock button
			skip_to_battle_button.visible = true
			battle_button.visible = false
			battle_button_right.visible = false
			left_battle_selectors.visible = false
			right_battle_selectors.visible = false
			current_decider_label.visible = false
			skip_battle_decision_button.visible = false
			minigames_counter_label.visible = true
			_update_minigames_counter()

			# Check host-authoritative done state for multiplayer
			var should_disable_minigames := false
			if App.is_multiplayer and multiplayer.has_multiplayer_peer():
				var my_id := multiplayer.get_unique_id()
				# Check if host marked us as done
				if Net.player_done_state.get(my_id, false):
					should_disable_minigames = true
				# Also check minigame count from host
				var count: int = Net.player_minigame_counts.get(my_id, 0)
				if count >= App.MAX_MINIGAMES_PER_PHASE:
					should_disable_minigames = true
			
			if should_disable_minigames:
				minigame_button.disabled = true
				bridge_minigame_button.disabled = true
				ice_fishing_button.disabled = true
				play_minigames_button.disabled = true
				skip_to_battle_button.disabled = true
				_show_waiting_for_others_overlay()
			else:
				# Re-enable buttons when returning to resource phase
				minigame_button.disabled = false
				bridge_minigame_button.disabled = false
				ice_fishing_button.disabled = false
				play_minigames_button.disabled = false
				skip_to_battle_button.disabled = false
				waiting_overlay.visible = false
				is_waiting_for_others = false

		App.GamePhase.BATTLE_PHASE:
			# Hide all minigame buttons
			minigame_button.visible = false
			bridge_minigame_button.visible = false
			ice_fishing_button.visible = false
			play_minigames_button.visible = false
			skip_to_battle_button.visible = false
			minigames_counter_label.visible = false

			if App.is_multiplayer:
				# Multiplayer: use battle selection UI
				_update_battle_selection_ui()
			else:
				# Single player: just show battle button
				battle_button.visible = true

	# Settings is always visible when game is ready
	settings_button.visible = true

	# Card icon button is always visible when game is ready (if player has cards)
	if App.player_card_collection.size() > 0:
		card_icon_button.visible = true

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
	if ice_fishing_button.visible:
		ice_fishing_button.modulate.a = 0.0
		btn_tween.tween_property(ice_fishing_button, "modulate:a", 1.0, 0.3)
	if play_minigames_button.visible:
		play_minigames_button.modulate.a = 0.0
		btn_tween.tween_property(play_minigames_button, "modulate:a", 1.0, 0.3)
	if battle_button.visible:
		battle_button.modulate.a = 0.0
		btn_tween.tween_property(battle_button, "modulate:a", 1.0, 0.3)
	if skip_to_battle_button.visible:
		skip_to_battle_button.modulate.a = 0.0
		btn_tween.tween_property(skip_to_battle_button, "modulate:a", 1.0, 0.3)
	if minigames_counter_label.visible:
		minigames_counter_label.modulate.a = 0.0
		btn_tween.tween_property(minigames_counter_label, "modulate:a", 1.0, 0.3)
	if card_icon_button.visible:
		card_icon_button.modulate.a = 0.0
		btn_tween.tween_property(card_icon_button, "modulate:a", 1.0, 0.3)
	if finish_claiming_button and finish_claiming_button.visible:
		finish_claiming_button.modulate.a = 0.0
		btn_tween.tween_property(finish_claiming_button, "modulate:a", 1.0, 0.3)
	if ready_for_battle_button and ready_for_battle_button.visible:
		ready_for_battle_button.modulate.a = 0.0
		btn_tween.tween_property(ready_for_battle_button, "modulate:a", 1.0, 0.3)

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

	# Multiplayer: skip marks you as done; stay on this scene and wait for others
	if App.is_multiplayer and multiplayer.has_multiplayer_peer():
		_show_waiting_for_others_overlay()
		return

	# Single player: transition immediately (existing behavior)
	App.go("res://scenes/ui/GameIntro.tscn")

## ========== END PHASE SYSTEM UI ==========

## ========== PLAYER HAND DISPLAY ==========

func _setup_card_icon_button() -> void:
	## Sets up the card icon button with a card back texture
	if not card_icon_button:
		return

	var card_icon := card_icon_button.get_node_or_null("CardIcon")
	if card_icon and card_icon is TextureRect:
		# Load cardback sprite frames and get the first frame
		var cardback_frames: SpriteFrames = load("res://assets/cardback.pxo")
		if cardback_frames and cardback_frames.has_animation("default"):
			var frame_count := cardback_frames.get_frame_count("default")
			if frame_count > 0:
				card_icon.texture = cardback_frames.get_frame_texture("default", 0)

func _on_card_icon_pressed() -> void:
	## Toggles the hand display panel visibility
	is_hand_visible = !is_hand_visible

	if is_hand_visible:
		_populate_hand_display()
		hand_display_panel.visible = true
		hand_display_panel.modulate.a = 0.0
		var tween := create_tween()
		tween.tween_property(hand_display_panel, "modulate:a", 1.0, 0.2)
	else:
		var tween := create_tween()
		tween.tween_property(hand_display_panel, "modulate:a", 0.0, 0.15)
		tween.tween_callback(func(): hand_display_panel.visible = false)

func _populate_hand_display() -> void:
	## Populates the hand container with card images from App.player_card_collection
	if not hand_container:
		return

	# Clear existing cards
	for child in hand_container.get_children():
		child.queue_free()

	# Create card visuals from App.player_card_collection
	for card_data in App.player_card_collection:
		var card_visual := TextureRect.new()
		card_visual.expand_mode = TextureRect.EXPAND_FIT_HEIGHT_PROPORTIONAL
		card_visual.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		card_visual.custom_minimum_size = Vector2(80, 120)

		# Load the sprite frames and get the correct frame
		# player_card_collection uses "path" and "frame" keys
		var sprite_frames_path: String = card_data.get("path", "")
		var frame_index: int = int(card_data.get("frame", 0))

		if not sprite_frames_path.is_empty():
			var sprite_frames: SpriteFrames = load(sprite_frames_path)
			if sprite_frames and sprite_frames.has_animation("default"):
				var frame_count := sprite_frames.get_frame_count("default")
				if frame_count > frame_index:
					card_visual.texture = sprite_frames.get_frame_texture("default", frame_index)

		hand_container.add_child(card_visual)

func _show_card_icon_button() -> void:
	## Shows the card icon button with a fade-in animation
	if card_icon_button and App.player_card_collection.size() > 0:
		card_icon_button.visible = true
		card_icon_button.modulate.a = 0.0
		var tween := create_tween()
		tween.tween_property(card_icon_button, "modulate:a", 1.0, 0.3)

## ========== END PLAYER HAND DISPLAY ==========

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

# ========== MULTIPLAYER BATTLE SELECTION SYSTEM ==========

func _connect_net_signals() -> void:
	## Connect to Net signals for multiplayer phase/battle sync
	if not Net.phase_changed.is_connected(_on_net_phase_changed):
		Net.phase_changed.connect(_on_net_phase_changed)
	if not Net.done_counts_updated.is_connected(_on_done_counts_updated):
		Net.done_counts_updated.connect(_on_done_counts_updated)
	if not Net.battle_decider_changed.is_connected(_on_battle_decider_changed):
		Net.battle_decider_changed.connect(_on_battle_decider_changed)
	if not Net.battle_choices_updated.is_connected(_on_battle_choices_updated):
		Net.battle_choices_updated.connect(_on_battle_choices_updated)
	if not Net.battle_started.is_connected(_on_battle_started):
		Net.battle_started.connect(_on_battle_started)
	if not Net.battle_finished_broadcast.is_connected(_on_battle_finished):
		Net.battle_finished_broadcast.connect(_on_battle_finished)

func _on_net_phase_changed(phase_id: int) -> void:
	print("[GameIntro] Phase changed to: ", phase_id)

	var prev_phase := App.current_game_phase

	if phase_id == 0:
		App.current_game_phase = App.GamePhase.RESOURCE_PHASE
		App.minigames_completed_this_phase = 0
		App.phase_transition_text = "Collect Your Resources"
	else:
		App.current_game_phase = App.GamePhase.BATTLE_PHASE
		App.phase_transition_text = "Choose Your Battles"

	# Only show the overlay if the phase actually changed
	App.show_phase_transition = (App.current_game_phase != prev_phase)

	is_waiting_for_others = false
	waiting_overlay.visible = false

	minigame_button.disabled = false
	bridge_minigame_button.disabled = false
	ice_fishing_button.disabled = false
	play_minigames_button.disabled = false
	skip_to_battle_button.disabled = false

	if App.show_phase_transition:
		_show_phase_transition_overlay()
	else:
		# No overlay; just apply UI immediately
		_apply_phase_ui()

func _on_done_counts_updated(done: int, total: int) -> void:
	## Update waiting overlay with done counts
	local_done_count = done
	local_total_count = total

	if is_waiting_for_others and waiting_overlay.visible:
		waiting_label.text = "Waiting for other players... (%d/%d done)" % [done, total]
	
	# ROBUSTNESS: Check if Net phase has advanced but App phase hasn't
	var net_phase_as_enum := App.GamePhase.RESOURCE_PHASE if Net.current_phase == 0 else App.GamePhase.BATTLE_PHASE
	if net_phase_as_enum != App.current_game_phase:
		_on_net_phase_changed(Net.current_phase)
		print("[GameIntro] Phase mismatch detected (Net: %d, App: %d). Forcing sync." % [Net.current_phase, App.current_game_phase])
		_on_net_phase_changed(Net.current_phase)

func _on_battle_decider_changed(peer_id: int) -> void:
	## Update UI when battle decider changes
	print("[GameIntro] Battle decider changed to: ", peer_id)
	_update_battle_selection_ui()

func _on_battle_choices_updated(snapshot: Dictionary) -> void:
	## Update battle selection UI when choices change
	print("[GameIntro] Battle choices updated: ", snapshot)
	_update_battle_selection_ui()

func _on_battle_started(p1_id: int, p2_id: int, side: String) -> void:
	## Handle battle start - participants enter battle, others show waiting
	var my_id := multiplayer.get_unique_id()

	if my_id == p1_id or my_id == p2_id:
		# We're a participant - go to battle
		print("[GameIntro] Entering battle as participant")
		if BattleStateManager:
			# For now, use a simple territory id; can be wired to map/side later.
			var territory_id := "%s_%s_battle" % [str(p1_id), str(p2_id)]
			BattleStateManager.set_current_territory(territory_id)
		App.go("res://scenes/card_battle.tscn")
	else:
		# We're a spectator - show waiting overlay
		print("[GameIntro] Battle in progress, waiting...")
		_show_battle_in_progress_overlay()

func _on_battle_finished() -> void:
	## Handle battle finished broadcast - hide waiting overlay
	print("[GameIntro] Battle finished, resuming")
	waiting_overlay.visible = false
	is_waiting_for_others = false
	# Use _apply_phase_ui to properly handle any phase transition that may have occurred
	_apply_phase_ui()

func _on_left_battle_pressed() -> void:
	## Handle left battle button press
	if App.is_multiplayer and multiplayer.has_multiplayer_peer():
		# In multiplayer, submit choice to host
		Net.request_battle_choice("LEFT")
	else:
		# Single player - go directly to battle
		if BattleStateManager:
			BattleStateManager.set_current_territory("default")
		App.go("res://scenes/card_battle.tscn")

func _on_right_battle_pressed() -> void:
	## Handle right battle button press (multiplayer only)
	if App.is_multiplayer and multiplayer.has_multiplayer_peer():
		Net.request_battle_choice("RIGHT")

func _on_skip_battle_decision_pressed() -> void:
	## Handle skip battle decision button press (multiplayer only)
	if App.is_multiplayer and multiplayer.has_multiplayer_peer():
		Net.request_battle_choice("SKIP")

func _update_battle_selection_ui() -> void:
	## Update battle selection UI based on current state
	if not App.is_multiplayer:
		return

	if App.current_game_phase != App.GamePhase.BATTLE_PHASE:
		# Hide battle selection UI in resource phase
		battle_button_right.visible = false
		left_battle_selectors.visible = false
		right_battle_selectors.visible = false
		current_decider_label.visible = false
		skip_battle_decision_button.visible = false
		return

	# Check if battle is in progress
	if Net.battle_in_progress:
		_show_battle_in_progress_overlay()
		return

	var my_id := multiplayer.get_unique_id()
	var is_my_turn := (my_id == Net.battle_decider_peer_id)

	# Update current decider label
	var decider_name := _get_player_name_by_id(Net.battle_decider_peer_id)
	current_decider_label.text = "Current decider: %s" % decider_name
	current_decider_label.visible = true

	# Show both battle buttons
	battle_button.visible = true
	battle_button_right.visible = true
	left_battle_selectors.visible = true
	right_battle_selectors.visible = true

	# Update selector lists
	_update_battle_selector_list(left_battle_selectors, Net.left_queue)
	_update_battle_selector_list(right_battle_selectors, Net.right_queue)

	# Check if queues are full
	var left_full := Net.left_queue.size() >= 2
	var right_full := Net.right_queue.size() >= 2

	if is_my_turn:
		# Enable buttons for decider (unless full)
		battle_button.disabled = left_full
		battle_button_right.disabled = right_full
		skip_battle_decision_button.visible = true
		skip_battle_decision_button.disabled = false
		waiting_overlay.visible = false

		# Update button text if full
		if left_full:
			battle_button.text = "Left Battle (FULL)"
		else:
			battle_button.text = "Left Battle"
		if right_full:
			battle_button_right.text = "Right Battle (FULL)"
		else:
			battle_button_right.text = "Right Battle"
	else:
		# Disable buttons for non-decider
		battle_button.disabled = true
		battle_button_right.disabled = true
		skip_battle_decision_button.visible = false

		# Show waiting message
		waiting_label.text = "Waiting for %s to choose..." % decider_name
		waiting_overlay.visible = true

func _update_battle_selector_list(container: VBoxContainer, queue: Array) -> void:
	## Update a selector container with player names/icons from queue
	# Clear existing
	for child in container.get_children():
		child.queue_free()

	# Add players in queue
	for pid in queue:
		var player_data := _get_player_data_by_id(pid)
		if player_data.is_empty():
			continue

		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", 5)

		# Race icon
		var race: String = String(player_data.get("race", "Elf"))  # NECESSARY: typed String to avoid Variant inference warning
		var icon := TextureRect.new()
		var texture = load(App.get_race_texture_path(race))
		if texture:
			icon.texture = texture
		icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(20, 20)
		item.add_child(icon)

		# Player name
		var name_label := Label.new()
		name_label.text = player_data.get("name", "Player")
		name_label.add_theme_font_override("font", UI_FONT)
		name_label.add_theme_font_size_override("font_size", 16)
		name_label.add_theme_color_override("font_color", App.get_race_color(race))
		item.add_child(name_label)

		container.add_child(item)

func _get_player_name_by_id(peer_id: int) -> String:
	## Get player name by peer ID
	for player in App.game_players:
		if player.get("id", -1) == peer_id:
			return player.get("name", "Player")
	return "Player"

func _get_player_data_by_id(peer_id: int) -> Dictionary:
	## Get full player data by peer ID
	for player in App.game_players:
		if player.get("id", -1) == peer_id:
			return player
	return {}

func _show_battle_in_progress_overlay() -> void:
	## Show waiting overlay during battle in progress
	waiting_label.text = "Battle in progress... waiting"
	waiting_overlay.visible = true
	is_waiting_for_others = true

func _show_waiting_for_others_overlay() -> void:
	## Show waiting overlay when player is done
	is_waiting_for_others = true
	
	# Compute done counts directly from Net state (not cached values which may be 0/0)
	var done := 0
	var total := Net.player_done_state.size()
	for pid in Net.player_done_state.keys():
		if Net.player_done_state.get(pid, false):
			done += 1
	if total == 0:
		# Fallback: use game_players count if Net state not initialized
		total = App.game_players.size()
	
	waiting_label.text = "Waiting for other players... (%d/%d done)" % [done, total]
	waiting_overlay.visible = true
	
	# Disable minigame buttons
	minigame_button.disabled = true
	bridge_minigame_button.disabled = true
	ice_fishing_button.disabled = true
	play_minigames_button.disabled = true
	skip_to_battle_button.disabled = true

# ========== END MULTIPLAYER BATTLE SELECTION SYSTEM ==========

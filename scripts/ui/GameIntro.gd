extends Control

const RACES := ["Elf", "Orc", "Fairy", "Infernal"]
const UI_FONT := preload("res://fonts/m5x7.ttf")

# Intro sequence (component)
const IntroSequenceUIScript := preload("res://scripts/ui/game_intro/IntroSequenceUI.gd")
var intro_ui: Node  # IntroSequenceUI instance
var intro_complete: bool = false

var map_sub_phase: int = PhaseController.MapSubPhase.CLAIMING

## Unified overlay state to prevent stacking
enum OverlayState { NONE, PHASE_TRANSITION, WAITING, D20_ROLLING }
var _overlay_state: OverlayState = OverlayState.NONE

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

# Claim territory panel (component - script-on-node)
var claim_ui: PanelContainer  # ClaimTerritoryUI instance (attached to ClaimTerritoryPanel)
var finish_claiming_button: Button
var ready_for_battle_button: Button

# Battle selection UI (component)
const BattleSelectionUIScript := preload("res://scripts/ui/game_intro/BattleSelectionUI.gd")
var battle_ui: Node  # BattleSelectionUI instance
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

# Phase overlay animation state - blocks UI updates during transition
var is_phase_overlay_animating: bool = false

var is_paused: bool = false


# Territory system
var territory_manager: TerritoryManager = null
var territories_container: Control = null
var _territory_claim_state: Node = null  # Autoload for territory claims (runtime lookup)
const TerritoryMapConfigScript := preload("res://scripts/TerritoryMapConfig.gd")
## Seconds to wait on map after 2 minigames before showing "Choose Your Battles"
const DELAY_BEFORE_BATTLE_TRANSITION_SEC := 1.0

## True during the delayed battle transition (wait before "Choose Your Battles"); blocks territory interaction
var _is_delayed_battle_transition_active := false

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

	# Claim territory panel (script-on-node component)
	claim_ui = $ClaimTerritoryPanel
	finish_claiming_button = get_node_or_null("FinishClaimingButton") as Button
	if finish_claiming_button:
		finish_claiming_button.pressed.connect(_on_finish_claiming_pressed)
	ready_for_battle_button = get_node_or_null("ReadyForBattleButton") as Button
	if ready_for_battle_button:
		ready_for_battle_button.pressed.connect(_on_ready_for_battle_pressed)

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

	# Map sub-phase buttons (single-player Claim & Conquer)
	if finish_claiming_button:
		finish_claiming_button.visible = false
	if ready_for_battle_button:
		ready_for_battle_button.visible = false

	# Setup card icon button texture (use cardback)
	_setup_card_icon_button()

	# Connect card icon button
	if card_icon_button:
		card_icon_button.pressed.connect(_on_card_icon_pressed)

	# Initialize IntroSequenceUI component
	intro_ui = IntroSequenceUIScript.new()
	intro_ui.name = "IntroSequenceUI"
	add_child(intro_ui)
	intro_ui.initialize({
		"showcase_container": showcase_container,
		"showcase_race_image": showcase_race_image,
		"showcase_name_label": showcase_name_label,
		"d20_container": d20_container,
		"d20_sprite": d20_sprite,
		"d20_anim": d20_anim,
		"roll_result_label": roll_result_label,
		"rolling_label": rolling_label,
		"player_roll_container": player_roll_container,
		"order_center_container": order_center_container,
		"order_list_center": order_list_center,
		"order_corner_container": order_corner_container,
		"map_overlay": map_overlay,
	})
	intro_ui.intro_completed.connect(_on_intro_completed)

	# Connect minigame buttons
	minigame_button.pressed.connect(_on_minigame_pressed)
	bridge_minigame_button.pressed.connect(_on_bridge_minigame_pressed)
	ice_fishing_button.pressed.connect(_on_ice_fishing_pressed)
	play_minigames_button.pressed.connect(_on_play_minigames_pressed)
	skip_to_battle_button.pressed.connect(_on_skip_to_battle_pressed)

	# Initialize BattleSelectionUI component (handles battle_button, battle_button_right, skip)
	battle_ui = BattleSelectionUIScript.new()
	battle_ui.name = "BattleSelectionUI"
	add_child(battle_ui)
	battle_ui.initialize({
		"battle_button": battle_button,
		"battle_button_right": battle_button_right,
		"left_battle_selectors": left_battle_selectors,
		"right_battle_selectors": right_battle_selectors,
		"current_decider_label": current_decider_label,
		"skip_battle_decision_button": skip_battle_decision_button,
	})

	# Connect settings
	if settings_button:
		settings_button.pressed.connect(_on_settings_pressed)
	# SettingsPanelUI (script-on-node) handles volume sliders; wire its signals here
	if settings_panel:
		settings_panel.resume_pressed.connect(toggle_pause)
		settings_panel.main_menu_pressed.connect(_on_main_menu_pressed)

	# Initialize territory system (registers TerritoryNodes, connects territory_selected -> claim panel)
	_initialize_territory_system()

	# Initialize ClaimTerritoryUI component (script-on-node, already has _ready())
	if claim_ui:
		claim_ui.initialize(territory_manager, _territory_claim_state)
		claim_ui.claim_submitted.connect(_on_claim_submitted)
		claim_ui.attack_submitted.connect(_on_attack_submitted)
		claim_ui.minigame_requested.connect(_on_claim_minigame_requested)

	# Connect PhaseController signals (used in both single-player and multiplayer)
	if not PhaseController.claiming_turn_finished.is_connected(_on_claiming_turn_finished):
		PhaseController.claiming_turn_finished.connect(_on_claiming_turn_finished)

	# Connect TerritoryClaimManager signals
	if not TerritoryClaimManager.claim_failed.is_connected(_on_claim_failed):
		TerritoryClaimManager.claim_failed.connect(_on_claim_failed)

	# Connect Net signals for multiplayer phase/battle sync
	if App.is_multiplayer:
		_connect_net_signals()
		# Note: Don't call _on_net_phase_changed here - wait for intro to complete

	# Check if we're returning from minigame (skip intro if turn_order already set)
	if App.turn_order.size() > 0:
		intro_ui.skip_intro()
		intro_complete = true
		_skip_to_game_ready()
		if App.returning_from_territory_battles:
			App.returning_from_territory_battles = false
			_apply_saved_territory_claims()
			_refresh_territory_claimed_visuals()
			call_deferred("_show_collect_resources_overlay")
		return

	# Start the intro sequence
	intro_ui.start_intro()

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
	## False during dice roll, phase overlay, delayed battle transition, or any non-map phase.
	if not intro_complete:
		return false
	if phase_overlay and phase_overlay.visible:
		return false
	if _is_delayed_battle_transition_active:
		return false
	if player_roll_container and player_roll_container.visible:
		return false
	return true

func _update_territory_interaction() -> void:
	## Enable or disable territory input based on interactability (prevents hover/click during transitions).
	if not territory_manager:
		return
	var interactable := _are_territories_interactable()
	for tid_key in territory_manager.territories:
		var node: TerritoryNode = territory_manager.territories[tid_key]
		node.mouse_filter = Control.MOUSE_FILTER_STOP if interactable else Control.MOUSE_FILTER_IGNORE

func _on_territory_selected(territory_id: int) -> void:
	if not _are_territories_interactable() or not claim_ui:
		return
	if map_sub_phase == PhaseController.MapSubPhase.RESOURCE_COLLECTION:
		if App.minigames_completed_this_phase >= App.MAX_MINIGAMES_PER_PHASE:
			claim_ui.show_unclaimed_territory_message()
			return
		var is_claimed: bool = _territory_claim_state != null and _territory_claim_state.call("is_claimed", territory_id)
		var owner_id: Variant = _territory_claim_state.call("get_owner_id", territory_id) if _territory_claim_state else null
		var local_id: Variant = _get_local_player_id()
		if not is_claimed or owner_id != local_id:
			claim_ui.show_unclaimed_territory_message()
			return
		claim_ui.open_play_only_panel(territory_id)
	else:
		claim_ui.open_claim_panel(territory_id, map_sub_phase, App.current_game_phase)

func _on_finish_claiming_pressed() -> void:
	## Called when "Done claiming" is clicked (skip_to_battle_button in CLAIMING sub-phase)
	if claim_ui:
		claim_ui.close_panel()
	PhaseController.finish_claiming_turn()

func _on_claiming_turn_finished(has_battles: bool) -> void:
	## UI response to finish_claiming_turn result
	if has_battles:
		return  # Battle scene will load
	if not App.is_multiplayer or not multiplayer.has_multiplayer_peer():
		_show_collect_resources_overlay()
	else:
		skip_to_battle_button.visible = false

func _show_collect_resources_overlay() -> void:
	# Ensure both Finish claiming buttons are hidden when entering resource collection
	skip_to_battle_button.visible = false
	if finish_claiming_button:
		finish_claiming_button.visible = false
	if not phase_overlay or not phase_label:
		_enter_resource_collection()
		return
	phase_label.text = "Collect your resources!"
	phase_overlay.visible = true
	phase_overlay.modulate.a = 0.0
	_update_territory_interaction()
	# Auto-dismiss like battle phase: fade in, hold, fade out, then enter resource collection
	var tween := create_tween()
	tween.tween_property(phase_overlay, "modulate:a", 1.0, 0.4)
	tween.tween_interval(1.5)
	tween.tween_property(phase_overlay, "modulate:a", 0.0, 0.4)
	tween.tween_callback(_on_collect_resources_overlay_finished)

func _on_collect_resources_overlay_finished() -> void:
	phase_overlay.visible = false
	_update_territory_interaction()
	_enter_resource_collection()

func _enter_resource_collection() -> void:
	PhaseController.enter_resource_collection()
	map_sub_phase = PhaseController.map_sub_phase
	_apply_phase_ui()
	_animate_phase_buttons()

func _on_ready_for_battle_pressed() -> void:
	_transition_to_next_round()

func _transition_to_next_round() -> void:
	## Transition back to Claiming phase for the next round
	PhaseController.enter_next_claiming_round()
	map_sub_phase = PhaseController.map_sub_phase
	_apply_phase_ui()
	_animate_phase_buttons()
	
	# Show "Next Round" or "Claim & Conquer" overlay
	if phase_overlay and phase_label:
		phase_label.text = "Next Round: Claim Territories"
		phase_overlay.visible = true
		phase_overlay.modulate.a = 0.0
		# Block interaction while overlay is up
		_update_territory_interaction()
		
		var tween := create_tween()
		tween.tween_property(phase_overlay, "modulate:a", 1.0, 0.4)
		tween.tween_interval(1.5)
		tween.tween_property(phase_overlay, "modulate:a", 0.0, 0.4)
		tween.tween_callback(func(): 
			phase_overlay.visible = false
			# Re-enable interaction after overlay is gone
			_update_territory_interaction()
		)

func _start_delayed_battle_transition() -> void:
	## Wait a few seconds on the map, then transition to next round (Claiming)
	_is_delayed_battle_transition_active = true
	_update_territory_interaction()
	await get_tree().create_timer(DELAY_BEFORE_BATTLE_TRANSITION_SEC).timeout
	_is_delayed_battle_transition_active = false
	_transition_to_next_round()

func _on_claim_submitted(territory_id: int, cards: Array) -> void:
	## Handle claim submission from ClaimTerritoryUI
	var local_id: Variant = _get_local_player_id()
	if local_id == null:
		if claim_ui:
			claim_ui.close_panel()
		return
	var success := TerritoryClaimManager.claim_territory(territory_id, local_id, cards, territory_manager)
	if success:
		_refresh_territory_claimed_visuals()
		if claim_ui:
			claim_ui.close_panel()

func _on_attack_submitted(territory_id: int, cards: Array) -> void:
	## Handle attack submission from ClaimTerritoryUI
	TerritoryClaimManager.register_attack(territory_id, cards)
	if claim_ui:
		claim_ui.close_panel()
	_update_territory_interaction()

func _on_claim_minigame_requested(territory_id: int, region_id: int) -> void:
	## Handle minigame request from ClaimTerritoryUI
	TerritoryClaimManager.launch_territory_minigame(territory_id, region_id)

func _on_claim_failed(_territory_id: int, reason: String) -> void:
	## Handle claim failure from TerritoryClaimManager (e.g. already claimed)
	if reason != "invalid_territory" and claim_ui:
		claim_ui.show_already_claimed_message(reason)

func _get_local_player_id() -> Variant:
	for p in App.game_players:
		if p.get("is_local", false):
			return p.get("id", 1)
	return 1

func _apply_saved_territory_claims() -> void:
	TerritoryClaimManager.apply_saved_claims(territory_manager)
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
	if intro_ui and not intro_complete:
		intro_ui.process_frame(delta)

func _on_intro_completed() -> void:
	## Called by IntroSequenceUI when corner order is displayed and map ungray finishes.
	intro_complete = true

	if App.is_multiplayer and multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		if PhaseController.current_phase == 0:
			PhaseSync.host_init_card_command_phase()
			App.phase_transition_text = "Card Command"
		else:
			PhaseController.sync_app_game_phase()
			if PhaseController.current_phase == 1:
				map_sub_phase = PhaseController.map_sub_phase
		App.show_phase_transition = true
		_show_phase_transition_overlay()
	elif App.is_multiplayer and multiplayer.has_multiplayer_peer():
		PhaseController.sync_app_game_phase()
		if PhaseController.current_phase == 1:
			map_sub_phase = PhaseController.map_sub_phase
		App.show_phase_transition = true
		_show_phase_transition_overlay()
	else:
		App.enter_claim_conquer_phase()
		map_sub_phase = PhaseController.MapSubPhase.CLAIMING
		App.phase_transition_text = "Claim & Conquer"
		App.show_phase_transition = true
		_show_phase_transition_overlay()

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
	# intro_ui.skip_intro() already handled visual skip; just run post-intro logic

	# Check if we're returning from a territory minigame
	# Note: This block was previously duplicated. Consolidating here.
	if App.returning_from_territory_minigame:
		App.returning_from_territory_minigame = false
		if App.pending_return_map_sub_phase != -1:
			map_sub_phase = App.pending_return_map_sub_phase
			App.pending_return_map_sub_phase = -1
		
		# If 2 minigames done, start delayed transition to "Choose Your Battles" (or Next Round logic)
		if not App.is_multiplayer and App.current_game_phase == App.GamePhase.CLAIM_CONQUER and map_sub_phase == PhaseController.MapSubPhase.RESOURCE_COLLECTION and App.minigames_completed_this_phase >= App.MAX_MINIGAMES_PER_PHASE:
			_start_delayed_battle_transition()
			
		# Skip overlay when returning from minigame
		App.show_phase_transition = false

	# Ensure we're in Claim & Conquer for single-player when returning (so map_sub_phase UI applies)
	if not App.is_multiplayer and App.current_game_phase == App.GamePhase.CLAIM_CONQUER:
		pass # Already set above or correct.
		
	# Check if we're returning from territory battles (Finish Claiming sequence)
	if App.returning_from_territory_battles:
		print("[DEBUG] GameIntro: Returning from territory battles. Processing logic.")
		App.returning_from_territory_battles = false
		
		if App.is_multiplayer and multiplayer.has_multiplayer_peer():
			print("[DEBUG] Multiplayer: Requesting end claiming turn after battles.")
			# In multiplayer, we just tell the server we are done. 
			# The server will advance the turn and sync the new state.
			PhaseSync.request_end_claiming_turn()
		else:
			# Single Player Logic
			print("[DEBUG] Current Turn Index: ", App.current_turn_index, " Turn Order Size: ", App.turn_order.size())
			
		if App.current_turn_index < App.turn_order.size():
			# Next Player's Turn
			var current_id = App.current_turn_player_id
			print("[DEBUG] Next player turn. Index: ", App.current_turn_index, " Name: ", _get_player_name_by_id(current_id))
			print("[GameIntro] Starting turn for player index: ", App.current_turn_index)
			
			App.current_game_phase = App.GamePhase.CARD_COMMAND # Logic implies Card Command follows
			map_sub_phase = PhaseController.MapSubPhase.CLAIMING 
			
			_apply_phase_ui()
			_show_phase_transition_overlay()
			if phase_label: 
				phase_label.text = "Card Command: " + _get_player_name_by_id(current_id)
		else:
			# All players done -> Resource Collection
			print("[DEBUG] Loop finished. All players done. Going to Resource Collection.")
			print("[GameIntro] All players finished claiming. Proceeding to Resource Collection.")
			App.current_turn_index = 0
			App.current_turn_player_id = App.turn_order[0].get("id", -1) if App.turn_order else -1
			
			PhaseController.enter_resource_collection()
			map_sub_phase = PhaseController.map_sub_phase
			_show_collect_resources_overlay()

	# Check if we need to show phase transition overlay
	if App.show_phase_transition:
		App.show_phase_transition = false
		_show_phase_transition_overlay()
	else:
		# Just apply phase-aware UI immediately with animation
		_apply_phase_ui()
		_animate_phase_buttons()

func _on_settings_pressed() -> void:
	toggle_pause()

func toggle_pause() -> void:
	is_paused = !is_paused
	settings_panel.visible = is_paused
	get_tree().paused = is_paused

	if settings_button:
		settings_button.visible = !is_paused

func _on_main_menu_pressed() -> void:
	get_tree().paused = false
	App.go("res://scenes/ui/MainMenu.tscn")

## ---------- PHASE SYSTEM UI ----------

func _set_overlay_state(state: OverlayState, text: String = "") -> void:
	## Unified overlay controller - only one overlay visible at a time
	_overlay_state = state
	# Hide all overlay elements first
	phase_overlay.visible = false
	waiting_overlay.visible = false
	
	match state:
		OverlayState.NONE:
			pass
		OverlayState.PHASE_TRANSITION:
			phase_label.text = text
			phase_overlay.visible = true
		OverlayState.WAITING:
			waiting_label.text = text
			waiting_overlay.visible = true
		OverlayState.D20_ROLLING:
			# During d20 rolling, use phase overlay for dimming only
			phase_label.text = ""
			phase_overlay.visible = true

func _apply_phase_ui() -> void:
	## Shows/hides buttons based on current game phase
	## Only applies when intro sequence is complete (intro_complete)
	## and phase overlay animation is not in progress
	if not intro_complete:
		return
	if is_phase_overlay_animating:
		return

	match App.current_game_phase:
		App.GamePhase.CARD_COMMAND:
			_apply_card_command_ui()
		App.GamePhase.CLAIM_CONQUER:
			_apply_claim_conquer_ui()
		App.GamePhase.CARD_COLLECTION:
			_apply_card_collection_ui()

	# Settings is always visible when game is ready
	settings_button.visible = true

	# Card icon button is always visible when game is ready (if player has cards)
	if App.player_card_collection.size() > 0:
		card_icon_button.visible = true

func _hide_battle_selection_ui() -> void:
	if battle_ui:
		battle_ui.hide_all()

func _apply_card_command_ui() -> void:
	# Hide all minigame buttons
	minigame_button.visible = false
	bridge_minigame_button.visible = false
	ice_fishing_button.visible = false
	play_minigames_button.visible = false
	skip_to_battle_button.visible = false
	minigames_counter_label.visible = false

	# Hide battle selection UI
	battle_button.visible = false
	_hide_battle_selection_ui()

	# TODO: Add "Place Cards" button UI here
	# NOTE: On first turn, player must place at least 1 card

	# For now, use skip_to_battle_button as placeholder "Done" button
	skip_to_battle_button.visible = true
	skip_to_battle_button.text = "Done Placing Cards"

	# Check if it's our turn (host-authoritative)
	if App.is_multiplayer and multiplayer.has_multiplayer_peer():
		var my_id := multiplayer.get_unique_id()
		if PhaseController.current_turn_peer_id != my_id:
			# Not our turn - show waiting overlay
			skip_to_battle_button.visible = false
			var turn_name := _get_player_name_for_peer(PhaseController.current_turn_peer_id)
			_set_overlay_state(OverlayState.WAITING, "Waiting for %s..." % turn_name)
			is_waiting_for_others = true
		else:
			# Our turn - hide overlay, show button
			_set_overlay_state(OverlayState.NONE)
			is_waiting_for_others = false
	else:
		_set_overlay_state(OverlayState.NONE)
		is_waiting_for_others = false

func _apply_claim_conquer_ui() -> void:
	# Hide standalone minigame buttons (territory-based minigames used instead)
	minigame_button.visible = false
	bridge_minigame_button.visible = false
	ice_fishing_button.visible = false
	play_minigames_button.visible = false
	skip_to_battle_button.visible = false
	# Hide battle selection UI until BATTLE_READY
	_hide_battle_selection_ui()

	# Both single-player and multiplayer: use map sub-phases
	battle_button.visible = false
	match map_sub_phase:
		PhaseController.MapSubPhase.CLAIMING:
			_apply_claiming_ui()
		PhaseController.MapSubPhase.RESOURCE_COLLECTION:
			_apply_resource_collection_ui()
		PhaseController.MapSubPhase.BATTLE_READY:
			_apply_battle_ready_ui()
	_update_territory_interaction()

func _apply_claiming_ui() -> void:
	# Turn-based claiming: "Done claiming" on your turn, "Waiting for [name]..." when not
	if finish_claiming_button:
		finish_claiming_button.visible = false
	if ready_for_battle_button:
		ready_for_battle_button.visible = false
	minigames_counter_label.visible = false
	if App.is_multiplayer and multiplayer.has_multiplayer_peer():
		var my_id := multiplayer.get_unique_id()
		if PhaseController.current_turn_peer_id != my_id:
			skip_to_battle_button.visible = false
			var turn_name := _get_player_name_for_peer(PhaseController.current_turn_peer_id)
			_set_overlay_state(OverlayState.WAITING, "Waiting for %s..." % turn_name)
			is_waiting_for_others = true
		else:
			skip_to_battle_button.visible = true
			skip_to_battle_button.text = "Done claiming"
			_set_overlay_state(OverlayState.NONE)
			is_waiting_for_others = false
	else:
		skip_to_battle_button.visible = true
		skip_to_battle_button.text = "Done claiming"
		_set_overlay_state(OverlayState.NONE)
		is_waiting_for_others = false

func _apply_resource_collection_ui() -> void:
	if finish_claiming_button:
		finish_claiming_button.visible = false
	if ready_for_battle_button:
		ready_for_battle_button.visible = false
	skip_to_battle_button.visible = false
	minigames_counter_label.visible = true
	_update_minigames_counter()
	if App.is_multiplayer:
		# Multiplayer: check if we're done (host-authoritative)
		var should_disable_minigames := false
		if multiplayer.has_multiplayer_peer():
			var my_id := multiplayer.get_unique_id()
			if PhaseController.player_done_state.get(my_id, false):
				should_disable_minigames = true
			var count: int = PhaseController.player_minigame_counts.get(my_id, 0)
			if count >= App.MAX_MINIGAMES_PER_PHASE:
				should_disable_minigames = true
		if should_disable_minigames:
			var _done := 0
			for _pid in PhaseController.player_done_state:
				if PhaseController.player_done_state.get(_pid, false):
					_done += 1
			var _total := maxi(PhaseController.player_done_state.size(), 1)
			# If ALL players are done, transition to BATTLE_READY immediately - don't show waiting.
			# Critical for last player who returns from minigame (may miss done_counts_updated signal).
			if _total > 0 and _done >= _total:
				_transition_to_next_round()
			else:
				_set_overlay_state(OverlayState.WAITING, "Waiting for other players... (%d/%d done)" % [_done, _total])
				is_waiting_for_others = true
		else:
			_set_overlay_state(OverlayState.NONE)
			is_waiting_for_others = false

func _apply_battle_ready_ui() -> void:
	if finish_claiming_button:
		finish_claiming_button.visible = false
	if ready_for_battle_button:
		ready_for_battle_button.visible = false
	if App.is_multiplayer:
		_update_battle_selection_ui()
		# Overlay state based on battle_ui results
		if battle_ui.is_battle_in_progress():
			_set_overlay_state(OverlayState.WAITING, "Battle in progress... waiting")
			is_waiting_for_others = true
		elif multiplayer.has_multiplayer_peer() and multiplayer.get_unique_id() != BattleSync.battle_decider_peer_id:
			var decider_name := battle_ui.get_decider_name()
			_set_overlay_state(OverlayState.WAITING, "Waiting for %s to choose..." % decider_name)
		else:
			_set_overlay_state(OverlayState.NONE)
	else:
		battle_button.visible = true
	minigames_counter_label.visible = false

func _apply_card_collection_ui() -> void:
	# Show all minigame buttons in a row (minigame counter only during RESOURCE_COLLECTION, not here)
	minigame_button.visible = true
	bridge_minigame_button.visible = true
	ice_fishing_button.visible = true
	play_minigames_button.visible = false  # Hide mock button
	skip_to_battle_button.visible = true
	skip_to_battle_button.text = "Skip to Next Round"
	battle_button.visible = false
	_hide_battle_selection_ui()
	minigames_counter_label.visible = false

	# Check host-authoritative done state for multiplayer
	var should_disable_minigames := false
	if App.is_multiplayer and multiplayer.has_multiplayer_peer():
		var my_id := multiplayer.get_unique_id()
		# Check if host marked us as done
		if PhaseController.player_done_state.get(my_id, false):
			should_disable_minigames = true
		# Also check minigame count from host
		var count: int = PhaseController.player_minigame_counts.get(my_id, 0)
		if count >= App.MAX_MINIGAMES_PER_PHASE:
			should_disable_minigames = true

	if should_disable_minigames:
		minigame_button.disabled = true
		bridge_minigame_button.disabled = true
		ice_fishing_button.disabled = true
		play_minigames_button.disabled = true
		skip_to_battle_button.disabled = true
		var _done_c := 0
		for _pid in PhaseController.player_done_state:
			if PhaseController.player_done_state.get(_pid, false):
				_done_c += 1
		var _total_c := maxi(App.turn_order.size(), 1)
		_set_overlay_state(OverlayState.WAITING, "Waiting for other players... (%d/%d done)" % [_done_c, _total_c])
		is_waiting_for_others = true
	else:
		# Re-enable buttons
		minigame_button.disabled = false
		bridge_minigame_button.disabled = false
		ice_fishing_button.disabled = false
		play_minigames_button.disabled = false
		skip_to_battle_button.disabled = false
		_set_overlay_state(OverlayState.NONE)
		is_waiting_for_others = false

func _get_player_name_for_peer(peer_id: int) -> String:
	## Helper to get player name from peer ID
	if PlayerDataSync.player_names.has(peer_id):
		return PlayerDataSync.player_names[peer_id]
	for player in App.turn_order:
		if player.get("id", -1) == peer_id:
			return player.get("name", "Player")
	return "Player"

func _show_phase_transition_overlay() -> void:
	## Shows a brief overlay announcing the current phase
	if not phase_overlay or not phase_label:
		_apply_phase_ui()
		return
	phase_label.text = App.phase_transition_text
	phase_overlay.visible = true
	phase_overlay.modulate.a = 0.0
	
	# Block all UI updates while overlay is animating
	is_phase_overlay_animating = true

	# Fade in
	var tween := create_tween()
	tween.tween_property(phase_overlay, "modulate:a", 1.0, 0.4)
	tween.tween_interval(1.5)  # Hold for 1.5 seconds
	tween.tween_property(phase_overlay, "modulate:a", 0.0, 0.4)
	tween.tween_callback(_on_phase_transition_finished)

func _on_phase_transition_finished() -> void:
	phase_overlay.visible = false
	# Allow UI updates now that overlay is done
	is_phase_overlay_animating = false
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
	## Updates the minigames counter label. Only shown during RESOURCE_COLLECTION; uses synced count in multiplayer.
	if not minigames_counter_label:
		return
	var count: int
	if App.is_multiplayer and multiplayer.has_multiplayer_peer():
		count = PhaseController.player_minigame_counts.get(multiplayer.get_unique_id(), 0)
	else:
		count = App.minigames_completed_this_phase
	minigames_counter_label.text = "Minigames: %d/%d" % [count, App.MAX_MINIGAMES_PER_PHASE]

func _on_skip_to_battle_pressed() -> void:
	## Handle skip/done button press - behavior depends on phase
	# In CLAIM_CONQUER CLAIMING, this button is "Finish claiming"
	if App.current_game_phase == App.GamePhase.CLAIM_CONQUER and map_sub_phase == PhaseController.MapSubPhase.CLAIMING:
		_on_finish_claiming_pressed()
		return
	match App.current_game_phase:
		App.GamePhase.CARD_COMMAND:
			# In Card Command phase, this is "Done Placing Cards"
			# Hide the button immediately to prevent double-clicking
			skip_to_battle_button.visible = false
			
			if App.is_multiplayer and multiplayer.has_multiplayer_peer():
				# Capture current phase before RPC (RPC may trigger phase change)
				var prev_phase := App.current_game_phase
				# Use turn-based advancement (not done counting)
				PhaseSync.request_end_card_command_turn()
				# Only show waiting overlay if phase didn't change (more turns to go)
				# If phase changed, the RPC handler already showed the phase overlay
				if App.current_game_phase == prev_phase:
					_set_overlay_state(OverlayState.WAITING, "Waiting for other players...")
					is_waiting_for_others = true
			else:
				# Single player: move to Claim & Conquer
				App.enter_claim_conquer_phase()
				_show_phase_transition_overlay()
		
		App.GamePhase.CARD_COLLECTION:
			# In Card Collection phase, this is "Skip to Next Round"
			if App.is_multiplayer and multiplayer.has_multiplayer_peer():
				# Capture current phase before RPC (RPC may trigger phase change)
				var prev_phase := App.current_game_phase
				App.skip_to_done()
				# Only show waiting overlay if phase didn't change (more players to go)
				if App.current_game_phase == prev_phase:
					_set_overlay_state(OverlayState.WAITING, "Waiting for other players...")
					is_waiting_for_others = true
			else:
				App.skip_to_done()
				# Single player: loop back to Card Command
				App.enter_card_command_phase()
				_show_phase_transition_overlay()
		
		_:
			# Fallback for any other phase
			App.skip_to_done()

## ---------- END PHASE SYSTEM UI ----------

## ---------- PLAYER HAND DISPLAY ----------

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

## ---------- END PLAYER HAND DISPLAY ----------

# ---------- MULTIPLAYER BATTLE SELECTION SYSTEM ----------

func _connect_net_signals() -> void:
	## Connect to decoupled module signals for multiplayer phase/battle sync
	if not PhaseController.phase_changed.is_connected(_on_net_phase_changed):
		PhaseController.phase_changed.connect(_on_net_phase_changed)
	if not PhaseController.done_counts_updated.is_connected(_on_done_counts_updated):
		PhaseController.done_counts_updated.connect(_on_done_counts_updated)
	if not PhaseController.turn_changed.is_connected(_on_turn_changed):
		PhaseController.turn_changed.connect(_on_turn_changed)
	if not BattleSync.battle_decider_changed.is_connected(_on_battle_decider_changed):
		BattleSync.battle_decider_changed.connect(_on_battle_decider_changed)
	if not BattleSync.battle_choices_updated.is_connected(_on_battle_choices_updated):
		BattleSync.battle_choices_updated.connect(_on_battle_choices_updated)
	if not BattleSync.battle_started.is_connected(_on_battle_started):
		BattleSync.battle_started.connect(_on_battle_started)
	if not BattleSync.battle_finished_broadcast.is_connected(_on_battle_finished):
		BattleSync.battle_finished_broadcast.connect(_on_battle_finished)
	if not TerritorySync.territory_claimed.is_connected(_on_net_territory_claimed):
		TerritorySync.territory_claimed.connect(_on_net_territory_claimed)
	if not TerritorySync.territory_claim_rejected.is_connected(_on_net_territory_claim_rejected):
		TerritorySync.territory_claim_rejected.connect(_on_net_territory_claim_rejected)
	if not PhaseController.map_sub_phase_changed.is_connected(_on_net_map_sub_phase_changed):
		PhaseController.map_sub_phase_changed.connect(_on_net_map_sub_phase_changed)

func _on_net_phase_changed(phase_id: int) -> void:
	print("[GameIntro] Phase changed to: ", phase_id)

	var prev_phase := App.current_game_phase
	PhaseController.sync_app_game_phase()
	# Card Collection resets minigame count
	if phase_id == 2:
		App.minigames_completed_this_phase = 0

	# Only update UI if intro sequence is complete
	if not intro_complete:
		print("[GameIntro] Intro not complete, deferring UI update")
		return

	# Only show the overlay if the phase actually changed
	App.show_phase_transition = (App.current_game_phase != prev_phase)
	# In multiplayer, suppress Claim & Conquer overlay (seamless continuation from Card Command)
	if App.is_multiplayer and App.current_game_phase == App.GamePhase.CLAIM_CONQUER:
		App.show_phase_transition = false

	is_waiting_for_others = false
	_set_overlay_state(OverlayState.NONE)

	minigame_button.disabled = false
	bridge_minigame_button.disabled = false
	ice_fishing_button.disabled = false
	play_minigames_button.disabled = false
	skip_to_battle_button.disabled = false

	if App.show_phase_transition:
		_show_phase_transition_overlay()
	else:
		_apply_phase_ui()

func _on_turn_changed(peer_id: int) -> void:
	## Update UI when turn changes
	print("[GameIntro] Turn changed to: ", peer_id)
	# Reapply phase UI to update whose turn it is
	# But skip if phase overlay is animating
	if intro_complete and not is_phase_overlay_animating:
		_apply_phase_ui()

func _on_done_counts_updated(done: int, total: int) -> void:
	## Update waiting overlay with done counts
	local_done_count = done
	local_total_count = total

	# Keep minigame counter correct when synced counts update (multiplayer)
	if App.current_game_phase == App.GamePhase.CLAIM_CONQUER and map_sub_phase == PhaseController.MapSubPhase.RESOURCE_COLLECTION and minigames_counter_label.visible:
		_update_minigames_counter()

	# When ALL players are done (done >= total), transition to BATTLE_READY immediately - for BOTH host and client.
	# Do this regardless of is_waiting_for_others so the last player (who just returned from minigame) also transitions.
	if total > 0 and done >= total and App.current_game_phase == App.GamePhase.CLAIM_CONQUER and map_sub_phase == PhaseController.MapSubPhase.RESOURCE_COLLECTION:
		_transition_to_next_round()
		return

	if is_waiting_for_others and _overlay_state == OverlayState.WAITING:
		waiting_label.text = "Waiting for other players... (%d/%d done)" % [done, total]
	
	# TODO: move phase mismatch repair to PhaseController (tightly coupled to UI callbacks for now)
	# ROBUSTNESS: Check if Net phase has advanced but App phase hasn't
	var net_phase_as_enum: App.GamePhase
	match PhaseController.current_phase:
		0: net_phase_as_enum = App.GamePhase.CARD_COMMAND
		1: net_phase_as_enum = App.GamePhase.CLAIM_CONQUER
		2: net_phase_as_enum = App.GamePhase.CARD_COLLECTION
		_: net_phase_as_enum = App.GamePhase.CARD_COMMAND
	if net_phase_as_enum != App.current_game_phase:
		print("[GameIntro] Phase mismatch detected (Net: %d, App: %d). Forcing sync." % [PhaseController.current_phase, App.current_game_phase])
		_on_net_phase_changed(PhaseController.current_phase)
	# Also sync map_sub_phase when in CLAIM_CONQUER and we're behind (Net has advanced)
	if App.current_game_phase == App.GamePhase.CLAIM_CONQUER and map_sub_phase < PhaseController.map_sub_phase:
		print("[GameIntro] Map sub-phase behind (local: %d, Net: %d). Forcing sync." % [map_sub_phase, PhaseController.map_sub_phase])
		_on_net_map_sub_phase_changed(PhaseController.map_sub_phase)

func _on_battle_decider_changed(peer_id: int) -> void:
	## Update UI when battle decider changes
	print("[GameIntro] Battle decider changed to: ", peer_id)
	# Skip if phase overlay is animating
	if not is_phase_overlay_animating:
		_update_battle_selection_ui()

func _on_battle_choices_updated(snapshot: Dictionary) -> void:
	## Update battle selection UI when choices change
	print("[GameIntro] Battle choices updated: ", snapshot)
	# Skip if phase overlay is animating
	if not is_phase_overlay_animating:
		_update_battle_selection_ui()

func _on_battle_started(p1_id: int, p2_id: int, side: String) -> void:
	## Handle battle start - participants enter battle, others show waiting
	if not multiplayer.has_multiplayer_peer():
		return
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

func _on_net_territory_claimed(territory_id: int, owner_id: int, cards: Array) -> void:
	## Apply territory claim from Net sync (all peers receive this)
	var local_id: Variant = _get_local_player_id()
	TerritoryClaimManager.apply_network_claim(territory_id, owner_id, cards, local_id, territory_manager)
	_refresh_territory_claimed_visuals()
	if claim_ui and claim_ui.get_current_territory_id() == territory_id:
		claim_ui.close_panel()

func _on_net_territory_claim_rejected(territory_id: int, claimer_name: String) -> void:
	## Show message when server rejects claim (territory already claimed)
	if claim_ui and claim_ui.get_current_territory_id() == territory_id:
		claim_ui.show_already_claimed_message(claimer_name)

func _on_net_map_sub_phase_changed(sub_phase: int) -> void:
	## Sync map sub-phase (CLAIMING=0, RESOURCE_COLLECTION=1, BATTLE_READY=2)
	if sub_phase == 0:  # CLAIMING
		map_sub_phase = PhaseController.MapSubPhase.CLAIMING
		is_waiting_for_others = false
		waiting_overlay.visible = false
		_set_overlay_state(OverlayState.NONE)
		_apply_phase_ui()
		_animate_phase_buttons()
	elif sub_phase == 1:  # RESOURCE_COLLECTION
		# Hide both "Finish claiming" button and redundant FinishClaimingButton immediately
		skip_to_battle_button.visible = false
		if finish_claiming_button:
			finish_claiming_button.visible = false
		map_sub_phase = PhaseController.MapSubPhase.RESOURCE_COLLECTION
		App.minigames_completed_this_phase = 0
		is_waiting_for_others = false
		_show_collect_resources_overlay()
	elif sub_phase == 2:  # BATTLE_READY
		_transition_to_next_round()

func _update_battle_selection_ui() -> void:
	if battle_ui:
		battle_ui.update_ui()

func _get_player_name_by_id(peer_id: int) -> String:
	## Get player name by peer ID
	for player in App.game_players:
		if player.get("id", -1) == peer_id:
			return player.get("name", "Player")
	return "Player"

func _show_battle_in_progress_overlay() -> void:
	_set_overlay_state(OverlayState.WAITING, "Battle in progress... waiting")
	is_waiting_for_others = true

func _show_waiting_for_others_overlay() -> void:
	is_waiting_for_others = true
	var done := 0
	var total := PhaseController.player_done_state.size()
	for pid in PhaseController.player_done_state.keys():
		if PhaseController.player_done_state.get(pid, false):
			done += 1
	if total == 0:
		total = App.game_players.size()
	_set_overlay_state(OverlayState.WAITING, "Waiting for other players... (%d/%d done)" % [done, total])
	minigame_button.disabled = true
	bridge_minigame_button.disabled = true
	ice_fishing_button.disabled = true
	play_minigames_button.disabled = true
	skip_to_battle_button.disabled = true

# ---------- END MULTIPLAYER BATTLE SELECTION SYSTEM ----------

extends Control

## GameIntro — Thin orchestrator: resolves scene nodes, wires 8 UI components, routes cross-component signals.

# Component scripts
const IntroSequenceUIScript := preload("res://scripts/ui/game_intro/IntroSequenceUI.gd")
const BattleSelectionUIScript := preload("res://scripts/ui/game_intro/BattleSelectionUI.gd")
const PhaseSystemUIScript := preload("res://scripts/ui/game_intro/PhaseSystemUI.gd")
const TerritorySystemUIScript := preload("res://scripts/ui/game_intro/TerritorySystemUI.gd")
const PlayerHandUIScript := preload("res://scripts/ui/game_intro/PlayerHandUI.gd")
const GameFlowUIScript := preload("res://scripts/ui/game_intro/GameFlowUI.gd")
const TurnOrderBarUIScript := preload("res://scripts/ui/game_intro/TurnOrderBarUI.gd")
const BotControllerScript := preload("res://scripts/bots/BotController.gd")
const GnomeTutorialUIScript := preload("res://scripts/ui/game_intro/GnomeTutorialUI.gd")

# Component instances
var gnome_ui: Node
var intro_ui: Node
var battle_ui: Node
var phase_ui: Node
var territory_ui: Node
var hand_ui: Node
var flow_ui: Node
var turn_order_bar: Node
var claim_ui: PanelContainer  # Script-on-node (ClaimTerritoryUI)
var settings_panel: Panel      # Script-on-node (SettingsPanelUI)
var bot_controller: Node

var _showcase_container: CenterContainer
var intro_complete: bool = false
var is_paused: bool = false
var settings_button: Button

# Minigame selection timer
var _selection_timer: float = 0.0
var _selection_timer_active: bool = false
const SELECTION_TIME_LIMIT: float = 15.0
var _selection_timer_label: Label = null
var _minigame_buttons_ref: Array = []  # [river, bridge, icefishing]


func _ready() -> void:
	# ---------- Resolve scene nodes ----------
	var map_overlay := $MapOverlay as ColorRect
	var showcase_container := $ShowcaseContainer as CenterContainer
	_showcase_container = showcase_container
	var showcase_race_image := $ShowcaseContainer/VBoxContainer/RaceImageContainer/RaceImage as TextureRect
	var showcase_name_label := $ShowcaseContainer/VBoxContainer/NameLabel as Label
	var d20_container := $D20Container as CenterContainer
	var d20_sprite := $D20Container/VBoxContainer/D20Sprite as Panel
	var d20_anim := $D20Container/VBoxContainer/D20Sprite/D20Anim as TextureRect
	var roll_result_label := $D20Container/VBoxContainer/RollResultLabel as Label
	var rolling_label := $D20Container/VBoxContainer/RollingLabel as Label
	var player_roll_container := $PlayerRollContainer as CenterContainer
	var order_center_container := $OrderCenterContainer as CenterContainer
	var order_list_center := $OrderCenterContainer/Panel/MarginContainer/VBoxContainer/OrderList as VBoxContainer
	var minigame_button := $MinigameButton as Button
	var bridge_minigame_button := $BridgeMinigameButton as Button
	var ice_fishing_button := $IceFishingButton as Button

	# Courtly Cuisine button (created in code — not in the .tscn)
	var courtly_cuisine_button := Button.new()
	courtly_cuisine_button.name = "CourtlyCuisineButton"
	courtly_cuisine_button.visible = false
	courtly_cuisine_button.text = "Courtly Cuisine"
	courtly_cuisine_button.layout_mode = 1
	courtly_cuisine_button.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	courtly_cuisine_button.anchor_left = 0.5
	courtly_cuisine_button.anchor_top = 1.0
	courtly_cuisine_button.anchor_right = 0.5
	courtly_cuisine_button.anchor_bottom = 1.0
	courtly_cuisine_button.offset_left = 240.0
	courtly_cuisine_button.offset_top = -80.0
	courtly_cuisine_button.offset_right = 400.0
	courtly_cuisine_button.offset_bottom = -40.0
	courtly_cuisine_button.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var cc_font = load("res://fonts/m5x7.ttf")
	if cc_font:
		courtly_cuisine_button.add_theme_font_override("font", cc_font)
		courtly_cuisine_button.add_theme_font_size_override("font_size", 22)
	add_child(courtly_cuisine_button)
	var play_minigames_button := $PlayMinigamesButton as Button
	var battle_button := $BattleButton as Button
	var skip_to_battle_button := $SkipToBattleButton as Button
	settings_button = $SettingsButton as Button
	# Phase indicator bar — built in code so the editor doesn't need to reload
	var phase_indicator_bar := _create_phase_indicator_bar()
	add_child(phase_indicator_bar)
	settings_panel = $SettingsPanel as Panel
	var phase_overlay := $PhaseOverlay as ColorRect
	var phase_label := $PhaseOverlay/PhaseLabel as Label
	var minigames_counter_label := $MinigamesCounterLabel as Label
	var card_icon_button := $CardIconButton as Button
	var card_count_label := $CardCountLabel as Label
	var hand_display_panel := $HandDisplayPanel as PanelContainer
	var hand_container := $HandDisplayPanel/MarginContainer/VBoxContainer/HandContainer as HBoxContainer
	claim_ui = $ClaimTerritoryPanel as PanelContainer
	var finish_claiming_button := get_node_or_null("FinishClaimingButton") as Button
	var ready_for_battle_button := get_node_or_null("ReadyForBattleButton") as Button
	var battle_button_right := $BattleButtonRight as Button
	var left_battle_selectors := $LeftBattleSelectors as VBoxContainer
	var right_battle_selectors := $RightBattleSelectors as VBoxContainer
	var waiting_overlay := $WaitingOverlay as ColorRect
	var waiting_label := $WaitingOverlay/WaitingLabel as Label
	var current_decider_label := $CurrentDeciderLabel as Label
	var skip_battle_decision_button := $SkipBattleDecisionButton as Button

	# ---------- Initial visibility state ----------
	map_overlay.modulate.a = 0.6
	showcase_container.visible = true
	showcase_container.modulate.a = 1.0
	d20_container.visible = false
	order_center_container.visible = false
	for btn in [minigame_button, bridge_minigame_button, courtly_cuisine_button, ice_fishing_button,
				play_minigames_button, battle_button, skip_to_battle_button, battle_button_right]:
		btn.visible = false
	var victory_overlay := get_node_or_null("VictoryOverlay") as ColorRect
	for node in [settings_button, settings_panel, player_roll_container, phase_overlay,
				 minigames_counter_label, card_icon_button, hand_display_panel,
				 left_battle_selectors, right_battle_selectors, waiting_overlay,
				 current_decider_label, skip_battle_decision_button]:
		node.visible = false
	if victory_overlay:
		victory_overlay.visible = false
	if finish_claiming_button:
		finish_claiming_button.visible = false
	if ready_for_battle_button:
		ready_for_battle_button.visible = false

	# ---------- TurnBannerLabel (non-modal turn indicator, pixel font) ----------
	var turn_banner_label := Label.new()
	turn_banner_label.name = "TurnBannerLabel"
	turn_banner_label.visible = false
	turn_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	turn_banner_label.add_theme_font_override("font", load("res://fonts/m5x7.ttf"))
	turn_banner_label.add_theme_font_size_override("font_size", 32)
	turn_banner_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.55, 1.0))
	turn_banner_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	turn_banner_label.add_theme_constant_override("outline_size", 4)
	turn_banner_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	turn_banner_label.offset_top = 62.0
	turn_banner_label.offset_bottom = 100.0
	add_child(turn_banner_label)
	
	# ---------- Minigame selection timer label (top-right) ----------
	_selection_timer_label = Label.new()
	_selection_timer_label.name = "SelectionTimerLabel"
	_selection_timer_label.visible = false
	_selection_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_selection_timer_label.add_theme_font_override("font", load("res://fonts/m5x7.ttf"))
	_selection_timer_label.add_theme_font_size_override("font_size", 36)
	_selection_timer_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.2, 1.0))
	_selection_timer_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	_selection_timer_label.add_theme_constant_override("outline_size", 4)
	_selection_timer_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_selection_timer_label.offset_left = -200.0
	_selection_timer_label.offset_top = 58.0
	_selection_timer_label.offset_right = -8.0
	_selection_timer_label.offset_bottom = 94.0
	_selection_timer_label.text = "Pick a game: 15"
	add_child(_selection_timer_label)

	# ---------- Instantiate components ----------

	hand_ui = PlayerHandUIScript.new()
	hand_ui.name = "PlayerHandUI"
	add_child(hand_ui)
	hand_ui.initialize({
		"card_icon_button": card_icon_button,
		"hand_display_panel": hand_display_panel,
		"hand_container": hand_container,
		"card_count_label": card_count_label,
	})

	turn_order_bar = TurnOrderBarUIScript.new()
	turn_order_bar.name = "TurnOrderBarUI"
	add_child(turn_order_bar)
	turn_order_bar.initialize(self)

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
		"map_overlay": map_overlay,
	})
	intro_ui.intro_completed.connect(_on_intro_completed)
	intro_ui.corner_order_ready.connect(_on_corner_order_ready)

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

	flow_ui = GameFlowUIScript.new()
	flow_ui.name = "GameFlowUI"
	add_child(flow_ui)
	flow_ui.initialize({
		"play_minigames_button": play_minigames_button,
		"card_icon_button": card_icon_button,
	})

	territory_ui = TerritorySystemUIScript.new()
	territory_ui.name = "TerritorySystemUI"
	add_child(territory_ui)
	territory_ui.initialize(self, {
		"phase_overlay": phase_overlay,
		"phase_label": phase_label,
		"skip_to_battle_button": skip_to_battle_button,
		"finish_claiming_button": finish_claiming_button,
		"ready_for_battle_button": ready_for_battle_button,
		"player_roll_container": player_roll_container,
	}, claim_ui)
	territory_ui.initialize_territory_system()

	phase_ui = PhaseSystemUIScript.new()
	phase_ui.name = "PhaseSystemUI"
	add_child(phase_ui)
	phase_ui.initialize({
		"phase_overlay": phase_overlay,
		"phase_label": phase_label,
		"waiting_overlay": waiting_overlay,
		"waiting_label": waiting_label,
		"turn_banner_label": turn_banner_label,
		"minigame_button": minigame_button,
		"bridge_minigame_button": bridge_minigame_button,
		"courtly_cuisine_button": courtly_cuisine_button,
		"ice_fishing_button": ice_fishing_button,
		"play_minigames_button": play_minigames_button,
		"battle_button": battle_button,
		"skip_to_battle_button": skip_to_battle_button,
		"minigames_counter_label": minigames_counter_label,
		"finish_claiming_button": finish_claiming_button,
		"ready_for_battle_button": ready_for_battle_button,
		"settings_button": settings_button,
		"card_icon_button": card_icon_button,
		"phase_indicator_bar": phase_indicator_bar,
	}, {
		"battle_ui": battle_ui,
		"claim_ui": claim_ui,
	})

	# Single-player bot coordinator (kept as a scene child so it can process every frame)
	bot_controller = BotControllerScript.new()
	bot_controller.name = "BotController"
	add_child(bot_controller)
	App.single_player_bot_controller = bot_controller

	# ---------- Wire cross-component signals ----------

	# PhaseSystemUI → others
	phase_ui.phase_ui_applied.connect(_on_phase_ui_applied)
	phase_ui.finish_claiming_pressed.connect(territory_ui.on_finish_claiming_pressed)
	phase_ui.collect_resources_overlay_requested.connect(territory_ui.show_collect_resources_overlay)
	phase_ui.next_round_requested.connect(territory_ui.transition_to_next_round)
	phase_ui.territory_claimed_from_net.connect(_on_net_territory_claimed)
	phase_ui.enter_battle_scene.connect(_on_enter_battle_scene)
	phase_ui.minigame_selection_started.connect(start_selection_timer)

	# Refresh card count immediately when cards are placed on territories
	if claim_ui and claim_ui.has_signal("claim_submitted"):
		claim_ui.claim_submitted.connect(func(_tid, _cards):
			hand_ui.update_card_count()
			if turn_order_bar:
				turn_order_bar.update_card_count()
				turn_order_bar.update_territory_counts()
		)

	# Territory ownership changes (claim, conquest, network sync) → refresh turn order territory counts
	if TerritoryClaimManager and not TerritoryClaimManager.claim_succeeded.is_connected(_on_territory_claim_succeeded):
		TerritoryClaimManager.claim_succeeded.connect(_on_territory_claim_succeeded)

	# TerritorySystemUI → PhaseSystemUI
	territory_ui.phase_ui_update_requested.connect(phase_ui.apply_phase_ui)
	territory_ui.animate_buttons_requested.connect(phase_ui.animate_phase_buttons)

	# GameFlowUI → others
	flow_ui.phase_transition_needed.connect(phase_ui.show_phase_transition_overlay)
	flow_ui.delayed_battle_transition_needed.connect(territory_ui.start_delayed_battle_transition)
	flow_ui.collect_resources_needed.connect(territory_ui.show_collect_resources_overlay)
	flow_ui.phase_ui_refresh_needed.connect(_on_flow_phase_ui_refresh)
	flow_ui.card_won.connect(func():
		hand_ui.show_card_icon_button()
		if turn_order_bar:
			turn_order_bar.update_card_count()
			turn_order_bar.update_territory_counts()
	)
	flow_ui.show_next_player_turn.connect(_on_show_next_player_turn)

	# ---------- Button connections ----------

	minigame_button.pressed.connect(_on_minigame_button_pressed.bind(flow_ui.on_minigame_pressed))
	bridge_minigame_button.pressed.connect(_on_minigame_button_pressed.bind(flow_ui.on_bridge_minigame_pressed))
	courtly_cuisine_button.pressed.connect(_on_minigame_button_pressed.bind(flow_ui.on_courtly_cuisine_pressed))
	ice_fishing_button.pressed.connect(_on_minigame_button_pressed.bind(flow_ui.on_ice_fishing_pressed))
	play_minigames_button.pressed.connect(flow_ui.on_play_minigames_pressed)
	_minigame_buttons_ref = [minigame_button, bridge_minigame_button, courtly_cuisine_button, ice_fishing_button]
	skip_to_battle_button.pressed.connect(phase_ui.on_skip_to_battle_pressed)
	battle_button.pressed.connect(flow_ui.on_battle_button_pressed)
	if finish_claiming_button:
		finish_claiming_button.pressed.connect(territory_ui.on_finish_claiming_pressed)
	if ready_for_battle_button:
		ready_for_battle_button.pressed.connect(territory_ui.on_ready_for_battle_pressed)

	# Victory overlay — wire button if it already exists in the scene tree
	if victory_overlay:
		var victory_btn := victory_overlay.get_node_or_null("MainMenuButton") as Button
		if victory_btn:
			victory_btn.pressed.connect(_on_victory_main_menu_pressed)

	# Check if a player won while we were in another scene (e.g. battle)
	if App.game_victor_id >= 0:
		_show_victory_overlay(App.game_victor_id)
		App.game_victor_id = -1

	# Settings
	if settings_button:
		settings_button.pressed.connect(_on_settings_pressed)
	if settings_panel:
		settings_panel.resume_pressed.connect(toggle_pause)
		settings_panel.main_menu_pressed.connect(_on_main_menu_pressed)

	# Win condition: show victory when returning with game_victor_id set
	if WinConditionManager and not WinConditionManager.player_won.is_connected(_on_player_won):
		WinConditionManager.player_won.connect(_on_player_won)

	# Card count sync → turn order bar
	if not PhaseController.card_counts_updated.is_connected(_on_card_counts_updated):
		PhaseController.card_counts_updated.connect(_on_card_counts_updated)

	# Multiplayer net signals
	if App.is_multiplayer:
		phase_ui.connect_net_signals()
		if not PhaseController.turn_changed.is_connected(_on_turn_order_bar_turn_changed):
			PhaseController.turn_changed.connect(_on_turn_order_bar_turn_changed)

	# ---------- Return-from-scene check ----------

	if App.turn_order.size() > 0:
		intro_ui.skip_intro()
		intro_complete = true
		territory_ui.intro_complete = true
		phase_ui.intro_complete = true
		
		var missed_phase_transition := false
		var current_phase_as_enum: int
		
		# In multiplayer, the server may have transitioned while we were away.
		# Sync BEFORE skip_to_game_ready so returning logic uses correct phase!
		if App.is_multiplayer:
			match PhaseController.current_phase:
				0: current_phase_as_enum = App.GamePhase.CONTEST_COMMAND
				1: current_phase_as_enum = App.GamePhase.CONTEST_CLAIM
				2: current_phase_as_enum = App.GamePhase.COLLECT
				_: current_phase_as_enum = App.GamePhase.CONTEST_COMMAND
				
			if current_phase_as_enum != App.current_game_phase:
				missed_phase_transition = true
				
			PhaseController.sync_app_game_phase()
			
		var map_sub_phase: int = flow_ui.skip_to_game_ready()
		
		if App.is_multiplayer:
			map_sub_phase = PhaseController.map_sub_phase
			
		phase_ui.map_sub_phase = map_sub_phase
		territory_ui.map_sub_phase = map_sub_phase
		
		# Refresh territory indicators to pick up card count changes after battles
		territory_ui.refresh_territory_claimed_visuals()
		
		# Refresh card counts in the turn order bar (collection may have changed in minigame/battle)
		App._notify_card_count_changed()
		if bot_controller and bot_controller.has_method("initialize_single_player_bots"):
			bot_controller.initialize_single_player_bots()
		
		# Show overlay if we missed the phase transition while in battle
		if missed_phase_transition:
			App.show_phase_transition = true
			phase_ui.show_phase_transition_overlay()
			
		return

	showcase_container.visible = false
	gnome_ui = GnomeTutorialUIScript.new()
	gnome_ui.name = "GnomeTutorialUI"
	add_child(gnome_ui)
	gnome_ui.initialize({
		"map_overlay": map_overlay,
		"showcase_container": showcase_container,
		"territory_manager": territory_ui.territory_manager,
		"card_icon_button": card_icon_button,
		"hand_display_panel": hand_display_panel,
		"hand_container": hand_container,
	})
	gnome_ui.gnome_sequence_completed.connect(_on_gnome_done)
	gnome_ui.start_sequence()


func _on_gnome_done() -> void:
	if gnome_ui:
		gnome_ui.queue_free()
		gnome_ui = null
	if _showcase_container:
		_showcase_container.visible = true
		_showcase_container.modulate.a = 1.0
	intro_ui.start_intro()


func _process(delta: float) -> void:
	if gnome_ui:
		gnome_ui.process_frame(delta)
	elif intro_ui and not intro_complete:
		intro_ui.process_frame(delta)
	if bot_controller and bot_controller.has_method("process_single_player_frame"):
		bot_controller.process_single_player_frame(delta)
	# Minigame selection countdown
	if _selection_timer_active:
		_selection_timer -= delta
		var secs := int(ceil(_selection_timer))
		if _selection_timer_label:
			_selection_timer_label.text = "Pick a game: %d" % secs
			if _selection_timer <= 10.0:
				_selection_timer_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.2, 1.0))
			else:
				_selection_timer_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.2, 1.0))
		if _selection_timer <= 0.0:
			_on_selection_timeout()


# ---------- INTRO COMPLETION ----------

func _on_intro_completed() -> void:
	intro_complete = true
	territory_ui.intro_complete = true
	phase_ui.intro_complete = true

	if App.is_multiplayer and multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		if PhaseController.current_phase == 0 and PhaseController.player_done_state.is_empty():
			# First game load — host initializes the Card Command phase
			PhaseSync.host_init_contest_command_phase()
			App.phase_transition_text = "Contest"
		else:
			# Returning from minigame/battle — phase already set by server RPCs
			PhaseController.sync_app_game_phase()
			phase_ui.map_sub_phase = PhaseController.map_sub_phase
			territory_ui.map_sub_phase = PhaseController.map_sub_phase
	elif App.is_multiplayer and multiplayer.has_multiplayer_peer():
		PhaseController.sync_app_game_phase()
		phase_ui.map_sub_phase = PhaseController.map_sub_phase
		territory_ui.map_sub_phase = PhaseController.map_sub_phase
	else:
		App.enter_contest_command_phase()
		phase_ui.map_sub_phase = PhaseController.MapSubPhase.CLAIMING
		territory_ui.map_sub_phase = PhaseController.MapSubPhase.CLAIMING
		App.phase_transition_text = "Contest"

	# Refresh territory indicators to pick up card count changes after battles
	territory_ui.refresh_territory_claimed_visuals()

	App.show_phase_transition = true
	phase_ui.show_phase_transition_overlay()
	if bot_controller and bot_controller.has_method("initialize_single_player_bots"):
		bot_controller.initialize_single_player_bots()


# ---------- CROSS-COMPONENT SIGNAL HANDLERS ----------

func _on_phase_ui_applied() -> void:
	territory_ui.update_territory_interaction()
	hand_ui.update_card_count()
	if turn_order_bar:
		turn_order_bar.update_card_count()
		turn_order_bar.update_territory_counts()
		_sync_turn_order_bar_highlight()
	# Stop the selection timer if we've left the collect phase
	var in_collect_phase := (
		App.current_game_phase == App.GamePhase.COLLECT
		or (App.current_game_phase == App.GamePhase.CONTEST_CLAIM
			and PhaseController.map_sub_phase == PhaseController.MapSubPhase.RESOURCE_COLLECTION)
	)
	if not in_collect_phase:
		stop_selection_timer()

func _on_net_territory_claimed(territory_id: int, owner_id: int, cards: Array) -> void:
	# TerritoryClaimManager applies via TerritorySync.territory_claimed; we just refresh visuals.
	territory_ui.refresh_territory_claimed_visuals()
	if turn_order_bar:
		turn_order_bar.update_territory_counts()


func _on_territory_claim_succeeded(_territory_id: int, _owner_id: int, _cards: Array) -> void:
	# Any successful claim (initial claim, conquest, network sync) — refresh territory counts.
	if turn_order_bar:
		turn_order_bar.update_territory_counts()

func _on_enter_battle_scene(scene_path: String) -> void:
	App.go(scene_path)

func _on_flow_phase_ui_refresh(map_sub_phase: int) -> void:
	# In multiplayer, use the authoritative server state — the pending_return value
	# from skip_to_game_ready() can be stale if the server already transitioned.
	var resolved: int = PhaseController.map_sub_phase if App.is_multiplayer else map_sub_phase
	phase_ui.map_sub_phase = resolved
	territory_ui.map_sub_phase = resolved
	phase_ui.apply_phase_ui()
	phase_ui.animate_phase_buttons()

func _on_show_next_player_turn(player_name: String) -> void:
	phase_ui.map_sub_phase = PhaseController.MapSubPhase.CLAIMING
	territory_ui.map_sub_phase = PhaseController.MapSubPhase.CLAIMING
	App.phase_transition_text = "Claim: " + player_name
	phase_ui.apply_phase_ui()
	phase_ui.show_phase_transition_overlay()


# ---------- SETTINGS / PAUSE ----------

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

func _on_player_won(player_id: int) -> void:
	if is_inside_tree():
		_show_victory_overlay(player_id)

func _show_victory_overlay(player_id: int) -> void:
	var victory_overlay := get_node_or_null("VictoryOverlay") as ColorRect
	if not victory_overlay:
		# Create overlay in code (editor cache may not have the .tscn node)
		victory_overlay = ColorRect.new()
		victory_overlay.name = "VictoryOverlay"
		victory_overlay.color = Color(0, 0, 0, 0.75)
		victory_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
		victory_overlay.z_index = 50
		add_child(victory_overlay)
		var label := Label.new()
		label.name = "VictoryLabel"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.set_anchors_preset(Control.PRESET_FULL_RECT)
		label.add_theme_font_size_override("font_size", 48)
		victory_overlay.add_child(label)
		var btn := Button.new()
		btn.name = "MainMenuButton"
		btn.text = "Main Menu"
		btn.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		btn.position = Vector2(-60, -80)
		btn.size = Vector2(120, 40)
		btn.pressed.connect(_on_victory_main_menu_pressed)
		victory_overlay.add_child(btn)
	var victory_label := victory_overlay.get_node_or_null("VictoryLabel") as Label
	var player_name: String = "Player"
	for p in App.game_players:
		if int(p.get("id", -1)) == player_id:
			player_name = str(p.get("name", "Player"))
			break
	if victory_label:
		victory_label.text = "%s Wins!" % player_name
	victory_overlay.visible = true
	App.game_victor_id = -1

func _on_victory_main_menu_pressed() -> void:
	get_tree().paused = false
	App.go("res://scenes/ui/MainMenu.tscn")


# ---------- MINIGAME SELECTION TIMER ----------

func start_selection_timer() -> void:
	# Only start in collect phases (not Contest)
	var in_collect_phase := (
		App.current_game_phase == App.GamePhase.COLLECT
		or (App.current_game_phase == App.GamePhase.CONTEST_CLAIM
			and PhaseController.map_sub_phase == PhaseController.MapSubPhase.RESOURCE_COLLECTION)
	)
	if not in_collect_phase:
		stop_selection_timer()
		return
	# Don't restart if already running (prevents flicker resets)
	if _selection_timer_active:
		return
	# Don't start if player has no more minigames (check count directly, not can_play_minigame which only works in COLLECT)
	var minigame_count: int = App.minigames_completed_this_phase
	if App.is_multiplayer and multiplayer.has_multiplayer_peer():
		var server_count: int = PhaseController.player_minigame_counts.get(multiplayer.get_unique_id(), 0)
		minigame_count = maxi(minigame_count, server_count)
	if minigame_count >= App.MAX_MINIGAMES_PER_PHASE:
		return
	_selection_timer = SELECTION_TIME_LIMIT
	_selection_timer_active = true
	if _selection_timer_label:
		_selection_timer_label.visible = true
		_selection_timer_label.text = "Pick a game: %d" % int(SELECTION_TIME_LIMIT)
		_selection_timer_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.2, 1.0))




func stop_selection_timer() -> void:
	_selection_timer_active = false
	if _selection_timer_label:
		_selection_timer_label.visible = false

func _on_minigame_button_pressed(callback: Callable) -> void:
	stop_selection_timer()
	callback.call()

func _on_selection_timeout() -> void:
	stop_selection_timer()
	# Forfeit this minigame chance — player took too long
	print("[GameIntro] Selection timed out — forfeiting this minigame chance")
	App.minigame_time_remaining = -1.0
	App.pending_minigame_reward.clear()
	App.pending_bonus_reward.clear()
	App.region_bonus_active = false
	App.on_minigame_completed()
	# Only refresh UI if the player can still play another game in the collect phase
	var minigame_count: int = App.minigames_completed_this_phase
	if App.is_multiplayer and multiplayer.has_multiplayer_peer():
		var server_count: int = PhaseController.player_minigame_counts.get(multiplayer.get_unique_id(), 0)
		minigame_count = maxi(minigame_count, server_count)
	if minigame_count < App.MAX_MINIGAMES_PER_PHASE and phase_ui:
		# Reset the timer guard so a fresh timer can start for the 2nd pick
		_selection_timer_active = false
		phase_ui.apply_phase_ui()
		phase_ui.animate_phase_buttons()

# ---------- HELPERS ----------

func _get_local_player_id() -> Variant:
	for p in App.game_players:
		if p.get("is_local", false):
			return p.get("id", 1)
	return 1

func _on_corner_order_ready() -> void:
	if turn_order_bar:
		turn_order_bar.build_turn_order(App.turn_order)
		_sync_turn_order_bar_highlight()

func _on_card_counts_updated() -> void:
	if turn_order_bar:
		turn_order_bar.update_card_count()
		turn_order_bar.update_territory_counts()

func _on_turn_order_bar_turn_changed(peer_id: int) -> void:
	if not turn_order_bar:
		return
	if _is_collect_phase():
		turn_order_bar.clear_highlight()
	elif peer_id >= 0:
		turn_order_bar.highlight_current_turn(peer_id)

func _sync_turn_order_bar_highlight() -> void:
	if not turn_order_bar:
		return
	if _is_collect_phase():
		turn_order_bar.clear_highlight()
		return
	var active_id: int = -1
	if App.is_multiplayer and multiplayer.has_multiplayer_peer():
		active_id = PhaseController.current_turn_peer_id
	else:
		if App.current_turn_index >= 0 and App.current_turn_index < App.turn_order.size():
			active_id = int(App.turn_order[App.current_turn_index].get("id", -1))
	if active_id >= 0:
		turn_order_bar.highlight_current_turn(active_id)

func _is_collect_phase() -> bool:
	return (
		App.current_game_phase == App.GamePhase.COLLECT
		or (App.current_game_phase == App.GamePhase.CONTEST_CLAIM
			and PhaseController.map_sub_phase == PhaseController.MapSubPhase.RESOURCE_COLLECTION)
	)

func _create_phase_indicator_bar() -> HBoxContainer:
	var font: Font = load("res://fonts/m5x7.ttf")
	var bar := HBoxContainer.new()
	bar.name = "PhaseIndicatorBar"
	bar.visible = false
	bar.anchor_left = 0.5
	bar.anchor_right = 0.5
	bar.offset_left = -250.0
	bar.offset_top = 8.0
	bar.offset_right = 250.0
	bar.offset_bottom = 52.0
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", 32)
	var names: Array[String] = ["Contest", "Collect"]
	for i in names.size():
		var panel := PanelContainer.new()
		panel.name = names[i] + "PhasePanel"
		# Default style: transparent background, no border
		var style_inactive := StyleBoxFlat.new()
		style_inactive.bg_color = Color(0, 0, 0, 0)
		style_inactive.border_width_left = 0
		style_inactive.border_width_top = 0
		style_inactive.border_width_right = 0
		style_inactive.border_width_bottom = 0
		panel.add_theme_stylebox_override("panel", style_inactive)
		var label := Label.new()
		label.text = names[i]
		label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
		label.add_theme_constant_override("outline_size", 5)
		label.add_theme_font_override("font", font)
		label.add_theme_font_size_override("font_size", 36)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		panel.add_child(label)
		bar.add_child(panel)
	return bar

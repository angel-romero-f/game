extends Control

## GameIntro — Thin orchestrator: resolves scene nodes, wires 8 UI components, routes cross-component signals.

# Component scripts
const IntroSequenceUIScript := preload("res://scripts/ui/game_intro/IntroSequenceUI.gd")
const BattleSelectionUIScript := preload("res://scripts/ui/game_intro/BattleSelectionUI.gd")
const PhaseSystemUIScript := preload("res://scripts/ui/game_intro/PhaseSystemUI.gd")
const TerritorySystemUIScript := preload("res://scripts/ui/game_intro/TerritorySystemUI.gd")
const PlayerHandUIScript := preload("res://scripts/ui/game_intro/PlayerHandUI.gd")
const GameFlowUIScript := preload("res://scripts/ui/game_intro/GameFlowUI.gd")

# Component instances
var intro_ui: Node
var battle_ui: Node
var phase_ui: Node
var territory_ui: Node
var hand_ui: Node
var flow_ui: Node
var claim_ui: PanelContainer  # Script-on-node (ClaimTerritoryUI)
var settings_panel: Panel      # Script-on-node (SettingsPanelUI)

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
	var order_corner_container := $OrderCornerContainer/VBoxContainer as VBoxContainer
	var minigame_button := $MinigameButton as Button
	var bridge_minigame_button := $BridgeMinigameButton as Button
	var ice_fishing_button := $IceFishingButton as Button
	var play_minigames_button := $PlayMinigamesButton as Button
	var battle_button := $BattleButton as Button
	var skip_to_battle_button := $SkipToBattleButton as Button
	settings_button = $SettingsButton as Button
	var current_phase_label := $CurrentPhaseLabel as Label
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
	order_corner_container.get_parent().visible = false
	for btn in [minigame_button, bridge_minigame_button, ice_fishing_button, play_minigames_button,
				battle_button, skip_to_battle_button, battle_button_right]:
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
		"ice_fishing_button": ice_fishing_button,
		"play_minigames_button": play_minigames_button,
		"battle_button": battle_button,
		"skip_to_battle_button": skip_to_battle_button,
		"minigames_counter_label": minigames_counter_label,
		"finish_claiming_button": finish_claiming_button,
		"ready_for_battle_button": ready_for_battle_button,
		"settings_button": settings_button,
		"card_icon_button": card_icon_button,
		"current_phase_label": current_phase_label,
	}, {
		"battle_ui": battle_ui,
		"claim_ui": claim_ui,
	})

	# ---------- Wire cross-component signals ----------

	# PhaseSystemUI → others
	phase_ui.phase_ui_applied.connect(_on_phase_ui_applied)
	phase_ui.finish_claiming_pressed.connect(territory_ui.on_finish_claiming_pressed)
	phase_ui.collect_resources_overlay_requested.connect(territory_ui.show_collect_resources_overlay)
	phase_ui.next_round_requested.connect(territory_ui.transition_to_next_round)
	phase_ui.territory_claimed_from_net.connect(_on_net_territory_claimed)
	phase_ui.enter_battle_scene.connect(_on_enter_battle_scene)
	phase_ui.minigame_selection_started.connect(start_selection_timer)

	# TerritorySystemUI → PhaseSystemUI
	territory_ui.phase_ui_update_requested.connect(phase_ui.apply_phase_ui)
	territory_ui.animate_buttons_requested.connect(phase_ui.animate_phase_buttons)

	# GameFlowUI → others
	flow_ui.phase_transition_needed.connect(phase_ui.show_phase_transition_overlay)
	flow_ui.delayed_battle_transition_needed.connect(territory_ui.start_delayed_battle_transition)
	flow_ui.collect_resources_needed.connect(territory_ui.show_collect_resources_overlay)
	flow_ui.phase_ui_refresh_needed.connect(_on_flow_phase_ui_refresh)
	flow_ui.card_won.connect(hand_ui.show_card_icon_button)
	flow_ui.show_next_player_turn.connect(_on_show_next_player_turn)

	# ---------- Button connections ----------

	minigame_button.pressed.connect(_on_minigame_button_pressed.bind(flow_ui.on_minigame_pressed))
	bridge_minigame_button.pressed.connect(_on_minigame_button_pressed.bind(flow_ui.on_bridge_minigame_pressed))
	ice_fishing_button.pressed.connect(_on_minigame_button_pressed.bind(flow_ui.on_ice_fishing_pressed))
	play_minigames_button.pressed.connect(flow_ui.on_play_minigames_pressed)
	_minigame_buttons_ref = [minigame_button, bridge_minigame_button, ice_fishing_button]
	skip_to_battle_button.pressed.connect(phase_ui.on_skip_to_battle_pressed)
	battle_button.pressed.connect(flow_ui.on_battle_button_pressed)
	if finish_claiming_button:
		finish_claiming_button.pressed.connect(territory_ui.on_finish_claiming_pressed)
	if ready_for_battle_button:
		ready_for_battle_button.pressed.connect(territory_ui.on_ready_for_battle_pressed)

	# Victory overlay
	if victory_overlay:
		var victory_btn := victory_overlay.get_node_or_null("MainMenuButton") as Button
		if victory_btn:
			victory_btn.pressed.connect(_on_victory_main_menu_pressed)
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

	# Multiplayer net signals
	if App.is_multiplayer:
		phase_ui.connect_net_signals()

	# ---------- Return-from-scene check ----------

	if App.turn_order.size() > 0:
		intro_ui.skip_intro()
		intro_complete = true
		territory_ui.intro_complete = true
		phase_ui.intro_complete = true
		var map_sub_phase: int = flow_ui.skip_to_game_ready()
		# In multiplayer, the server may have already transitioned (e.g. RESOURCE_COLLECTION → CLAIMING)
		# while we were in a minigame scene. Use the authoritative PhaseController state.
		if App.is_multiplayer:
			map_sub_phase = PhaseController.map_sub_phase
		phase_ui.map_sub_phase = map_sub_phase
		territory_ui.map_sub_phase = map_sub_phase
		return

	intro_ui.start_intro()


func _process(delta: float) -> void:
	if intro_ui and not intro_complete:
		intro_ui.process_frame(delta)
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
			PhaseSync.host_init_card_command_phase()
			App.phase_transition_text = "Command & Contest"
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
		App.enter_claim_conquer_phase()
		phase_ui.map_sub_phase = PhaseController.MapSubPhase.CLAIMING
		territory_ui.map_sub_phase = PhaseController.MapSubPhase.CLAIMING
		App.phase_transition_text = "Collect"

	App.show_phase_transition = true
	phase_ui.show_phase_transition_overlay()


# ---------- CROSS-COMPONENT SIGNAL HANDLERS ----------

func _on_phase_ui_applied() -> void:
	territory_ui.update_territory_interaction()
	hand_ui.update_card_count()
	# Stop the selection timer if we've left the collect phase
	var in_collect_phase := (
		App.current_game_phase == App.GamePhase.CARD_COLLECTION
		or (App.current_game_phase == App.GamePhase.CLAIM_CONQUER
			and PhaseController.map_sub_phase == PhaseController.MapSubPhase.RESOURCE_COLLECTION)
	)
	if not in_collect_phase:
		stop_selection_timer()

func _on_net_territory_claimed(territory_id: int, owner_id: int, cards: Array) -> void:
	# TerritoryClaimManager applies via TerritorySync.territory_claimed; we just refresh visuals.
	territory_ui.refresh_territory_claimed_visuals()

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
		return
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
	# Only start in collect phases (not Command & Contest)
	var in_collect_phase := (
		App.current_game_phase == App.GamePhase.CARD_COLLECTION
		or (App.current_game_phase == App.GamePhase.CLAIM_CONQUER
			and PhaseController.map_sub_phase == PhaseController.MapSubPhase.RESOURCE_COLLECTION)
	)
	if not in_collect_phase:
		stop_selection_timer()
		return
	# Don't restart if already running (prevents flicker resets)
	if _selection_timer_active:
		return
	# Don't start if player has no more minigames (check count directly, not can_play_minigame which only works in CARD_COLLECTION)
	var minigame_count: int = App.minigames_completed_this_phase
	if App.is_multiplayer and multiplayer.has_multiplayer_peer():
		minigame_count = PhaseController.player_minigame_counts.get(multiplayer.get_unique_id(), 0)
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
	App.on_minigame_completed()
	# Only refresh UI if the player can still play another game in the collect phase
	var minigame_count: int = App.minigames_completed_this_phase
	if App.is_multiplayer and multiplayer.has_multiplayer_peer():
		minigame_count = PhaseController.player_minigame_counts.get(multiplayer.get_unique_id(), 0)
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

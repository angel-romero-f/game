extends Node

## TerritorySystemUI — Territory initialization, interaction gating, and claim/attack routing.
## Programmatic component: created with .new(), receives node refs via initialize().

signal phase_ui_update_requested
signal animate_buttons_requested

const TerritoryMapConfigScript := preload("res://scripts/TerritoryMapConfig.gd")
const TerritoryIndicatorManagerScript := preload("res://scripts/TerritoryIndicatorManager.gd")
const DELAY_BEFORE_BATTLE_TRANSITION_SEC := 1.0

var territory_manager: TerritoryManager = null
var territories_container: Control = null
var _territory_indicator_manager: Node = null
var _territory_claim_state: Node = null
var _is_delayed_battle_transition_active := false
var intro_complete: bool = false

# Node references
var phase_overlay: ColorRect
var phase_label: Label
var skip_to_battle_button: Button
var finish_claiming_button: Button
var ready_for_battle_button: Button
var player_roll_container: CenterContainer

# Component references
var claim_ui: PanelContainer  # ClaimTerritoryUI
var parent_control: Control  # GameIntro (for tween creation and child placement)

var map_sub_phase: int = PhaseController.MapSubPhase.CLAIMING

func initialize(p_parent: Control, nodes: Dictionary, p_claim_ui: PanelContainer) -> void:
	parent_control = p_parent
	claim_ui = p_claim_ui
	phase_overlay = nodes.get("phase_overlay")
	phase_label = nodes.get("phase_label")
	skip_to_battle_button = nodes.get("skip_to_battle_button")
	finish_claiming_button = nodes.get("finish_claiming_button")
	ready_for_battle_button = nodes.get("ready_for_battle_button")
	player_roll_container = nodes.get("player_roll_container")
	_territory_claim_state = parent_control.get_node_or_null("/root/" + "Territory" + "Claim" + "State")

func initialize_territory_system() -> void:
	## Creates TerritoryManager and container, registers territories.
	territory_manager = parent_control.get_node_or_null("TerritoryManager") as TerritoryManager
	if not territory_manager:
		territory_manager = TerritoryManager.new()
		territory_manager.name = "TerritoryManager"
		parent_control.add_child(territory_manager)

	territories_container = parent_control.get_node_or_null("TerritoriesContainer") as Control
	if not territories_container:
		territories_container = Control.new()
		territories_container.name = "TerritoriesContainer"
		territories_container.set_anchors_preset(Control.PRESET_FULL_RECT)
		territories_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var map_overlay_node: ColorRect = parent_control.get_node_or_null("MapOverlay")
		var map_overlay_index := parent_control.get_child_count()
		for i in range(parent_control.get_child_count()):
			if parent_control.get_child(i) == map_overlay_node:
				map_overlay_index = i
				break
		parent_control.add_child(territories_container)
		parent_control.move_child(territories_container, map_overlay_index)

	if not territory_manager.territory_selected.is_connected(_on_territory_selected):
		territory_manager.territory_selected.connect(_on_territory_selected)
	if not territory_manager.card_placed.is_connected(_on_card_placed):
		territory_manager.card_placed.connect(_on_card_placed)

	_initialize_territories()

	# Create territory indicators (one per territory, under the territory nodes, same id)
	_setup_territory_indicators()

	# Connect autoload signals
	if not PhaseController.claiming_turn_finished.is_connected(_on_claiming_turn_finished):
		PhaseController.claiming_turn_finished.connect(_on_claiming_turn_finished)
	if not PhaseController.map_sub_phase_changed.is_connected(_on_map_sub_phase_changed):
		PhaseController.map_sub_phase_changed.connect(_on_map_sub_phase_changed)
	if not TerritoryClaimManager.claim_failed.is_connected(_on_claim_failed):
		TerritoryClaimManager.claim_failed.connect(_on_claim_failed)

	# Connect claim_ui signals
	if claim_ui:
		claim_ui.initialize(territory_manager, _territory_claim_state)
		claim_ui.claim_submitted.connect(_on_claim_submitted)
		claim_ui.attack_submitted.connect(_on_attack_submitted)
		claim_ui.minigame_requested.connect(_on_claim_minigame_requested)

	if territory_manager and not territory_manager.defending_cards_preview_requested.is_connected(_on_defending_preview_requested):
		territory_manager.defending_cards_preview_requested.connect(_on_defending_preview_requested)

func get_territory_manager() -> TerritoryManager:
	return territory_manager

func get_territory_indicator_manager() -> Node:
	return _territory_indicator_manager


func _on_defending_preview_requested(territory_id: int) -> void:
	if claim_ui and claim_ui.has_method("show_defending_preview"):
		claim_ui.show_defending_preview(territory_id)


func _setup_territory_indicators() -> void:
	if not territory_manager or territory_manager.territories.is_empty():
		return
	var manager := TerritoryIndicatorManagerScript.new()
	manager.name = "TerritoryIndicatorManager"
	parent_control.add_child(manager)
	manager.initialize(territory_manager)
	_territory_indicator_manager = manager

# ---------- TERRITORY INITIALIZATION ----------

func _initialize_territories() -> void:
	if territories_container and territories_container.get_child_count() > 0:
		var has_territory_nodes := false
		for child in territories_container.get_children():
			if child is TerritoryNode:
				has_territory_nodes = true
				break
		if has_territory_nodes:
			territory_manager.initialize_from_editor_nodes(territories_container)
			apply_saved_territory_claims()
			refresh_territory_claimed_visuals()
			return

	var map_config_path := "res://scripts/TerritoryMapConfig.tres"
	if ResourceLoader.exists(map_config_path):
		var config = load(map_config_path)
		if config and config.has_method("get_territory_configs"):
			territory_manager.initialize_territories(config.get_territory_configs(), territories_container)
			apply_saved_territory_claims()
			refresh_territory_claimed_visuals()
			return

	if TerritoryMapConfigScript:
		var default_config = TerritoryMapConfigScript.create_default_config()
		if default_config and default_config.has_method("get_territory_configs"):
			territory_manager.initialize_territories(default_config.get_territory_configs(), territories_container)
			apply_saved_territory_claims()
			refresh_territory_claimed_visuals()
			return

	# Fallback
	push_warning("[TerritorySystemUI] Could not load TerritoryMapConfig, creating basic territories")
	var basic_configs: Array[Dictionary] = []
	for i in range(31):
		var default_size := Vector2(150, 120)
		var default_polygon := PackedVector2Array([
			Vector2(0, 0), Vector2(default_size.x, 0),
			Vector2(default_size.x, default_size.y), Vector2(0, default_size.y)
		])
		basic_configs.append({
			"territory_id": i + 1, "region_id": 1,
			"position": Vector2(400.0 + float(i % 6) * 150.0, 300.0 + float(i) / 6.0 * 120.0),
			"size": default_size, "polygon_points": default_polygon, "adjacent_territory_ids": []
		})
	territory_manager.initialize_territories(basic_configs, territories_container)
	apply_saved_territory_claims()
	refresh_territory_claimed_visuals()

# ---------- INTERACTION GATING ----------

func are_territories_interactable() -> bool:
	if not intro_complete:
		return false
	if phase_overlay and phase_overlay.visible:
		return false
	if _is_delayed_battle_transition_active:
		return false
	if player_roll_container and player_roll_container.visible:
		return false
	return true

func update_territory_interaction() -> void:
	if not territory_manager:
		return
	var interactable := are_territories_interactable()
	for tid_key in territory_manager.territories:
		var indicator: TerritoryIndicator = territory_manager.territories[tid_key]
		indicator.mouse_filter = Control.MOUSE_FILTER_STOP if interactable else Control.MOUSE_FILTER_IGNORE

# ---------- TERRITORY EVENTS ----------

func _on_territory_selected(territory_id: int) -> void:
	if not are_territories_interactable() or not claim_ui:
		return
	var is_claimed: bool = _territory_claim_state != null and _territory_claim_state.call("is_claimed", territory_id)
	var owner_id: Variant = _territory_claim_state.call("get_owner_id", territory_id) if _territory_claim_state else null
	var local_id: Variant = _get_local_player_id()
	# If this territory is already owned by the local player and we're not in resource collection,
	# open the defending-cards preview immediately instead of the full claim panel.
	if map_sub_phase != PhaseController.MapSubPhase.RESOURCE_COLLECTION and is_claimed and owner_id == local_id:
		if claim_ui.has_method("show_defending_preview"):
			claim_ui.show_defending_preview(territory_id)
		return
	if map_sub_phase == PhaseController.MapSubPhase.RESOURCE_COLLECTION:
		if App.minigames_completed_this_phase >= App.MAX_MINIGAMES_PER_PHASE:
			claim_ui.show_unclaimed_territory_message()
			return
		if not is_claimed or owner_id != local_id:
			claim_ui.show_unclaimed_territory_message()
			return
		claim_ui.open_play_only_panel(territory_id)
	else:
		claim_ui.open_claim_panel(territory_id, map_sub_phase, App.current_game_phase)

func _on_card_placed(territory_id: int, player_id: int) -> void:
	print("[TerritorySystemUI] Card placed on territory %d by player %d" % [territory_id, player_id])

func _on_claim_submitted(territory_id: int, cards: Array) -> void:
	var local_id: Variant = _get_local_player_id()
	if local_id == null:
		if claim_ui:
			claim_ui.close_panel()
		return
	var success := TerritoryClaimManager.claim_territory(territory_id, local_id, cards, territory_manager)
	if success:
		refresh_territory_claimed_visuals()
		if claim_ui:
			claim_ui.close_panel()

func _on_attack_submitted(territory_id: int, cards: Array) -> void:
	## Attack only registers attacking cards; it does NOT start or resolve a battle. The battle runs in the card_battle scene after both players press Ready.
	TerritoryClaimManager.register_attack(territory_id, cards)
	if claim_ui:
		claim_ui.close_panel()
	update_territory_interaction()

func _on_claim_minigame_requested(territory_id: int, region_id: int) -> void:
	TerritoryClaimManager.launch_territory_minigame(territory_id, region_id)

func _on_claim_failed(_territory_id: int, reason: String) -> void:
	if reason != "invalid_territory" and claim_ui:
		claim_ui.show_already_claimed_message(reason)

# ---------- PHASE TRANSITIONS (TERRITORY-SIDE) ----------

func _on_map_sub_phase_changed(sub_phase: int) -> void:
	map_sub_phase = sub_phase
	# After last battle we enter resource collection; refresh indicators so card counts are correct
	if sub_phase == PhaseController.MapSubPhase.RESOURCE_COLLECTION:
		refresh_territory_claimed_visuals()

func on_finish_claiming_pressed() -> void:
	if claim_ui:
		claim_ui.close_panel()
	PhaseController.finish_claiming_turn()

func _on_claiming_turn_finished(has_battles: bool) -> void:
	if has_battles:
		return
	if not App.is_multiplayer or not multiplayer.has_multiplayer_peer():
		show_collect_resources_overlay()
	else:
		skip_to_battle_button.visible = false

func show_collect_resources_overlay() -> void:
	skip_to_battle_button.visible = false
	if finish_claiming_button:
		finish_claiming_button.visible = false
	if not phase_overlay or not phase_label:
		_enter_resource_collection()
		return
	phase_label.text = "Collect"
	phase_overlay.visible = true
	phase_overlay.modulate.a = 0.0
	update_territory_interaction()
	var tween := create_tween()
	tween.tween_property(phase_overlay, "modulate:a", 1.0, 0.4)
	tween.tween_interval(1.5)
	tween.tween_property(phase_overlay, "modulate:a", 0.0, 0.4)
	tween.tween_callback(_on_collect_resources_overlay_finished)

func _on_collect_resources_overlay_finished() -> void:
	phase_overlay.visible = false
	update_territory_interaction()
	_enter_resource_collection()

func _enter_resource_collection() -> void:
	PhaseController.enter_resource_collection()
	map_sub_phase = PhaseController.map_sub_phase
	phase_ui_update_requested.emit()
	animate_buttons_requested.emit()

func on_ready_for_battle_pressed() -> void:
	transition_to_next_round()

func transition_to_next_round() -> void:
	PhaseController.enter_next_claiming_round()
	map_sub_phase = PhaseController.map_sub_phase
	phase_ui_update_requested.emit()
	animate_buttons_requested.emit()

	if phase_overlay and phase_label:
		phase_label.text = "Next Round: Claim Territories"
		phase_overlay.visible = true
		phase_overlay.modulate.a = 0.0
		update_territory_interaction()
		var tween := create_tween()
		tween.tween_property(phase_overlay, "modulate:a", 1.0, 0.4)
		tween.tween_interval(1.5)
		tween.tween_property(phase_overlay, "modulate:a", 0.0, 0.4)
		tween.tween_callback(func():
			phase_overlay.visible = false
			update_territory_interaction()
		)

func start_delayed_battle_transition() -> void:
	_is_delayed_battle_transition_active = true
	update_territory_interaction()
	await get_tree().create_timer(DELAY_BEFORE_BATTLE_TRANSITION_SEC).timeout
	_is_delayed_battle_transition_active = false
	transition_to_next_round()

# ---------- TERRITORY VISUALS ----------

func apply_saved_territory_claims() -> void:
	TerritoryClaimManager.apply_saved_claims(territory_manager)
	refresh_territory_claimed_visuals()

func refresh_territory_claimed_visuals() -> void:
	if not territory_manager:
		return
	for tid_key in territory_manager.territories:
		var indicator: TerritoryIndicator = territory_manager.territories[tid_key]
		indicator.update_claimed_visual()
	if _territory_indicator_manager and _territory_indicator_manager.has_method("refresh_all_indicator_textures"):
		_territory_indicator_manager.refresh_all_indicator_textures()

# ---------- HELPERS ----------

func _get_local_player_id() -> Variant:
	for p in App.game_players:
		if p.get("is_local", false):
			return p.get("id", 1)
	return 1

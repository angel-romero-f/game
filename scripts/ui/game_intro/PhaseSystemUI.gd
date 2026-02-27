extends Node

## PhaseSystemUI — Phase-aware button visibility, overlay management, and multiplayer sync handlers.
## Merges phase UI + multiplayer sync because every sync handler terminates by calling apply_phase_ui/set_overlay.

signal phase_ui_applied
signal phase_transition_finished
signal finish_claiming_pressed
signal collect_resources_overlay_requested
signal next_round_requested
signal territory_claimed_from_net(territory_id: int, owner_id: int, cards: Array)
signal enter_battle_scene(territory_id: String)
signal minigame_selection_started

enum OverlayState { NONE, PHASE_TRANSITION, WAITING, D20_ROLLING }
var _overlay_state: OverlayState = OverlayState.NONE
var _pending_phase_overlay: bool = false  # True when a phase RPC arrived before intro_complete
var is_phase_overlay_animating: bool = false
var is_waiting_for_others: bool = false
var local_done_count: int = 0
var local_total_count: int = 0
var map_sub_phase: int = PhaseController.MapSubPhase.CLAIMING
var intro_complete: bool = false

# Node references
var phase_overlay: ColorRect
var phase_label: Label
var waiting_overlay: ColorRect
var waiting_label: Label
var turn_banner_label: Label  # Non-modal "(Name)'s Turn" text
var minigame_button: Button
var bridge_minigame_button: Button
var ice_fishing_button: Button
var play_minigames_button: Button
var battle_button: Button
var skip_to_battle_button: Button
var minigames_counter_label: Label
var finish_claiming_button: Button
var ready_for_battle_button: Button
var settings_button: Button
var card_icon_button: Button
var current_phase_label: Label
var phase_indicator_bar: HBoxContainer

# Component references
var battle_ui: Node  # BattleSelectionUI
var claim_ui: PanelContainer  # ClaimTerritoryUI

func initialize(nodes: Dictionary, refs: Dictionary) -> void:
	phase_overlay = nodes.get("phase_overlay")
	phase_label = nodes.get("phase_label")
	waiting_overlay = nodes.get("waiting_overlay")
	waiting_label = nodes.get("waiting_label")
	turn_banner_label = nodes.get("turn_banner_label")
	minigame_button = nodes.get("minigame_button")
	bridge_minigame_button = nodes.get("bridge_minigame_button")
	ice_fishing_button = nodes.get("ice_fishing_button")
	play_minigames_button = nodes.get("play_minigames_button")
	battle_button = nodes.get("battle_button")
	skip_to_battle_button = nodes.get("skip_to_battle_button")
	minigames_counter_label = nodes.get("minigames_counter_label")
	finish_claiming_button = nodes.get("finish_claiming_button")
	ready_for_battle_button = nodes.get("ready_for_battle_button")
	settings_button = nodes.get("settings_button")
	card_icon_button = nodes.get("card_icon_button")
	current_phase_label = nodes.get("current_phase_label")
	phase_indicator_bar = nodes.get("phase_indicator_bar")
	battle_ui = refs.get("battle_ui")
	claim_ui = refs.get("claim_ui")

func connect_net_signals() -> void:
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

# ---------- OVERLAY STATE ----------

func set_overlay_state(state: OverlayState, text: String = "") -> void:
	_overlay_state = state
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
			phase_label.text = ""
			phase_overlay.visible = true

# ---------- TURN BANNER (non-modal, replaces waiting overlay for turn-based waits) ----------

func _update_turn_banner() -> void:
	if not turn_banner_label:
		return
	# Only show the turn banner during Command & Contest (CARD_COMMAND) phase.
	# All other phases (Collect, etc.) are not strictly turn-based for this UI.
	if App.current_game_phase != App.GamePhase.CARD_COMMAND:
		turn_banner_label.visible = false
		return
	if not App.is_multiplayer or not multiplayer.has_multiplayer_peer():
		turn_banner_label.visible = false
		return
	var my_id := multiplayer.get_unique_id()
	if PhaseController.current_turn_peer_id == -1:
		turn_banner_label.visible = false
	elif PhaseController.current_turn_peer_id == my_id:
		turn_banner_label.text = "Your Turn"
		turn_banner_label.visible = true
	else:
		var turn_name := _get_player_name_for_peer(PhaseController.current_turn_peer_id)
		turn_banner_label.text = "%s's Turn" % turn_name
		turn_banner_label.visible = true

# ---------- CURRENT PHASE LABEL ----------

func _update_current_phase_label() -> void:
	# Update standalone phase label if available
	if current_phase_label:
		match App.current_game_phase:
			App.GamePhase.CARD_COMMAND:
				current_phase_label.text = "Command & Contest"
			App.GamePhase.CLAIM_CONQUER:
				if map_sub_phase == PhaseController.MapSubPhase.RESOURCE_COLLECTION:
					current_phase_label.text = "Collect"
				else:
					current_phase_label.text = "Command & Contest"
			App.GamePhase.CARD_COLLECTION:
				current_phase_label.text = "Collect"
		current_phase_label.visible = true
	# Update phase indicator bar if available
	if phase_indicator_bar:
		phase_indicator_bar.visible = true
		var is_collect := (
			App.current_game_phase == App.GamePhase.CARD_COLLECTION
			or (App.current_game_phase == App.GamePhase.CLAIM_CONQUER
				and map_sub_phase == PhaseController.MapSubPhase.RESOURCE_COLLECTION)
		)
		for child in phase_indicator_bar.get_children():
			if child is PanelContainer:
				var label: Label = child.get_child(0) if child.get_child_count() > 0 else null
				if not label:
					continue
				var is_active := false
				if is_collect and child.name.begins_with("Collect"):
					is_active = true
				elif not is_collect and child.name.begins_with("Command"):
					is_active = true
				if is_active:
					label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.55, 1.0))
				else:
					label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1.0))

# ---------- PHASE TRANSITION OVERLAY ----------

func show_phase_transition_overlay() -> void:
	if not phase_overlay or not phase_label:
		apply_phase_ui()
		return
	# Prevent double overlay if one is already animating
	if is_phase_overlay_animating:
		return
	# Hide top phase indicator during overlay to avoid redundant text.
	if current_phase_label:
		current_phase_label.visible = false
	if phase_indicator_bar:
		phase_indicator_bar.visible = false
	phase_label.text = App.phase_transition_text
	phase_overlay.visible = true
	phase_overlay.modulate.a = 0.0
	is_phase_overlay_animating = true
	var tween := create_tween()
	tween.tween_property(phase_overlay, "modulate:a", 1.0, 0.2)
	tween.tween_interval(0.8)
	tween.tween_property(phase_overlay, "modulate:a", 0.0, 0.2)
	tween.tween_callback(_on_phase_transition_finished)

func _on_phase_transition_finished() -> void:
	phase_overlay.visible = false
	is_phase_overlay_animating = false
	apply_phase_ui()
	animate_phase_buttons()
	phase_transition_finished.emit()

# ---------- PHASE UI ----------

func apply_phase_ui() -> void:
	if not intro_complete or is_phase_overlay_animating:
		return
	map_sub_phase = PhaseController.map_sub_phase
	match App.current_game_phase:
		App.GamePhase.CARD_COMMAND:
			_apply_card_command_ui()
		App.GamePhase.CLAIM_CONQUER:
			_apply_claim_conquer_ui()
		App.GamePhase.CARD_COLLECTION:
			_apply_card_collection_ui()
	settings_button.visible = true
	card_icon_button.visible = true
	# Always update and show the phase label
	_update_current_phase_label()
	phase_ui_applied.emit()

func _hide_battle_selection_ui() -> void:
	if battle_ui:
		battle_ui.hide_all()

func _apply_card_command_ui() -> void:
	minigame_button.visible = false
	bridge_minigame_button.visible = false
	ice_fishing_button.visible = false
	play_minigames_button.visible = false
	skip_to_battle_button.visible = false
	minigames_counter_label.visible = false
	battle_button.visible = false
	_hide_battle_selection_ui()
	skip_to_battle_button.visible = true
	skip_to_battle_button.text = "Done Placing Cards"
	if App.is_multiplayer and multiplayer.has_multiplayer_peer():
		var my_id := multiplayer.get_unique_id()
		if PhaseController.current_turn_peer_id != my_id:
			skip_to_battle_button.visible = false
			# No gray overlay — just show the turn banner
			set_overlay_state(OverlayState.NONE)
			is_waiting_for_others = false
			print("[CLIENT PhaseSystemUI] Command turn: waiting for %s (peer %d)" % [_get_player_name_for_peer(PhaseController.current_turn_peer_id), PhaseController.current_turn_peer_id])
		else:
			set_overlay_state(OverlayState.NONE)
			is_waiting_for_others = false
			# Clear stale attacking slots from previous battles to prevent phantom battles
			if BattleStateManager:
				BattleStateManager.clear_all_attacking_slots()
			print("[CLIENT PhaseSystemUI] Command turn: it's MY turn")
		_update_turn_banner()
	else:
		set_overlay_state(OverlayState.NONE)
		is_waiting_for_others = false
		_update_turn_banner()

func _apply_claim_conquer_ui() -> void:
	minigame_button.visible = false
	bridge_minigame_button.visible = false
	ice_fishing_button.visible = false
	play_minigames_button.visible = false
	skip_to_battle_button.visible = false
	_hide_battle_selection_ui()
	battle_button.visible = false
	match map_sub_phase:
		PhaseController.MapSubPhase.CLAIMING:
			_apply_claiming_ui()
		PhaseController.MapSubPhase.RESOURCE_COLLECTION:
			_apply_resource_collection_ui()
		PhaseController.MapSubPhase.BATTLE_READY:
			_apply_battle_ready_ui()

func _apply_claiming_ui() -> void:
	if finish_claiming_button:
		finish_claiming_button.visible = false
	if ready_for_battle_button:
		ready_for_battle_button.visible = false
	minigames_counter_label.visible = false
	if App.is_multiplayer and multiplayer.has_multiplayer_peer():
		var my_id := multiplayer.get_unique_id()
		if PhaseController.current_turn_peer_id != my_id:
			skip_to_battle_button.visible = false
			# No gray overlay — just show the turn banner
			set_overlay_state(OverlayState.NONE)
			is_waiting_for_others = false
			print("[CLIENT PhaseSystemUI] Claiming turn: waiting for %s (peer %d)" % [_get_player_name_for_peer(PhaseController.current_turn_peer_id), PhaseController.current_turn_peer_id])
		else:
			skip_to_battle_button.visible = true
			skip_to_battle_button.text = "Done claiming"
			set_overlay_state(OverlayState.NONE)
			is_waiting_for_others = false
			print("[CLIENT PhaseSystemUI] Claiming turn: it's MY turn")
		_update_turn_banner()
	else:
		skip_to_battle_button.visible = true
		skip_to_battle_button.text = "Done claiming"
		set_overlay_state(OverlayState.NONE)
		is_waiting_for_others = false
		_update_turn_banner()

func _apply_resource_collection_ui() -> void:
	if finish_claiming_button:
		finish_claiming_button.visible = false
	if turn_banner_label:
		turn_banner_label.visible = false
	if ready_for_battle_button:
		ready_for_battle_button.visible = false
	skip_to_battle_button.visible = false
	minigames_counter_label.visible = true
	_update_minigames_counter()
	if App.is_multiplayer:
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
			# Server handles the transition authoritatively; just show waiting overlay.
			set_overlay_state(OverlayState.WAITING, "Waiting for other players... (%d/%d done)" % [_done, _total])
			is_waiting_for_others = true
		else:
			set_overlay_state(OverlayState.NONE)
			is_waiting_for_others = false
			minigame_selection_started.emit()
	elif App.can_play_minigame():
		set_overlay_state(OverlayState.NONE)
		is_waiting_for_others = false
		minigame_selection_started.emit()

func _apply_battle_ready_ui() -> void:
	if finish_claiming_button:
		finish_claiming_button.visible = false
	if ready_for_battle_button:
		ready_for_battle_button.visible = false
	if App.is_multiplayer:
		_update_battle_selection_ui()
		if battle_ui.is_battle_in_progress():
			set_overlay_state(OverlayState.WAITING, "Battle in progress... waiting")
			is_waiting_for_others = true
		elif multiplayer.has_multiplayer_peer() and multiplayer.get_unique_id() != BattleSync.battle_decider_peer_id:
			var decider_name: String = battle_ui.get_decider_name()
			set_overlay_state(OverlayState.WAITING, "Waiting for %s to choose..." % decider_name)
		else:
			set_overlay_state(OverlayState.NONE)
	else:
		battle_button.visible = true
	minigames_counter_label.visible = false

func _apply_card_collection_ui() -> void:
	minigame_button.visible = true
	bridge_minigame_button.visible = true
	ice_fishing_button.visible = true
	play_minigames_button.visible = false
	skip_to_battle_button.visible = true
	skip_to_battle_button.text = "Skip to Next Round"
	battle_button.visible = false
	_hide_battle_selection_ui()
	minigames_counter_label.visible = false
	var should_disable_minigames := false
	if App.is_multiplayer and multiplayer.has_multiplayer_peer():
		var my_id := multiplayer.get_unique_id()
		if PhaseController.player_done_state.get(my_id, false):
			should_disable_minigames = true
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
		set_overlay_state(OverlayState.WAITING, "Waiting for other players... (%d/%d done)" % [_done_c, _total_c])
		is_waiting_for_others = true
	else:
		minigame_button.disabled = false
		bridge_minigame_button.disabled = false
		ice_fishing_button.disabled = false
		play_minigames_button.disabled = false
		skip_to_battle_button.disabled = false
		set_overlay_state(OverlayState.NONE)
		is_waiting_for_others = false
		minigame_selection_started.emit()

# ---------- BUTTON ANIMATION ----------

func animate_phase_buttons() -> void:
	var btn_tween := create_tween()
	btn_tween.set_parallel(true)
	_fade_if_visible(btn_tween, minigame_button)
	_fade_if_visible(btn_tween, bridge_minigame_button)
	_fade_if_visible(btn_tween, ice_fishing_button)
	_fade_if_visible(btn_tween, play_minigames_button)
	_fade_if_visible(btn_tween, battle_button)
	_fade_if_visible(btn_tween, skip_to_battle_button)
	_fade_if_visible(btn_tween, minigames_counter_label)
	_fade_if_visible(btn_tween, card_icon_button)
	if finish_claiming_button:
		_fade_if_visible(btn_tween, finish_claiming_button)
	if ready_for_battle_button:
		_fade_if_visible(btn_tween, ready_for_battle_button)
	settings_button.modulate.a = 0.0
	btn_tween.tween_property(settings_button, "modulate:a", 1.0, 0.3)

func _fade_if_visible(tween: Tween, node: CanvasItem) -> void:
	if node and node.visible:
		node.modulate.a = 0.0
		tween.tween_property(node, "modulate:a", 1.0, 0.3)

# ---------- MINIGAME COUNTER ----------

func _update_minigames_counter() -> void:
	if not minigames_counter_label:
		return
	var count: int
	if App.is_multiplayer and multiplayer.has_multiplayer_peer():
		count = PhaseController.player_minigame_counts.get(multiplayer.get_unique_id(), 0)
	else:
		count = App.minigames_completed_this_phase
	minigames_counter_label.text = "Minigames: %d/%d" % [count, App.MAX_MINIGAMES_PER_PHASE]

# ---------- SKIP / DONE BUTTON ----------

func on_skip_to_battle_pressed() -> void:
	if App.current_game_phase == App.GamePhase.CLAIM_CONQUER and map_sub_phase == PhaseController.MapSubPhase.CLAIMING:
		finish_claiming_pressed.emit()
		return
	match App.current_game_phase:
		App.GamePhase.CARD_COMMAND:
			skip_to_battle_button.visible = false
			if App.is_multiplayer and multiplayer.has_multiplayer_peer():
				# Check for pending battles (attacks on enemy territories)
				if BattleStateManager:
					App.pending_territory_battle_ids = BattleStateManager.get_territory_ids_with_battle()
				if App.pending_territory_battle_ids.size() > 0:
					App.is_territory_battle_attacker = true
					App.on_battle_completed()  # Pops first battle and starts it
					return  # Battles resolve first; turn advances when returning
				PhaseSync.request_end_card_command_turn()
				# Keep non-active players on the board with turn banner guidance; no gray waiting screen.
				set_overlay_state(OverlayState.NONE)
				is_waiting_for_others = false
			else:
				App.enter_claim_conquer_phase()
				show_phase_transition_overlay()
		App.GamePhase.CLAIM_CONQUER:
			# Non-CLAIMING sub-phases (RESOURCE_COLLECTION, BATTLE_READY):
			# server drives transitions, so do nothing here.
			pass
		App.GamePhase.CARD_COLLECTION:
			if App.is_multiplayer and multiplayer.has_multiplayer_peer():
				var prev_phase := App.current_game_phase
				App.skip_to_done()
				if App.current_game_phase == prev_phase:
					set_overlay_state(OverlayState.WAITING, "Waiting for other players...")
					is_waiting_for_others = true
			else:
				App.skip_to_done()
				App.enter_card_command_phase()
				show_phase_transition_overlay()
		_:
			App.skip_to_done()

# ---------- MULTIPLAYER SYNC HANDLERS ----------

func _on_net_phase_changed(phase_id: int) -> void:
	var prev_phase := App.current_game_phase
	PhaseController.sync_app_game_phase()
	if phase_id == 2:
		App.minigames_completed_this_phase = 0
	if not intro_complete:
		# RPC arrived before intro sequence finished — mark for deferred overlay
		_pending_phase_overlay = true
		return
	var phase_actually_changed := (App.current_game_phase != prev_phase)
	# If the phase was already pre-set by _on_intro_completed's sync_app_game_phase(),
	# check _pending_phase_overlay to catch that case
	if _pending_phase_overlay:
		phase_actually_changed = true
		_pending_phase_overlay = false
	# Sub-phase changes within CLAIM_CONQUER shouldn't re-show the phase overlay.
	# But a real transition INTO CLAIM_CONQUER from another phase should.
	if App.is_multiplayer and App.current_game_phase == App.GamePhase.CLAIM_CONQUER and prev_phase == App.GamePhase.CLAIM_CONQUER:
		phase_actually_changed = false
	if phase_actually_changed:
		is_waiting_for_others = false
		set_overlay_state(OverlayState.NONE)
		if turn_banner_label:
			turn_banner_label.visible = false
		# Hide ALL game buttons immediately to prevent flashing during overlay
		minigame_button.visible = false
		bridge_minigame_button.visible = false
		ice_fishing_button.visible = false
		play_minigames_button.visible = false
		skip_to_battle_button.visible = false
		minigames_counter_label.visible = false
		battle_button.visible = false
		_hide_battle_selection_ui()
		minigame_button.disabled = false
		bridge_minigame_button.disabled = false
		ice_fishing_button.disabled = false
		play_minigames_button.disabled = false
		skip_to_battle_button.disabled = false

		# Set phase_transition_text based on the new phase
		match App.current_game_phase:
			App.GamePhase.CARD_COMMAND:
				App.phase_transition_text = "Command & Contest"
			App.GamePhase.CLAIM_CONQUER:
				App.phase_transition_text = "Collect"
			App.GamePhase.CARD_COLLECTION:
				App.phase_transition_text = "Collect"
		print("[CLIENT PhaseSystemUI] Phase changed to %d — showing transition overlay" % phase_id)
		show_phase_transition_overlay()
	else:
		print("[CLIENT PhaseSystemUI] apply_phase_ui phase=%d sub=%d turn=%d" % [PhaseController.current_phase, PhaseController.map_sub_phase, PhaseController.current_turn_peer_id])
		apply_phase_ui()

func _on_turn_changed(_peer_id: int) -> void:
	if intro_complete and not is_phase_overlay_animating:
		apply_phase_ui()
		if multiplayer.has_multiplayer_peer():
			print("[CLIENT PhaseSystemUI] Turn changed → peer %d" % _peer_id)

func _on_done_counts_updated(done: int, total: int) -> void:
	local_done_count = done
	local_total_count = total
	if App.current_game_phase == App.GamePhase.CLAIM_CONQUER \
		and map_sub_phase == PhaseController.MapSubPhase.RESOURCE_COLLECTION \
		and minigames_counter_label.visible:
		_update_minigames_counter()
	# Server handles RESOURCE_COLLECTION -> CLAIMING transition authoritatively;
	# no client-side next_round_requested here to avoid stale-turn deadlocks.
	if is_waiting_for_others and _overlay_state == OverlayState.WAITING:
		waiting_label.text = "Waiting for other players... (%d/%d done)" % [done, total]
	# Phase mismatch repair
	var net_phase_as_enum: App.GamePhase
	match PhaseController.current_phase:
		0: net_phase_as_enum = App.GamePhase.CARD_COMMAND
		1: net_phase_as_enum = App.GamePhase.CLAIM_CONQUER
		2: net_phase_as_enum = App.GamePhase.CARD_COLLECTION
		_: net_phase_as_enum = App.GamePhase.CARD_COMMAND
	if net_phase_as_enum != App.current_game_phase:
		_on_net_phase_changed(PhaseController.current_phase)
	if App.current_game_phase == App.GamePhase.CLAIM_CONQUER and map_sub_phase < PhaseController.map_sub_phase:
		_on_net_map_sub_phase_changed(PhaseController.map_sub_phase)

func _on_battle_decider_changed(_peer_id: int) -> void:
	if not is_phase_overlay_animating:
		_update_battle_selection_ui()

func _on_battle_choices_updated(_snapshot: Dictionary) -> void:
	if not is_phase_overlay_animating:
		_update_battle_selection_ui()

func _on_battle_started(p1_id: int, p2_id: int, _side: String) -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	var my_id := multiplayer.get_unique_id()
	if my_id == p1_id or my_id == p2_id:
		if BattleStateManager:
			var territory_id := "%s_%s_battle" % [str(p1_id), str(p2_id)]
			BattleStateManager.set_current_territory(territory_id)
		enter_battle_scene.emit("res://scenes/card_battle.tscn")
	else:
		set_overlay_state(OverlayState.WAITING, "Battle in progress... waiting")
		is_waiting_for_others = true

func _on_battle_finished() -> void:
	waiting_overlay.visible = false
	is_waiting_for_others = false
	apply_phase_ui()

func _on_net_territory_claimed(territory_id: int, owner_id: int, cards: Array) -> void:
	territory_claimed_from_net.emit(territory_id, owner_id, cards)
	if claim_ui and claim_ui.get_current_territory_id() == territory_id:
		claim_ui.close_panel()

func _on_net_territory_claim_rejected(territory_id: int, claimer_name: String) -> void:
	if claim_ui and claim_ui.get_current_territory_id() == territory_id:
		claim_ui.show_already_claimed_message(claimer_name)

func _on_net_map_sub_phase_changed(sub_phase: int) -> void:
	# Ignore stale/non-applicable sub-phase transitions outside Claim & Conquer.
	# This prevents late RESOURCE_COLLECTION RPCs from reopening "Collect" UI while in Command.
	if App.current_game_phase != App.GamePhase.CLAIM_CONQUER:
		if sub_phase == PhaseController.MapSubPhase.CLAIMING:
			map_sub_phase = PhaseController.MapSubPhase.CLAIMING
		return
	var previous_sub_phase := map_sub_phase
	if sub_phase == 0:  # CLAIMING
		map_sub_phase = PhaseController.MapSubPhase.CLAIMING
		App.minigames_completed_this_phase = 0
		is_waiting_for_others = false
		waiting_overlay.visible = false
		set_overlay_state(OverlayState.NONE)
		# Show phase transition when exiting resource collection into claiming.
		if previous_sub_phase == PhaseController.MapSubPhase.RESOURCE_COLLECTION:
			App.phase_transition_text = "Command & Contest"
			show_phase_transition_overlay()
		else:
			apply_phase_ui()
			animate_phase_buttons()
	elif sub_phase == 1:  # RESOURCE_COLLECTION
		skip_to_battle_button.visible = false
		if finish_claiming_button:
			finish_claiming_button.visible = false
		map_sub_phase = PhaseController.MapSubPhase.RESOURCE_COLLECTION
		App.minigames_completed_this_phase = 0
		is_waiting_for_others = false
		collect_resources_overlay_requested.emit()
	elif sub_phase == 2:  # BATTLE_READY
		next_round_requested.emit()

func _update_battle_selection_ui() -> void:
	if battle_ui:
		battle_ui.update_ui()

# ---------- HELPERS ----------

func _get_player_name_for_peer(peer_id: int) -> String:
	if PlayerDataSync.player_names.has(peer_id):
		return PlayerDataSync.player_names[peer_id]
	for player in App.turn_order:
		if player.get("id", -1) == peer_id:
			return player.get("name", "Player")
	return "Player"

func _get_player_name_by_id(peer_id: int) -> String:
	for player in App.game_players:
		if player.get("id", -1) == peer_id:
			return player.get("name", "Player")
	return "Player"

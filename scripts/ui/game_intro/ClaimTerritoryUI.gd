extends PanelContainer
## Claim territory panel UI component.
## Attached to the existing ClaimTerritoryPanel node in GameIntro.tscn.

signal claim_submitted(territory_id: int, cards: Array)
signal update_submitted(territory_id: int, old_cards: Array, new_cards: Array)
signal attack_submitted(territory_id: int, cards: Array)
signal panel_closed()
signal minigame_requested(territory_id: int, region_id: int)

const UI_FONT := preload("res://fonts/m5x7.ttf")
const CLAIM_PANEL_FULL_OFFSET := Vector4(-220.0, -180.0, 220.0, 180.0)
const CLAIM_PANEL_PLAY_ONLY_OFFSET := Vector4(-160.0, -55.0, 160.0, 55.0)

# External references (set by initialize())
var territory_manager: TerritoryManager
var _territory_claim_state: Node

# Node references (resolved from children)
var claim_slots_container: HBoxContainer
var claim_hand_container: HBoxContainer
var claim_cancel_button: Button
var claim_button: Button
var claim_attack_button: Button
var claim_play_minigame_button: Button

# Panel state
var current_claim_territory_id: int = -1
var claim_panel_play_only_mode: bool = false
var claim_slot_cards: Array = [null, null, null]
var claim_attacking_slot_cards: Array = [null, null, null]
var claim_hand_cards: Array = []
var claim_selected_hand_index: int = -1
var claim_panel_attack_mode: bool = false
var original_claim_slot_cards: Array = [null, null, null] # snapshot of cards when panel opened for updates

# Message panel
var message_panel: PanelContainer
var message_label: Label
var message_close_button: Button

func initialize(territory_mgr: TerritoryManager, tcs: Node) -> void:
	territory_manager = territory_mgr
	_territory_claim_state = tcs

func _ready() -> void:
	claim_slots_container = get_node_or_null("MarginContainer/VBoxContainer/SlotsContainer") as HBoxContainer
	claim_hand_container = get_node_or_null("MarginContainer/VBoxContainer/ClaimHandContainer") as HBoxContainer
	claim_cancel_button = get_node_or_null("MarginContainer/VBoxContainer/ButtonsContainer/CancelButton") as Button
	claim_button = get_node_or_null("MarginContainer/VBoxContainer/ButtonsContainer/ClaimButton") as Button
	claim_attack_button = get_node_or_null("MarginContainer/VBoxContainer/ButtonsContainer/AttackButton") as Button
	claim_play_minigame_button = get_node_or_null("MarginContainer/VBoxContainer/ButtonsContainer/PlayMinigameButton") as Button

	if claim_cancel_button:
		claim_cancel_button.pressed.connect(_on_cancel_clicked)
	if claim_button:
		claim_button.pressed.connect(_on_claim_clicked)
	if claim_attack_button:
		claim_attack_button.pressed.connect(_on_attack_clicked)
	if claim_play_minigame_button:
		claim_play_minigame_button.pressed.connect(_on_play_minigame_pressed)

	_setup_message_panel()

func _setup_message_panel() -> void:
	message_panel = get_parent().get_node_or_null("MessagePanel") as PanelContainer
	if not message_panel:
		message_panel = PanelContainer.new()
		message_panel.name = "MessagePanel"
		message_panel.set_anchors_preset(Control.PRESET_CENTER)
		message_panel.offset_left = -200
		message_panel.offset_top = -80
		message_panel.offset_right = 200
		message_panel.offset_bottom = 80
		get_parent().add_child.call_deferred(message_panel)

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

# ---------- PUBLIC API ----------

func open_claim_panel(territory_id: int, map_sub_phase: int, _game_phase: int) -> void:
	claim_panel_play_only_mode = false
	if BattleStateManager:
		BattleStateManager.set_current_territory(str(territory_id))
	offset_left = CLAIM_PANEL_FULL_OFFSET.x
	offset_top = CLAIM_PANEL_FULL_OFFSET.y
	offset_right = CLAIM_PANEL_FULL_OFFSET.z
	offset_bottom = CLAIM_PANEL_FULL_OFFSET.w
	_deselect_current()
	current_claim_territory_id = territory_id
	claim_selected_hand_index = -1
	var title_label: Label = get_node_or_null("MarginContainer/VBoxContainer/TitleLabel") as Label
	if title_label:
		title_label.text = "Claim Territory"
	if claim_slots_container:
		claim_slots_container.visible = true
	var hand_label: Control = get_node_or_null("MarginContainer/VBoxContainer/HandLabel")
	if hand_label:
		hand_label.visible = true
	if claim_hand_container:
		claim_hand_container.visible = true
	if claim_cancel_button:
		claim_cancel_button.visible = true
		claim_cancel_button.text = "Cancel"

	var is_claimed: bool = _territory_claim_state and _territory_claim_state.call("is_claimed", territory_id)
	var tid_str := str(territory_id)
	claim_panel_attack_mode = is_claimed and (App.current_game_phase == App.GamePhase.CLAIM_CONQUER)

	if claim_panel_attack_mode:
		var defs: Dictionary = BattleStateManager.get_defending_slots(tid_str) if BattleStateManager else {}
		if not defs.is_empty():
			claim_slot_cards = [null, null, null]
			for idx in defs:
				if int(idx) < 3:
					claim_slot_cards[int(idx)] = defs[idx]
		else:
			var saved: Array = _territory_claim_state.call("get_cards", territory_id) as Array if _territory_claim_state else []
			claim_slot_cards = []
			for i in range(3):
				claim_slot_cards.append(saved[i] if i < saved.size() and saved[i] != null else null)
		var atks: Dictionary = BattleStateManager.get_attacking_slots(tid_str) if BattleStateManager else {}
		claim_attacking_slot_cards = [null, null, null]
		for i in range(3):
			if atks.has(i):
				claim_attacking_slot_cards[i] = atks[i]
		claim_hand_cards = App.player_card_collection.duplicate()
		claim_button.visible = false
		var local_id: Variant = _get_local_player_id()
		var owner_id: Variant = _territory_claim_state.call("get_owner_id", territory_id) if _territory_claim_state else null
		var is_owner: bool = owner_id != null and int(local_id) == int(owner_id)
		if claim_attack_button:
			claim_attack_button.visible = not is_owner and (map_sub_phase == PhaseController.MapSubPhase.CLAIMING)
	else:
		claim_attacking_slot_cards = [null, null, null]
		if is_claimed:
			var saved: Array = _territory_claim_state.call("get_cards", territory_id) as Array
			claim_slot_cards = []
			for i in range(3):
				claim_slot_cards.append(saved[i] if i < saved.size() and saved[i] != null else null)
			original_claim_slot_cards = []
			for i in range(3):
				if claim_slot_cards[i] != null and claim_slot_cards[i] is Dictionary:
					original_claim_slot_cards.append(claim_slot_cards[i].duplicate())
				else:
					original_claim_slot_cards.append(null)
			claim_hand_cards = App.player_card_collection.duplicate()
			var local_id_check: Variant = _get_local_player_id()
			var owner_id_check: Variant = _territory_claim_state.call("get_owner_id", territory_id) if _territory_claim_state else null
			var is_local_owner: bool = owner_id_check != null and int(local_id_check) == int(owner_id_check)
			if is_local_owner and map_sub_phase == PhaseController.MapSubPhase.CLAIMING:
				claim_button.visible = true
				claim_button.text = "Update Territory"
				if title_label:
					title_label.text = "Update Territory"
			else:
				claim_button.visible = false
		else:
			original_claim_slot_cards = [null, null, null]
			claim_slot_cards = [null, null, null]
			claim_hand_cards = App.player_card_collection.duplicate()
			claim_button.visible = true
			if claim_button:
				claim_button.text = "Claim"
		if claim_attack_button:
			claim_attack_button.visible = false
	if hand_label and hand_label is Label:
		(hand_label as Label).text = "Place attacking cards to start battle" if claim_panel_attack_mode else "Place 1-3 cards (click card, then click a slot)"
	_populate_claim_slots()
	_populate_claim_hand()
	_update_claim_button_state()
	_update_attack_button_state()

	var show_play_minigame: bool = (map_sub_phase == PhaseController.MapSubPhase.BATTLE_READY)
	var region_id: int = 1
	if territory_manager and territory_manager.territory_data.has(territory_id):
		region_id = territory_manager.territory_data[territory_id].region_id
	var region_info: Dictionary = TerritoryClaimManager.REGION_MINIGAMES.get(region_id, { "name": "", "scene": "" })
	var scene_path: String = region_info.get("scene", "")
	var region_name: String = region_info.get("name", "")
	if map_sub_phase == PhaseController.MapSubPhase.CLAIMING:
		if claim_play_minigame_button:
			claim_play_minigame_button.visible = false
		if claim_attack_button:
			if claim_panel_attack_mode:
				var local_id: Variant = _get_local_player_id()
				var owner_id: Variant = _territory_claim_state.call("get_owner_id", territory_id) if _territory_claim_state else null
				var is_owner: bool = owner_id != null and int(local_id) == int(owner_id)
				claim_attack_button.visible = not is_owner
			else:
				claim_attack_button.visible = false
	else:
		if claim_play_minigame_button:
			if show_play_minigame and scene_path != "" and region_name != "":
				claim_play_minigame_button.text = "Play %s" % region_name
				claim_play_minigame_button.visible = true
			else:
				claim_play_minigame_button.visible = false
		if claim_attack_button:
			claim_attack_button.visible = false
	z_index = 100
	visible = true
	var indicator: TerritoryIndicator = territory_manager.get_territory_node(territory_id) if territory_manager else null
	if indicator:
		indicator.show_selection_glow()

func open_play_only_panel(territory_id: int) -> void:
	_deselect_current()
	current_claim_territory_id = territory_id
	claim_panel_play_only_mode = true
	offset_left = CLAIM_PANEL_PLAY_ONLY_OFFSET.x
	offset_top = CLAIM_PANEL_PLAY_ONLY_OFFSET.y
	offset_right = CLAIM_PANEL_PLAY_ONLY_OFFSET.z
	offset_bottom = CLAIM_PANEL_PLAY_ONLY_OFFSET.w
	var title_label: Label = get_node_or_null("MarginContainer/VBoxContainer/TitleLabel") as Label
	if title_label:
		title_label.text = "Collect resources"
	if claim_slots_container:
		claim_slots_container.visible = false
	var hand_label: Control = get_node_or_null("MarginContainer/VBoxContainer/HandLabel")
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
	var region_info: Dictionary = TerritoryClaimManager.REGION_MINIGAMES.get(region_id, { "name": "", "scene": "" })
	var scene_path: String = region_info.get("scene", "")
	var region_name: String = region_info.get("name", "")
	if claim_play_minigame_button:
		if scene_path != "" and region_name != "":
			claim_play_minigame_button.text = "Play %s" % region_name
			claim_play_minigame_button.visible = true
		else:
			claim_play_minigame_button.visible = false
	if claim_attack_button:
		claim_attack_button.visible = false
	z_index = 100
	visible = true
	var play_indicator: TerritoryIndicator = territory_manager.get_territory_node(territory_id) if territory_manager else null
	if play_indicator:
		play_indicator.show_selection_glow()

func close_panel() -> void:
	_deselect_current()
	current_claim_territory_id = -1
	visible = false
	claim_panel_play_only_mode = false
	offset_left = CLAIM_PANEL_FULL_OFFSET.x
	offset_top = CLAIM_PANEL_FULL_OFFSET.y
	offset_right = CLAIM_PANEL_FULL_OFFSET.z
	offset_bottom = CLAIM_PANEL_FULL_OFFSET.w
	if claim_slots_container:
		claim_slots_container.visible = true
	var hand_label: Control = get_node_or_null("MarginContainer/VBoxContainer/HandLabel")
	if hand_label:
		hand_label.visible = true
	if claim_hand_container:
		claim_hand_container.visible = true
	if claim_cancel_button:
		claim_cancel_button.visible = true
		claim_cancel_button.text = "Cancel"

func is_open() -> bool:
	return visible

func get_current_territory_id() -> int:
	return current_claim_territory_id

func show_unclaimed_territory_message() -> void:
	if not message_panel or not message_label:
		return
	if App.minigames_completed_this_phase >= App.MAX_MINIGAMES_PER_PHASE:
		message_label.text = "You've already completed %d minigames this phase. Click 'Ready for Battle' to continue." % App.MAX_MINIGAMES_PER_PHASE
	else:
		message_label.text = "This territory must be claimed before you can collect resources here."
	if message_close_button:
		message_close_button.visible = true
	message_panel.z_index = 100
	message_panel.visible = true
	message_panel.modulate.a = 0.0
	var tween := get_tree().create_tween()
	tween.tween_property(message_panel, "modulate:a", 1.0, 0.2)

func show_already_claimed_message(claimer_name: String) -> void:
	if not message_panel or not message_label:
		return
	message_label.text = "%s has claimed this territory already!" % claimer_name
	if message_close_button:
		message_close_button.visible = true
	message_panel.z_index = 100
	message_panel.visible = true
	message_panel.modulate.a = 0.0
	var tween := get_tree().create_tween()
	tween.tween_property(message_panel, "modulate:a", 1.0, 0.2)

# ---------- INTERNAL ----------

func _deselect_current() -> void:
	if territory_manager and current_claim_territory_id >= 0:
		var indicator: TerritoryIndicator = territory_manager.get_territory_node(current_claim_territory_id)
		if indicator:
			indicator.deselect()

func _on_cancel_clicked() -> void:
	close_panel()
	panel_closed.emit()

func _on_claim_clicked() -> void:
	if current_claim_territory_id < 0:
		close_panel()
		panel_closed.emit()
		return
	var has_any_card: bool = false
	for slot_idx in range(3):
		if claim_slot_cards[slot_idx] != null:
			has_any_card = true
			break
	if not has_any_card:
		return
	if _is_territory_claimed_by_local(current_claim_territory_id):
		update_submitted.emit(current_claim_territory_id, original_claim_slot_cards, claim_slot_cards)
	else:
		claim_submitted.emit(current_claim_territory_id, claim_slot_cards)

func _on_attack_clicked() -> void:
	if current_claim_territory_id < 0:
		close_panel()
		panel_closed.emit()
		return
	var has_any_card: bool = false
	for slot_idx in range(3):
		if claim_attacking_slot_cards[slot_idx] != null:
			has_any_card = true
			break
	if not has_any_card:
		return
	attack_submitted.emit(current_claim_territory_id, claim_attacking_slot_cards)

func _on_play_minigame_pressed() -> void:
	if current_claim_territory_id < 0 or not territory_manager or not territory_manager.territory_data.has(current_claim_territory_id):
		return
	var territory: Territory = territory_manager.territory_data[current_claim_territory_id]
	var region_id: int = territory.region_id
	close_panel()
	minigame_requested.emit(current_claim_territory_id, region_id)

func _on_message_close_pressed() -> void:
	if not message_panel:
		return
	var tween := get_tree().create_tween()
	tween.tween_property(message_panel, "modulate:a", 0.0, 0.15)
	tween.tween_callback(func(): message_panel.visible = false)

func _populate_claim_slots() -> void:
	for child in claim_slots_container.get_children():
		child.queue_free()
	var slot_size := Vector2(70, 100)
	var local_id: Variant = _get_local_player_id()
	var owner_id: Variant = _territory_claim_state.call("get_owner_id", current_claim_territory_id) if _territory_claim_state else null
	var is_owner: bool = owner_id != null and int(local_id) == int(owner_id)

	if claim_panel_attack_mode:
		var vbox := VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 8)
		var def_label := Label.new()
		def_label.text = "Defending"
		def_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(def_label)
		var def_row := HBoxContainer.new()
		def_row.add_theme_constant_override("separation", 10)
		for i in range(3):
			var panel := Panel.new()
			panel.custom_minimum_size = slot_size
			panel.set_meta("slot_type", "defending")
			panel.set_meta("slot_index", i)
			var tex := TextureRect.new()
			tex.set_anchors_preset(Control.PRESET_FULL_RECT)
			tex.offset_left = 4; tex.offset_top = 4; tex.offset_right = -4; tex.offset_bottom = -4
			tex.expand_mode = TextureRect.EXPAND_FIT_HEIGHT_PROPORTIONAL
			tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
			if claim_slot_cards[i] != null and claim_slot_cards[i] is Dictionary:
				if is_owner:
					var path: String = claim_slot_cards[i].get("path", "")
					var frame: int = int(claim_slot_cards[i].get("frame", 0))
					if path != "" and ResourceLoader.exists(path):
						var sf: SpriteFrames = load(path) as SpriteFrames
						if sf and sf.has_animation("default"):
							tex.texture = sf.get_frame_texture("default", frame)
				else:
					var back := _get_card_back_texture()
					if back:
						tex.texture = back
			panel.add_child(tex)
			if is_owner:
				panel.gui_input.connect(_on_slot_gui_input_attack.bind("defending", i))
			panel.mouse_filter = Control.MOUSE_FILTER_STOP
			def_row.add_child(panel)
		vbox.add_child(def_row)
		var atk_label := Label.new()
		atk_label.text = "Attacking"
		atk_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(atk_label)
		var atk_row := HBoxContainer.new()
		atk_row.add_theme_constant_override("separation", 10)
		for i in range(3):
			var panel := Panel.new()
			panel.custom_minimum_size = slot_size
			panel.set_meta("slot_type", "attacking")
			panel.set_meta("slot_index", i)
			var tex := TextureRect.new()
			tex.set_anchors_preset(Control.PRESET_FULL_RECT)
			tex.offset_left = 4; tex.offset_top = 4; tex.offset_right = -4; tex.offset_bottom = -4
			tex.expand_mode = TextureRect.EXPAND_FIT_HEIGHT_PROPORTIONAL
			tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
			if claim_attacking_slot_cards[i] != null and claim_attacking_slot_cards[i] is Dictionary:
				var path: String = claim_attacking_slot_cards[i].get("path", "")
				var frame: int = int(claim_attacking_slot_cards[i].get("frame", 0))
				if path != "" and ResourceLoader.exists(path):
					var sf: SpriteFrames = load(path) as SpriteFrames
					if sf and sf.has_animation("default"):
						tex.texture = sf.get_frame_texture("default", frame)
			panel.add_child(tex)
			if not is_owner:
				panel.gui_input.connect(_on_slot_gui_input_attack.bind("attacking", i))
			panel.mouse_filter = Control.MOUSE_FILTER_STOP
			atk_row.add_child(panel)
		vbox.add_child(atk_row)
		claim_slots_container.add_child(vbox)
		return

	for i in range(3):
		var panel := Panel.new()
		panel.custom_minimum_size = slot_size
		panel.set_meta("slot_index", i)
		var tex := TextureRect.new()
		tex.set_anchors_preset(Control.PRESET_FULL_RECT)
		tex.offset_left = 4; tex.offset_top = 4; tex.offset_right = -4; tex.offset_bottom = -4
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
		panel.gui_input.connect(_on_slot_gui_input.bind(i))
		claim_slots_container.add_child(panel)

func _is_territory_claimed_by_local(territory_id: int) -> bool:
	if not _territory_claim_state or not _territory_claim_state.has_method("is_claimed"):
		return false
	if not _territory_claim_state.call("is_claimed", territory_id):
		return false
	var owner_id: Variant = _territory_claim_state.call("get_owner_id", territory_id)
	var local_id: Variant = _get_local_player_id()
	return owner_id != null and local_id != null and int(owner_id) == int(local_id)

func _on_slot_gui_input(event: InputEvent, slot_index: int) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and mb.double_click:
			if claim_slot_cards[slot_index] != null and claim_slot_cards[slot_index] is Dictionary:
				var c: Dictionary = claim_slot_cards[slot_index]
				var path: String = c.get("path", "")
				var frame: int = int(c.get("frame", 0))
				if not path.is_empty() and CardEnlargeOverlay:
					CardEnlargeOverlay.show_enlarged_card(path, frame)
				return
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			if claim_selected_hand_index >= 0 and claim_selected_hand_index < claim_hand_cards.size():
				var card: Dictionary = claim_hand_cards[claim_selected_hand_index]
				claim_slot_cards[slot_index] = card
				claim_hand_cards.remove_at(claim_selected_hand_index)
				claim_selected_hand_index = -1
				_populate_claim_slots()
				_populate_claim_hand()
				_update_claim_button_state()
			elif claim_slot_cards[slot_index] != null:
				if _is_territory_claimed_by_local(current_claim_territory_id):
					var card_count := 0
					for idx in range(3):
						if claim_slot_cards[idx] != null:
							card_count += 1
					if card_count <= 1:
						return
				claim_hand_cards.append(claim_slot_cards[slot_index])
				claim_slot_cards[slot_index] = null
				_populate_claim_slots()
				_populate_claim_hand()
				_update_claim_button_state()

func _on_slot_gui_input_attack(event: InputEvent, slot_type: String, slot_index: int) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
			return
		var arr: Array = claim_slot_cards if slot_type == "defending" else claim_attacking_slot_cards
		if mb.double_click and slot_index >= 0 and slot_index < arr.size() and arr[slot_index] != null and arr[slot_index] is Dictionary:
			var c: Dictionary = arr[slot_index]
			var path: String = c.get("path", "")
			var frame: int = int(c.get("frame", 0))
			if not path.is_empty() and CardEnlargeOverlay:
				CardEnlargeOverlay.show_enlarged_card(path, frame)
			return
		if claim_selected_hand_index >= 0 and claim_selected_hand_index < claim_hand_cards.size():
			var card: Dictionary = claim_hand_cards[claim_selected_hand_index]
			if slot_type == "attacking":
				claim_attacking_slot_cards[slot_index] = card
			elif slot_type == "defending":
				claim_slot_cards[slot_index] = card
			claim_hand_cards.remove_at(claim_selected_hand_index)
			claim_selected_hand_index = -1
		elif arr[slot_index] != null:
			if slot_type == "attacking":
				claim_hand_cards.append(claim_attacking_slot_cards[slot_index])
				claim_attacking_slot_cards[slot_index] = null
			elif slot_type == "defending":
				claim_hand_cards.append(claim_slot_cards[slot_index])
				claim_slot_cards[slot_index] = null
		if slot_type == "defending":
			var defending_dict: Dictionary = {}
			for idx in range(3):
				if claim_slot_cards[idx] != null and claim_slot_cards[idx] is Dictionary:
					defending_dict[idx] = claim_slot_cards[idx]
			if BattleStateManager:
				BattleStateManager.set_defending_slots(str(current_claim_territory_id), defending_dict)
			if _territory_claim_state and _territory_claim_state.has_method("set_claim"):
				var owner_id: Variant = _territory_claim_state.call("get_owner_id", current_claim_territory_id)
				if owner_id != null:
					_territory_claim_state.set_claim(current_claim_territory_id, int(owner_id), claim_slot_cards)
		_populate_claim_slots()
		_populate_claim_hand()
		_update_attack_button_state()

func _update_claim_button_state() -> void:
	if not claim_button:
		return
	var has_any: bool = false
	for slot_idx in range(3):
		if claim_slot_cards[slot_idx] != null:
			has_any = true
			break
	claim_button.disabled = not has_any

func _update_attack_button_state() -> void:
	if not claim_attack_button:
		return
	var has_any: bool = false
	for slot_idx in range(3):
		if claim_attacking_slot_cards[slot_idx] != null:
			has_any = true
			break
	claim_attack_button.disabled = not has_any

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
		tex.offset_left = 4; tex.offset_top = 4; tex.offset_right = -4; tex.offset_bottom = -4
		tex.expand_mode = TextureRect.EXPAND_FIT_HEIGHT_PROPORTIONAL
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var path: String = card_data.get("path", "")
		var frame: int = int(card_data.get("frame", 0))
		if path != "" and ResourceLoader.exists(path):
			var sf: SpriteFrames = load(path) as SpriteFrames
			if sf and sf.has_animation("default"):
				tex.texture = sf.get_frame_texture("default", frame)
		btn.add_child(tex)
		btn.pressed.connect(_on_hand_card_clicked.bind(i))
		btn.gui_input.connect(_on_hand_card_gui_input.bind(i))
		claim_hand_container.add_child(btn)

func _on_hand_card_gui_input(event: InputEvent, hand_index: int) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and mb.double_click:
			if hand_index >= 0 and hand_index < claim_hand_cards.size():
				var c: Dictionary = claim_hand_cards[hand_index]
				var path: String = c.get("path", "")
				var frame: int = int(c.get("frame", 0))
				if not path.is_empty() and CardEnlargeOverlay:
					CardEnlargeOverlay.show_enlarged_card(path, frame)
				get_viewport().set_input_as_handled()

func _on_hand_card_clicked(hand_index: int) -> void:
	claim_selected_hand_index = hand_index

func _get_card_back_texture() -> Texture2D:
	var path := "res://assets/cardback.pxo"
	if not ResourceLoader.exists(path):
		return null
	var sf: SpriteFrames = load(path) as SpriteFrames
	if not sf or not sf.has_animation("default"):
		return null
	return sf.get_frame_texture("default", 0)

func _get_local_player_id() -> Variant:
	for p in App.game_players:
		if p.get("is_local", false):
			return p.get("id", 1)
	return 1

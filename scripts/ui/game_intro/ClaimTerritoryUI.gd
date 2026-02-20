extends PanelContainer

## ClaimTerritoryUI — Script-on-node on $ClaimTerritoryPanel.
## Handles territory claim panel: card slot management, claim/attack submission, minigame requests.

signal claim_submitted(territory_id: int, cards: Array)
signal attack_submitted(territory_id: int, cards: Array)
signal minigame_requested(territory_id: int, region_id: int)

const UI_FONT := preload("res://fonts/m5x7.ttf")

const CLAIM_PANEL_FULL_OFFSET := Vector4(-220.0, -180.0, 220.0, 180.0)
const CLAIM_PANEL_PLAY_ONLY_OFFSET := Vector4(-160.0, -55.0, 160.0, 55.0)

const REGION_MINIGAMES: Dictionary = {
	1: { "name": "Bridge", "scene": "res://scenes/BridgeGame.tscn" },
	6: { "name": "Ice fishing", "scene": "res://scenes/IceFishingGame.tscn" },
	5: { "name": "River crossing", "scene": "res://scenes/Game.tscn" },
	4: { "name": "", "scene": "" },
	3: { "name": "", "scene": "" },
	2: { "name": "", "scene": "" }
}

var territory_manager: TerritoryManager
var _territory_claim_state: Node

# Claim panel state
var current_claim_territory_id: int = -1
var claim_panel_play_only_mode: bool = false
var claim_slot_cards: Array = [null, null, null]
var claim_hand_cards: Array = []
var claim_selected_hand_index: int = -1

# Scene nodes (resolved in _ready)
var claim_slots_container: HBoxContainer
var claim_hand_container: HBoxContainer
var claim_cancel_button: Button
var claim_button: Button
var claim_attack_button: Button
var claim_play_minigame_button: Button

# Message panel (built programmatically)
var message_panel: PanelContainer
var message_label: Label

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
		claim_play_minigame_button.pressed.connect(_on_play_minigame_clicked)
	visible = false

func initialize(p_territory_manager: TerritoryManager, p_claim_state: Node) -> void:
	territory_manager = p_territory_manager
	_territory_claim_state = p_claim_state

func get_current_territory_id() -> int:
	return current_claim_territory_id

func open_claim_panel(territory_id: int, map_sub_phase: int, _game_phase) -> void:
	claim_panel_play_only_mode = false
	offset_left = CLAIM_PANEL_FULL_OFFSET.x
	offset_top = CLAIM_PANEL_FULL_OFFSET.y
	offset_right = CLAIM_PANEL_FULL_OFFSET.z
	offset_bottom = CLAIM_PANEL_FULL_OFFSET.w
	_deselect_territory()
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

	# Check if already claimed — show existing cards
	if _territory_claim_state and _territory_claim_state.call("is_claimed", territory_id):
		var saved: Array = _territory_claim_state.call("get_cards", territory_id) as Array
		claim_slot_cards = []
		for i in range(3):
			claim_slot_cards.append(saved[i] if i < saved.size() and saved[i] != null else null)
		claim_hand_cards = App.player_card_collection.duplicate()
		if claim_button:
			claim_button.visible = false
		# Show attack button if claimed by someone else
		var owner_id = _territory_claim_state.call("get_owner_id", territory_id)
		var local_id = _get_local_player_id()
		if claim_attack_button:
			claim_attack_button.visible = (owner_id != null and owner_id != local_id)
	else:
		claim_slot_cards = [null, null, null]
		claim_hand_cards = App.player_card_collection.duplicate()
		if claim_button:
			claim_button.visible = true
		if claim_attack_button:
			claim_attack_button.visible = false

	_populate_slots()
	_populate_hand()
	_update_button_state()

	# Play minigame button: only in RESOURCE_COLLECTION
	var show_play := (map_sub_phase == PhaseController.MapSubPhase.RESOURCE_COLLECTION)
	_setup_minigame_button(territory_id, show_play)
	visible = true

func open_play_only_panel(territory_id: int) -> void:
	_deselect_territory()
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
	if claim_attack_button:
		claim_attack_button.visible = false
	if claim_cancel_button:
		claim_cancel_button.visible = true
		claim_cancel_button.text = "Close"
	_setup_minigame_button(territory_id, true)
	visible = true

func close_panel() -> void:
	_deselect_territory()
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

func show_already_claimed_message(reason: String) -> void:
	_show_message("Territory already claimed by %s" % reason)

func show_unclaimed_territory_message() -> void:
	if App.minigames_completed_this_phase >= App.MAX_MINIGAMES_PER_PHASE:
		_show_message("You've already completed %d minigames this phase." % App.MAX_MINIGAMES_PER_PHASE)
	else:
		_show_message("You can only play minigames on territories you've claimed.")

# ---------- INTERNAL ----------

func _deselect_territory() -> void:
	if territory_manager and current_claim_territory_id >= 0:
		var node: TerritoryNode = territory_manager.get_territory_node(current_claim_territory_id)
		if node:
			node.deselect()

func _setup_minigame_button(territory_id: int, show: bool) -> void:
	if not claim_play_minigame_button:
		return
	if not show:
		claim_play_minigame_button.visible = false
		return
	var region_id: int = 1
	if territory_manager and territory_manager.territory_data.has(territory_id):
		region_id = territory_manager.territory_data[territory_id].region_id
	var region_info: Dictionary = REGION_MINIGAMES.get(region_id, { "name": "", "scene": "" })
	var scene_path: String = region_info.get("scene", "")
	var region_name: String = region_info.get("name", "")
	if scene_path != "" and region_name != "":
		claim_play_minigame_button.text = "Play %s" % region_name
		claim_play_minigame_button.visible = true
	else:
		claim_play_minigame_button.visible = false

func _populate_slots() -> void:
	if not claim_slots_container:
		return
	for child in claim_slots_container.get_children():
		child.queue_free()
	var slot_size := Vector2(70, 100)
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

func _on_slot_gui_input(event: InputEvent, slot_index: int) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			if claim_selected_hand_index >= 0 and claim_selected_hand_index < claim_hand_cards.size():
				var card: Dictionary = claim_hand_cards[claim_selected_hand_index]
				claim_slot_cards[slot_index] = card
				claim_hand_cards.remove_at(claim_selected_hand_index)
				claim_selected_hand_index = -1
				_populate_slots(); _populate_hand(); _update_button_state()
			elif claim_slot_cards[slot_index] != null:
				claim_hand_cards.append(claim_slot_cards[slot_index])
				claim_slot_cards[slot_index] = null
				_populate_slots(); _populate_hand(); _update_button_state()

func _update_button_state() -> void:
	if not claim_button:
		return
	var has_any: bool = false
	for slot_idx in range(3):
		if claim_slot_cards[slot_idx] != null:
			has_any = true
			break
	claim_button.disabled = not has_any
	if claim_attack_button:
		claim_attack_button.disabled = not has_any

func _populate_hand() -> void:
	if not claim_hand_container:
		return
	for child in claim_hand_container.get_children():
		child.queue_free()
	var card_size := Vector2(60, 90)
	for i in range(claim_hand_cards.size()):
		var card_data: Dictionary = claim_hand_cards[i]
		var btn := Button.new()
		btn.custom_minimum_size = card_size
		btn.flat = true
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
		claim_hand_container.add_child(btn)

func _on_hand_card_clicked(hand_index: int) -> void:
	claim_selected_hand_index = hand_index

func _on_cancel_clicked() -> void:
	close_panel()

func _on_claim_clicked() -> void:
	if current_claim_territory_id < 0:
		close_panel()
		return
	var has_any_card: bool = false
	for slot_idx in range(3):
		if claim_slot_cards[slot_idx] != null:
			has_any_card = true
			break
	if not has_any_card:
		return
	claim_submitted.emit(current_claim_territory_id, claim_slot_cards.duplicate())

func _on_attack_clicked() -> void:
	if current_claim_territory_id < 0:
		close_panel()
		return
	var has_any_card: bool = false
	for slot_idx in range(3):
		if claim_slot_cards[slot_idx] != null:
			has_any_card = true
			break
	if not has_any_card:
		return
	attack_submitted.emit(current_claim_territory_id, claim_slot_cards.duplicate())

func _on_play_minigame_clicked() -> void:
	if current_claim_territory_id < 0 or not territory_manager:
		return
	if not territory_manager.territory_data.has(current_claim_territory_id):
		return
	var territory: Territory = territory_manager.territory_data[current_claim_territory_id]
	minigame_requested.emit(current_claim_territory_id, territory.region_id)

func _get_local_player_id() -> Variant:
	for p in App.game_players:
		if p.get("is_local", false):
			return p.get("id", 1)
	return 1

func _show_message(text: String) -> void:
	if not message_panel:
		_create_message_panel()
	if message_label:
		message_label.text = text
	if message_panel:
		message_panel.visible = true
		message_panel.modulate.a = 0.0
		var tween := create_tween()
		tween.tween_property(message_panel, "modulate:a", 1.0, 0.2)

func _create_message_panel() -> void:
	message_panel = PanelContainer.new()
	message_panel.name = "MessagePanel"
	message_panel.set_anchors_preset(Control.PRESET_CENTER)
	message_panel.offset_left = -200; message_panel.offset_top = -80
	message_panel.offset_right = 200; message_panel.offset_bottom = 80
	# Add to parent (GameIntro) so it's above the claim panel
	get_parent().add_child(message_panel)
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
	var close_button := Button.new()
	close_button.text = "Close"
	close_button.pressed.connect(func():
		var tw := create_tween()
		tw.tween_property(message_panel, "modulate:a", 0.0, 0.15)
		tw.tween_callback(func(): message_panel.visible = false)
	)
	button_container.add_child(close_button)
	message_panel.visible = false

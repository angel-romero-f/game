extends Node

## PlayerHandUI — Card hand toggle panel.
## Shows/hides the player's card collection via a card icon button.

var card_icon_button: Button
var hand_display_panel: PanelContainer
var hand_container: HBoxContainer
var card_count_label: Label
var is_hand_visible: bool = false

func initialize(nodes: Dictionary) -> void:
	card_icon_button = nodes.get("card_icon_button")
	hand_display_panel = nodes.get("hand_display_panel")
	hand_container = nodes.get("hand_container")
	card_count_label = nodes.get("card_count_label")
	_setup_card_icon_button()
	if card_icon_button:
		card_icon_button.pressed.connect(_on_card_icon_pressed)

func _setup_card_icon_button() -> void:
	if not card_icon_button:
		return
	var card_icon := card_icon_button.get_node_or_null("CardIcon")
	if card_icon and card_icon is TextureRect:
		var cardback_frames: SpriteFrames = load("res://assets/cardback.pxo")
		if cardback_frames and cardback_frames.has_animation("default"):
			var frame_count := cardback_frames.get_frame_count("default")
			if frame_count > 0:
				card_icon.texture = cardback_frames.get_frame_texture("default", 0)

func _on_card_icon_pressed() -> void:
	is_hand_visible = !is_hand_visible
	update_card_count()
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

func _on_hand_card_gui_input(event: InputEvent, card_path: String, frame_index: int) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and mb.double_click:
			if not card_path.is_empty() and CardEnlargeOverlay:
				CardEnlargeOverlay.show_enlarged_card(card_path, frame_index)
			get_viewport().set_input_as_handled()

func _populate_hand_display() -> void:
	if not hand_container:
		return
	for child in hand_container.get_children():
		child.queue_free()
	for card_data in App.player_card_collection:
		var card_visual := TextureRect.new()
		card_visual.expand_mode = TextureRect.EXPAND_FIT_HEIGHT_PROPORTIONAL
		card_visual.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		# Make hand cards larger for better readability (3x previous size).
		card_visual.custom_minimum_size = Vector2(240, 360)
		card_visual.mouse_filter = Control.MOUSE_FILTER_STOP
		var sprite_frames_path: String = card_data.get("path", "")
		var frame_index: int = int(card_data.get("frame", 0))
		if not sprite_frames_path.is_empty():
			var sprite_frames: SpriteFrames = load(sprite_frames_path)
			if sprite_frames and sprite_frames.has_animation("default"):
				var frame_count := sprite_frames.get_frame_count("default")
				if frame_count > frame_index:
					card_visual.texture = sprite_frames.get_frame_texture("default", frame_index)
		card_visual.gui_input.connect(_on_hand_card_gui_input.bind(sprite_frames_path, frame_index))
		hand_container.add_child(card_visual)

func update_card_count() -> void:
	if not card_count_label:
		return
	var count := App.player_card_collection.size()
	card_count_label.text = str(count)
	card_count_label.visible = card_icon_button != null and card_icon_button.visible

func show_card_icon_button() -> void:
	if card_icon_button and App.player_card_collection.size() > 0:
		card_icon_button.visible = true
		card_icon_button.modulate.a = 0.0
		var tween := create_tween()
		tween.tween_property(card_icon_button, "modulate:a", 1.0, 0.3)
		update_card_count()

extends Node2D

## Manages card dragging functionality
## Cards can be clicked and dragged, but cannot leave the screen bounds

var dragged_card: Node2D = null
var drag_offset: Vector2 = Vector2.ZERO
var dragging_enabled: bool = true
var screen_bounds: Rect2
var hovered_card: Node2D = null
var card_original_scales: Dictionary = {}  # Store original scales for each card
var card_spawn_positions: Dictionary = {}  # Store original spawn positions for each card
var hover_scale: float = 1.15  # Scale factor when hovering (15% larger)
var snapped_cards: Dictionary = {}  # Track which cards are snapped to slots (card -> slot)
var dragged_from_slot: Node2D = null  # Slot the card was in when drag started (for swap-on-drop)

# Double-click enlarge feature
var enlarged_card: Node2D = null  # Currently enlarged card (if any)
var darkening_overlay: ColorRect = null  # Darkening overlay for enlarged view
var overlay_canvas_layer: CanvasLayer = null  # Canvas layer for overlay
var last_click_time: float = 0.0  # Time of last click for double-click detection
var last_clicked_card: Node2D = null  # Last clicked card for double-click detection
var double_click_timeout: float = 0.3  # Max time between clicks for double-click (seconds)
var enlarged_scale: float = 3.0  # Scale factor when card is enlarged
var card_enlarged_state: Dictionary = {}  # Store original state when enlarged (position, scale, parent, z_index)

signal card_drag_started(card: Node2D)
signal card_drag_ended(card: Node2D)
signal card_snapped_to_slot(card: Node2D, slot: Node2D)

func _ready():
	# Calculate screen bounds
	_update_screen_bounds()
	
	# Connect to viewport size changes
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	
	# Create darkening overlay for enlarged card view
	_create_darkening_overlay()
	
	# Wait a frame for all nodes to be ready
	await get_tree().process_frame
	# Find all cards and connect their input events
	_setup_cards()

func _on_viewport_size_changed():
	_update_screen_bounds()
	# Update overlay size if it exists
	if darkening_overlay:
		var viewport = get_viewport()
		if viewport:
			var size = viewport.get_visible_rect().size
			darkening_overlay.size = size
			var overlay_container = darkening_overlay.get_parent()
			if overlay_container:
				overlay_container.size = size

func _update_screen_bounds():
	var viewport = get_viewport()
	if viewport:
		var size = viewport.get_visible_rect().size
		screen_bounds = Rect2(Vector2.ZERO, size)

func _setup_cards():
	# Get the parent scene (CardBattle) to find all card instances
	var parent_scene = get_parent()
	if not parent_scene:
		return
	
	# Find all Card instances in the scene
	for child in parent_scene.get_children():
		# Check if it's a Card instance (has Card script or is an instance of card.tscn)
		if child != self:  # Don't process ourselves
			var card_script = child.get_script()
			if card_script and card_script.resource_path == "res://scripts/Card.gd":
				register_card(child)

func register_card(card: Node2D) -> void:
	"""Public method to register a card with the CardManager.
	Can be called by other systems (like Deck) when spawning cards dynamically."""
	if not card:
		return
	# Record the card's spawn position the first time it is registered.
	if not card_spawn_positions.has(card):
		card_spawn_positions[card] = card.global_position
	_connect_card(card)

func set_card_spawn_position(card: Node2D, pos: Vector2) -> void:
	"""Update a card's spawn position (used when returning cards to hand)."""
	if card:
		card_spawn_positions[card] = pos

func _connect_card(card: Node2D):
	# Store original scale
	if not card_original_scales.has(card):
		card_original_scales[card] = card.scale
	
	# Find the Area2D collision node
	var area = card.get_node_or_null("Card_Collision")
	if area and area is Area2D:
		# Enable input detection
		area.input_pickable = true
		# Connect input event (only if not already connected)
		if not area.input_event.is_connected(_on_card_input_event):
			area.input_event.connect(_on_card_input_event.bind(card))
		# Connect mouse enter/exit for hover effects (only if not already connected)
		if not area.mouse_entered.is_connected(_on_card_mouse_entered):
			area.mouse_entered.connect(_on_card_mouse_entered.bind(card))
		if not area.mouse_exited.is_connected(_on_card_mouse_exited):
			area.mouse_exited.connect(_on_card_mouse_exited.bind(card))

func _on_card_input_event(_viewport: Node, event: InputEvent, _shape_idx: int, card: Node2D):
	# Don't process input if card is currently enlarged
	if enlarged_card == card:
		return
	
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				# Check for double-click
				var current_time = Time.get_ticks_msec() / 1000.0
				var is_double_click = (card == last_clicked_card) and (current_time - last_click_time < double_click_timeout)
				
				if is_double_click:
					# Double-click detected - enlarge card
					_enlarge_card(card)
					last_click_time = 0.0  # Reset to prevent triple-click issues
					last_clicked_card = null
				else:
					# Single click - start drag as normal (only if dragging is enabled)
					if not dragging_enabled:
						return
					last_click_time = current_time
					last_clicked_card = card
					# If card is snapped, remember its slot for possible swap, then unsnap
					if snapped_cards.has(card):
						dragged_from_slot = snapped_cards[card]
						_unsnap_card(card)
					else:
						dragged_from_slot = null
					_start_drag(card, get_global_mouse_position())
			else:
				_end_drag()

func disable_dragging() -> void:
	"""Disables starting new drags for all cards."""
	dragging_enabled = false

func _on_card_mouse_entered(card: Node2D):
	# Don't hover effect if card is being dragged
	if card == dragged_card:
		return
	
	hovered_card = card
	_scale_card_up(card)

func _on_card_mouse_exited(card: Node2D):
	# Don't scale down if card is being dragged
	if card == dragged_card:
		return
	
	if hovered_card == card:
		hovered_card = null
	_scale_card_down(card)

func _scale_card_up(card: Node2D):
	# Get original scale
	var original_scale = card_original_scales.get(card, Vector2.ONE)
	var target_scale = original_scale * hover_scale
	
	# Create tween for smooth scaling
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_BACK)
	tween.tween_property(card, "scale", target_scale, 0.2)

func _scale_card_down(card: Node2D):
	# Get original scale
	var original_scale = card_original_scales.get(card, Vector2.ONE)
	
	# Create tween for smooth scaling
	var tween = create_tween()
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_BACK)
	tween.tween_property(card, "scale", original_scale, 0.2)

func _start_drag(card: Node2D, mouse_pos: Vector2):
	# Don't allow dragging if card is enlarged
	if enlarged_card == card:
		return
	if dragged_card:
		return
	
	dragged_card = card
	# Calculate offset from card center to mouse position
	var card_pos = card.global_position
	drag_offset = card_pos - mouse_pos
	
	# Scale down hover effect if card was hovered
	if hovered_card == card:
		hovered_card = null
		_scale_card_down(card)
	
	# Bring card to front (move to end of parent's children list)
	var parent = card.get_parent()
	if parent:
		parent.move_child(card, -1)
	
	card_drag_started.emit(card)

func _end_drag():
	if dragged_card:
		var card = dragged_card
		var card_pos = card.global_position
		
		# Check if card should snap to a nearby slot
		var nearest_slot: Node2D = _find_nearest_slot(card_pos)
		var did_snap := false
		if nearest_slot:
			var target_occupied: bool = nearest_slot.get("has_card") == true and nearest_slot.get("snapped_card") != null
			# If target slot has another card and we came from a slot, trade positions
			if target_occupied and dragged_from_slot != null and is_instance_valid(dragged_from_slot):
				var other_card: Node2D = nearest_slot.snapped_card
				if other_card and is_instance_valid(other_card):
					# Put our card into the target slot (displaces other_card)
					nearest_slot.force_snap_card(card)
					snapped_cards[card] = nearest_slot
					snapped_cards.erase(other_card)
					if card_original_scales.has(card):
						card.scale = card_original_scales[card]
					card_snapped_to_slot.emit(card, nearest_slot)
					# Put the displaced card into our previous slot
					_snap_card_to_slot(other_card, dragged_from_slot)
					did_snap = true
			if not did_snap:
				_snap_card_to_slot(card, nearest_slot)
				did_snap = snapped_cards.has(card)
		else:
			# Unsnap if card was previously snapped but moved away
			if snapped_cards.has(card):
				_unsnap_card(card)
		
		# If the card did not end up in a slot, return it to its original spawn position.
		if not did_snap and card_spawn_positions.has(card):
			var spawn_pos: Vector2 = card_spawn_positions[card]
			var tween := create_tween()
			tween.set_ease(Tween.EASE_OUT)
			tween.set_trans(Tween.TRANS_CUBIC)
			tween.tween_property(card, "global_position", spawn_pos, 0.25)
		
		card_drag_ended.emit(card)
		dragged_card = null
		drag_offset = Vector2.ZERO
		dragged_from_slot = null

func _process(_delta):
	# Don't process dragging if card is enlarged
	if not enlarged_card:
		if dragged_card:
			# Get mouse position in world space
			var mouse_pos = get_global_mouse_position()
			
			# Calculate desired position
			var desired_pos = mouse_pos + drag_offset
			
			# Get card size for bounds checking
			var card_size = _get_card_size(dragged_card)
			
			# Clamp position to screen bounds
			var half_size = card_size / 2.0
			desired_pos.x = clamp(desired_pos.x, half_size.x, screen_bounds.size.x - half_size.x)
			desired_pos.y = clamp(desired_pos.y, half_size.y, screen_bounds.size.y - half_size.y)
			
			# Update card position
			dragged_card.global_position = desired_pos
		
		# Keep snapped cards in place (only if not being dragged)
		for card in snapped_cards.keys():
			if is_instance_valid(card) and is_instance_valid(snapped_cards[card]):
				# Don't lock position if card is being dragged
				if card != dragged_card:
					var slot = snapped_cards[card]
					card.global_position = slot.global_position

func _get_card_size(card: Node2D) -> Vector2:
	# Try to get size from Card script if it has the method
	if card.has_method("_get_card_size"):
		return card._get_card_size()
	
	# Fallback: try to get from collision shape
	var area = card.get_node_or_null("Card_Collision")
	if area:
		var collision = area.get_node_or_null("Card_Area")
		if collision and collision.shape is RectangleShape2D:
			var shape = collision.shape as RectangleShape2D
			return shape.size
	
	# Default size if we can't determine
	return Vector2(64, 96)

func _find_nearest_slot(card_pos: Vector2) -> Node2D:
	"""Finds the nearest slot to the given position within snap distance."""
	var parent_scene = get_parent()
	if not parent_scene:
		return null
	
	var nearest_slot: Node2D = null
	var nearest_distance: float = INF
	
	# Find all CardSlot instances recursively
	var all_slots = _find_all_slots(parent_scene)
	
	for slot in all_slots:
		if slot == self:
			continue
		
		if slot.has_method("is_card_nearby") and slot.has_method("snap_card"):
			# Check if slot can snap using a method call (more reliable than property access)
			if slot.has_method("can_snap_cards"):
				if not slot.can_snap_cards():
					continue  # Skip this slot if snapping is disabled
			else:
				# Fallback: try to access property directly
				var can_snap_value = slot.get("can_snap")
				# Only skip if explicitly false (not null or true)
				if can_snap_value == false:
					continue
			
			if slot.is_card_nearby(card_pos):
				var distance = card_pos.distance_to(slot.global_position)
				if distance < nearest_distance:
					nearest_distance = distance
					nearest_slot = slot
	
	return nearest_slot

func _find_all_slots(parent: Node) -> Array:
	"""Recursively finds all CardSlot instances in the scene."""
	var slots: Array = []
	
	for child in parent.get_children():
		var slot_script = child.get_script()
		if slot_script and slot_script.resource_path == "res://scripts/CardSlot.gd":
			slots.append(child)
		
		# Recursively search children
		var child_slots = _find_all_slots(child)
		slots.append_array(child_slots)
	
	return slots

func _snap_card_to_slot(card: Node2D, slot: Node2D):
	"""Snaps a card to a slot and makes it stationary."""
	if slot.has_method("snap_card"):
		if slot.snap_card(card):
			snapped_cards[card] = slot
			
			# Don't disconnect input events - allow cards to be removed by dragging
			# The card will still be kept in place by _process, but can be dragged to unsnap
			
			# Restore original scale
			if card_original_scales.has(card):
				card.scale = card_original_scales[card]
			
			card_snapped_to_slot.emit(card, slot)

func _unsnap_card(card: Node2D):
	"""Removes a card from its slot and allows it to be dragged again."""
	if snapped_cards.has(card):
		var slot = snapped_cards[card]
		if is_instance_valid(slot) and slot.has_method("unsnap_card"):
			slot.unsnap_card()
		
		snapped_cards.erase(card)
		
		# Reconnect card input events
		_connect_card(card)

func _create_darkening_overlay() -> void:
	"""Creates a semi-transparent dark overlay for the enlarged card view."""
	var canvas_layer = CanvasLayer.new()
	canvas_layer.name = "EnlargedCardOverlay"
	canvas_layer.layer = 100  # High layer to appear above everything
	
	# Create a Control node to hold the overlay
	var overlay_container = Control.new()
	overlay_container.name = "OverlayContainer"
	overlay_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay_container.mouse_filter = Control.MOUSE_FILTER_STOP  # Capture clicks
	
	darkening_overlay = ColorRect.new()
	darkening_overlay.name = "DarkeningOverlay"
	darkening_overlay.color = Color(0, 0, 0, 0.7)  # Semi-transparent black
	darkening_overlay.mouse_filter = Control.MOUSE_FILTER_STOP  # Capture clicks
	
	# Make overlay cover entire screen
	var viewport = get_viewport()
	if viewport:
		var size = viewport.get_visible_rect().size
		darkening_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		darkening_overlay.size = size
	
	# Connect click to close
	if not darkening_overlay.gui_input.is_connected(_on_overlay_clicked):
		darkening_overlay.gui_input.connect(_on_overlay_clicked)
	if not overlay_container.gui_input.is_connected(_on_overlay_clicked):
		overlay_container.gui_input.connect(_on_overlay_clicked)
	
	overlay_container.add_child(darkening_overlay)
	canvas_layer.add_child(overlay_container)
	add_child(canvas_layer)
	darkening_overlay.visible = false
	overlay_container.visible = false

func _on_overlay_clicked(event: InputEvent) -> void:
	"""Handle clicks on the darkening overlay to close enlarged card."""
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			_restore_enlarged_card()

func _enlarge_card(card: Node2D) -> void:
	"""Enlarge a card to full screen view with darkening overlay."""
	if not card or not is_instance_valid(card):
		return
	
	# Unsnap card if it's snapped
	if snapped_cards.has(card):
		_unsnap_card(card)
	
	# Store original state
	var original_scale = card.scale
	var original_position = card.global_position
	var original_parent = card.get_parent()
	var original_z_index = 0
	if card is Node2D:
		original_z_index = card.z_index
	
	card_enlarged_state[card] = {
		"scale": original_scale,
		"position": original_position,
		"parent": original_parent,
		"z_index": original_z_index
	}
	
	# Stop any dragging
	if dragged_card == card:
		dragged_card = null
		drag_offset = Vector2.ZERO
	
	# Remove hover effect
	if hovered_card == card:
		hovered_card = null
		_scale_card_down(card)
	
	# Move card to a high layer - create a Node2D container in the overlay layer
	var overlay_layer = get_node_or_null("EnlargedCardOverlay")
	if overlay_layer:
		# Create a Node2D container for the card (since cards are Node2D, not Control)
		var card_container = Node2D.new()
		card_container.name = "EnlargedCardContainer"
		overlay_layer.add_child(card_container)
		
		# Convert global position to local position before reparenting
		var global_pos = card.global_position
		original_parent.remove_child(card)
		card_container.add_child(card)
		# Set position relative to container (which is in world space)
		card.global_position = global_pos
		if card is Node2D:
			card.z_index = 1000  # Very high z-index
		
		# Store container reference for cleanup
		card_enlarged_state[card]["container"] = card_container
	
	# Calculate center position (in global coordinates)
	var viewport = get_viewport()
	var center_pos = Vector2.ZERO
	if viewport:
		var size = viewport.get_visible_rect().size
		center_pos = size / 2.0
	
	# Calculate enlarged scale
	var base_scale = card_original_scales.get(card, Vector2.ONE)
	var target_scale = base_scale * enlarged_scale
	
	# Animate to center and scale up
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(card, "global_position", center_pos, 0.3)
	tween.tween_property(card, "scale", target_scale, 0.3)
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	
	# Show darkening overlay
	if darkening_overlay:
		darkening_overlay.visible = true
		# Update overlay size in case viewport changed
		if viewport:
			var size = viewport.get_visible_rect().size
			darkening_overlay.size = size
		# Show overlay container
		var overlay_container = darkening_overlay.get_parent()
		if overlay_container:
			overlay_container.visible = true
	
	enlarged_card = card
	
	# Disable card input while enlarged
	var area = card.get_node_or_null("Card_Collision")
	if area:
		area.input_pickable = false

func _restore_enlarged_card() -> void:
	"""Restore the enlarged card to its original state."""
	if not enlarged_card or not is_instance_valid(enlarged_card):
		return
	
	var card = enlarged_card
	var state = card_enlarged_state.get(card, {})
	
	if state.is_empty():
		# Fallback restoration
		enlarged_card = null
		if darkening_overlay:
			darkening_overlay.visible = false
		return
	
	var original_parent = state.get("parent", null)
	var original_position = state.get("position", Vector2.ZERO)
	var original_scale = state.get("scale", Vector2.ONE)
	
	# Animate back to original position and scale
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(card, "global_position", original_position, 0.3)
	tween.tween_property(card, "scale", original_scale, 0.3)
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_CUBIC)
	
	await tween.finished
	
	# Reparent card back to original parent
	var current_parent = card.get_parent()
	if current_parent and original_parent and current_parent != original_parent:
		# Preserve global position during reparent
		var global_pos = card.global_position
		current_parent.remove_child(card)
		original_parent.add_child(card)
		card.global_position = global_pos
		
		# Clean up container if it exists
		var container = state.get("container", null)
		if container and is_instance_valid(container):
			container.queue_free()
	
	# Restore z-index
	if card is Node2D:
		card.z_index = state.get("z_index", 0)
	
	# Re-enable card input
	var area = card.get_node_or_null("Card_Collision")
	if area:
		area.input_pickable = true
	
	# Hide overlay
	if darkening_overlay:
		darkening_overlay.visible = false
		var overlay_container = darkening_overlay.get_parent()
		if overlay_container:
			overlay_container.visible = false
	
	# Clear state
	card_enlarged_state.erase(card)
	enlarged_card = null


# --- Methods moved from BattleManager (card/hand/snap/attribute UI) ---

func respace_hand_cards() -> void:
	## Re-space all cards in the hand evenly whenever hand size changes.
	var hand_cards: Array = []
	for card in card_spawn_positions:
		if not snapped_cards.has(card):
			if is_instance_valid(card):
				hand_cards.append(card)
	if hand_cards.is_empty():
		return
	var viewport := get_viewport()
	if not viewport:
		return
	var viewport_size := viewport.get_visible_rect().size
	var y := viewport_size.y * 0.9
	var n := hand_cards.size()
	for i in range(n):
		var card = hand_cards[i]
		if not is_instance_valid(card) or not is_instance_of(card, Node2D) or not card.is_inside_tree():
			continue
		var t := float(i + 1) / float(n + 1)
		var x := viewport_size.x * t
		var new_pos := Vector2(x, y)
		set_card_spawn_position(card, new_pos)
		if dragged_card == card:
			continue
		var tween_instance := create_tween()
		if tween_instance:
			tween_instance.set_ease(Tween.EASE_OUT)
			tween_instance.set_trans(Tween.TRANS_CUBIC)
			tween_instance.tween_property(card, "global_position", new_pos, 0.25)


func get_card_size_for_indicator(card: Node) -> Vector2:
	if card.get("card_size"):
		var s: Variant = card.get("card_size")
		if s is Vector2:
			return s
	var img := card.get_node_or_null("Card_Image") as Sprite2D
	if img and img.texture:
		return img.texture.get_size() * img.scale
	return Vector2(100, 140)


func get_card_attribute(card: Node, attribute_config: Resource) -> String:
	if card == null:
		return "unknown"
	if attribute_config == null or not attribute_config.has_method("get_attribute"):
		return "unknown"
	var frames: SpriteFrames = card.get("card_sprite_frames")
	var fidx: int = int(card.get("frame_index"))
	return String(attribute_config.call("get_attribute", frames, fidx))


func get_attribute_from_path(path: String, attribute_config: Resource) -> String:
	if path.is_empty():
		return "unknown"
	var sf: SpriteFrames = load(path) as SpriteFrames
	if sf == null:
		return "unknown"
	if attribute_config and attribute_config.has_method("get_attribute"):
		return String(attribute_config.call("get_attribute", sf, 0))
	return "unknown"


func _get_player_attribute_matchup(player_card: Node, opponent_card: Node, attribute_config: Resource) -> String:
	var pa := get_card_attribute(player_card, attribute_config)
	var oa := get_card_attribute(opponent_card, attribute_config)
	if pa == "unknown" or oa == "unknown":
		return "neutral"
	if pa == oa:
		return "neutral"
	var pa_beats = attribute_config.beats.get(pa, null)
	if pa_beats == oa:
		return "advantage"
	var oa_beats = attribute_config.beats.get(oa, null)
	if oa_beats == pa:
		return "disadvantage"
	return "neutral"


func add_attribute_indicators(
	player_slot_nodes: Array,
	opponent_slot_nodes: Array,
	attribute_config: Resource,
	font_scale: float,
	indicator_offset: Vector2
) -> void:
	if attribute_config == null or not attribute_config.has_method("get_attribute"):
		return
	var player_indices := [2, 1, 0]
	var opponent_indices := [0, 1, 2]
	var pair_count: int = min(
		min(player_indices.size(), opponent_indices.size()),
		min(player_slot_nodes.size(), opponent_slot_nodes.size())
	)
	for pair_idx in range(pair_count):
		var p_index: int = player_indices[pair_idx]
		var o_index: int = opponent_indices[pair_idx]
		if p_index >= player_slot_nodes.size() or o_index >= opponent_slot_nodes.size():
			continue
		var pslot = player_slot_nodes[p_index]
		var oslot = opponent_slot_nodes[o_index]
		if not pslot:
			continue
		var card = pslot.snapped_card if pslot.get("snapped_card") else null
		if not card or not is_instance_valid(card):
			continue
		var ocard: Node = oslot.snapped_card if oslot and oslot.get("snapped_card") else null
		var matchup := _get_player_attribute_matchup(card, ocard, attribute_config)
		if matchup == "neutral":
			continue
		var existing_panel: Node = card.get_node_or_null("AttributeIndicator")
		if existing_panel:
			existing_panel.queue_free()
		var text := "+1" if matchup == "advantage" else "-1"
		var card_size := get_card_size_for_indicator(card)
		var font_size := int(card_size.y * font_scale)
		if font_size < 8:
			font_size = 8
		var label_size := Vector2(maxi(font_size * 2, 40), maxi(font_size + 8, 32))
		var glow_padding := 0.5
		var panel_size := label_size + Vector2(glow_padding * 2, glow_padding * 2)
		var style := StyleBoxFlat.new()
		style.bg_color = Color(1.0, 1.0, 0.95, 0.55)
		style.corner_radius_top_left = 8
		style.corner_radius_top_right = 8
		style.corner_radius_bottom_left = 8
		style.corner_radius_bottom_right = 8
		style.shadow_color = Color(1.0, 1.0, 0.85, 0.5)
		style.shadow_size = 3
		style.shadow_offset = Vector2.ZERO
		var panel := Panel.new()
		panel.name = "AttributeIndicator"
		panel.add_theme_stylebox_override("panel", style)
		panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
		panel.size = panel_size
		panel.position = indicator_offset - panel_size / 2.0
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(panel)
		var label := Label.new()
		label.name = "Label"
		label.text = text
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", font_size)
		label.add_theme_color_override("font_color", Color.BLACK)
		label.set_anchors_preset(Control.PRESET_TOP_LEFT)
		label.size = label_size
		label.position = Vector2(glow_padding, glow_padding)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(label)


func auto_snap_dragged_card() -> void:
	## If the player is dragging a card when the timer expires, force it into the nearest available slot.
	if dragged_card == null:
		return
	var card: Node2D = dragged_card
	var card_pos: Vector2 = card.global_position
	var root: Node = get_parent()
	if root == null:
		root = get_tree().current_scene
	var nearest_slot: Node2D = null
	var nearest_distance: float = INF
	var all_slots: Array = _find_all_slots(root)
	for slot in all_slots:
		if slot == null or not is_instance_valid(slot):
			continue
		if slot.has_method("can_snap_cards") and not slot.can_snap_cards():
			continue
		if "has_card" in slot and slot.has_card:
			continue
		var distance := card_pos.distance_to(slot.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_slot = slot
	if nearest_slot:
		_snap_card_to_slot(card, nearest_slot)
	dragged_card = null
	drag_offset = Vector2.ZERO


func request_debug_add_card(card_scene: PackedScene) -> void:
	## Debug: add a random card to hand and respace. Called when debug button is pressed.
	if not card_scene:
		return
	App.add_card_from_minigame_win()
	if App.player_card_collection.is_empty():
		return
	var card_data: Dictionary = App.player_card_collection[App.player_card_collection.size() - 1]
	var card_path: String = card_data.get("path", "")
	var frame: int = int(card_data.get("frame"))
	if card_path.is_empty():
		return
	var frames: SpriteFrames = ResourceLoader.load(card_path, "SpriteFrames", ResourceLoader.CACHE_MODE_REUSE) as SpriteFrames
	if not frames:
		return
	var root_node := get_parent()
	if not root_node:
		root_node = get_tree().current_scene
	var hand_container := root_node.get_node_or_null("HandCardsLayer/HandCardsContainer")
	if not hand_container:
		hand_container = root_node
	var card := card_scene.instantiate()
	if not card:
		return
	hand_container.add_child(card)
	card.set("card_sprite_frames", frames)
	card.set("frame_index", frame)
	register_card(card)
	var viewport := get_viewport()
	if viewport:
		var viewport_size := viewport.get_visible_rect().size
		card.global_position = Vector2(viewport_size.x * 0.5, viewport_size.y * 0.9)
	call_deferred("respace_hand_cards")


func _input(event: InputEvent):
	# Handle click to close enlarged card
	if enlarged_card and event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			# Click anywhere to close enlarged view
			_restore_enlarged_card()
			return
	
	# Handle mouse release even if not over a card
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and not mouse_event.pressed:
			if dragged_card:
				_end_drag()

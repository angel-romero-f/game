extends Node2D

## Manages card dragging functionality
## Cards can be clicked and dragged, but cannot leave the screen bounds

var dragged_card: Node2D = null
var drag_offset: Vector2 = Vector2.ZERO
var screen_bounds: Rect2
var hovered_card: Node2D = null
var card_original_scales: Dictionary = {}  # Store original scales for each card
var card_spawn_positions: Dictionary = {}  # Store original spawn positions for each card
var hover_scale: float = 1.15  # Scale factor when hovering (15% larger)
var snapped_cards: Dictionary = {}  # Track which cards are snapped to slots (card -> slot)

signal card_drag_started(card: Node2D)
signal card_drag_ended(card: Node2D)
signal card_snapped_to_slot(card: Node2D, slot: Node2D)

func _ready():
	# Calculate screen bounds
	_update_screen_bounds()
	
	# Connect to viewport size changes
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	
	# Wait a frame for all nodes to be ready
	await get_tree().process_frame
	# Find all cards and connect their input events
	_setup_cards()

func _on_viewport_size_changed():
	_update_screen_bounds()

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
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				# If card is snapped, unsnap it first
				if snapped_cards.has(card):
					_unsnap_card(card)
				_start_drag(card, get_global_mouse_position())
			else:
				_end_drag()

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
		var nearest_slot = _find_nearest_slot(card_pos)
		var did_snap := false
		if nearest_slot:
			_snap_card_to_slot(card, nearest_slot)
			did_snap = true
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

func _process(_delta):
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

func _input(event: InputEvent):
	# Handle mouse release even if not over a card
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and not mouse_event.pressed:
			if dragged_card:
				_end_drag()

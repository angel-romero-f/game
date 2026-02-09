@tool
class_name TerritoryNode
extends Control

## TerritoryNode
## Represents a territory region on the map using Control + Polygon2D.
## Links a Territory data object to a visual/interactive polygon area.
## No gameplay logic - only map ↔ territory linkage.

## Reference to the Territory data object
var territory_data: Territory = null

## Adjacent TerritoryNode references (for easy traversal)
var adjacent_nodes: Array[TerritoryNode] = []

## Signals
signal territory_selected(territory_id: int)
signal card_placed(territory_id: int, player_id: int)

## Visual representation (optional - can be set in editor)
@export var territory_name: String = ""

## Whether this territory is currently selected/highlighted
var is_selected: bool = false

## Polygon points that define the territory shape (matches gray outline)
## Set this in the editor by clicking "Edit Polygon Points" or manually entering coordinates
var _polygon_points_backing: PackedVector2Array = []
@export var polygon_points: PackedVector2Array:
	set(value):
		_polygon_points_backing = value.duplicate()
		original_polygon_points = value.duplicate()
		# In editor, don't run _update_size_from_polygon() - it sets size and can cause NOTIFICATION_RESIZED re-entry (stack underflow)
		if is_inside_tree() and not Engine.is_editor_hint():
			_update_size_from_polygon()
		# Defer redraw in editor so we don't draw in same stack as setter (avoids engine stack underflow)
		if Engine.is_editor_hint():
			call_deferred("queue_redraw")
		else:
			queue_redraw()
	get:
		return _polygon_points_backing

## Territory ID (should match the Territory data object)
@export var territory_id_override: int = -1

## Region ID (can be set in editor, will override Territory data if set)
@export var region_id_override: int = -1

## Current display state
var current_color: Color = Color(0, 0, 0, 0)  # Transparent by default
var glow_color: Color = Color(0, 0, 0, 0)  # Glow effect color

## Colors
var base_color: Color = Color(1.0, 1.0, 1.0, 0.3)  # More visible for debugging
var hover_color: Color = Color(1.0, 1.0, 0.0, 0.4)  # Yellow glow on hover
var selected_color: Color = Color(0.0, 1.0, 1.0, 0.5)  # Cyan glow when selected
var glow_width: float = 8.0  # Width of glow outline

## Debug: Make territories more visible
@export var debug_visible: bool = true  # Set to false to hide territories when not hovering

## When claimed, polygon is tinted with this color (set by update_claimed_visual from owner's race)
var claimed_display_color: Color = Color(0, 0, 0, 0)

## Editor: When true, size changes will update polygon to a rectangle (0,0) to (size.x, size.y)
@export var editor_sync_rect_to_size: bool = true

## Store original polygon points before adjustment
var original_polygon_points: PackedVector2Array = []


func _ready() -> void:
	if Engine.is_editor_hint():
		# Defer layout change to avoid re-entry during _ready (can cause stack underflow)
		call_deferred("set_anchors_preset", Control.PRESET_TOP_LEFT)
		queue_redraw()
		return
	
	# Enable mouse input
	mouse_filter = MOUSE_FILTER_STOP
	
	# If territory_id_override is set but no territory_data exists, create it
	if territory_id_override != -1 and not territory_data:
		var region_id := region_id_override if region_id_override != -1 else 1
		territory_data = Territory.new(territory_id_override, region_id, null, [])
		territory_name = "Territory %d" % territory_id_override
		print("[TerritoryNode] Auto-created Territory data for ID %d" % territory_id_override)
	
	# Connect mouse events
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	
	# Set initial color
	current_color = base_color
	
	# Initialize backing variable if needed
	if _polygon_points_backing.is_empty() and not polygon_points.is_empty():
		_polygon_points_backing = polygon_points.duplicate()
	
	# Store original polygon points before any adjustments
	if not _polygon_points_backing.is_empty():
		original_polygon_points = _polygon_points_backing.duplicate()
	
	# Ensure we have polygon points
	if _polygon_points_backing.is_empty():
		push_warning("TerritoryNode '%s' has no polygon_points. Territory will not be visible." % name)
	else:
		# Update size to contain polygon (this may adjust polygon_points)
		_update_size_from_polygon()
	
	# Ensure Control has a minimum size
	if size.x <= 0 or size.y <= 0:
		size = Vector2(200, 150)
		push_warning("TerritoryNode '%s' has invalid size, setting default" % name)
	
	# Queue redraw
	queue_redraw()
	
	# Debug print
	if not _polygon_points_backing.is_empty():
		print("[TerritoryNode] '%s' ready with %d polygon points, size: %s, position: %s" % [name, _polygon_points_backing.size(), size, position])


func _update_size_from_polygon() -> void:
	var points_to_check := _polygon_points_backing if not _polygon_points_backing.is_empty() else original_polygon_points
	if points_to_check.is_empty():
		return
	
	# Use original points if available, otherwise use current points
	var points_to_use := original_polygon_points if not original_polygon_points.is_empty() else points_to_check
	
	var min_x := INF
	var min_y := INF
	var max_x := -INF
	var max_y := -INF
	
	for point in points_to_use:
		min_x = min(min_x, point.x)
		min_y = min(min_y, point.y)
		max_x = max(max_x, point.x)
		max_y = max(max_y, point.y)
	
	# Set size to contain polygon with padding for glow
	var padding := glow_width + 5.0
	var calculated_size := Vector2(max_x - min_x + padding * 2, max_y - min_y + padding * 2)
	
	# Only update size if it's not already set or is too small
	if size.x < calculated_size.x or size.y < calculated_size.y:
		size = calculated_size
	
	# Adjust polygon points to be relative to Control's origin (only if needed)
	# Check if points are already relative to origin (all >= 0)
	var needs_adjustment := false
	for point in points_to_use:
		if point.x < 0 or point.y < 0:
			needs_adjustment = true
			break
	
	if needs_adjustment:
		var adjusted_points := PackedVector2Array()
		for point in points_to_use:
			adjusted_points.append(point - Vector2(min_x - padding, min_y - padding))
		_polygon_points_backing = adjusted_points
	else:
		# Points are already relative to origin, use them as-is
		_polygon_points_backing = points_to_use.duplicate()


func _draw() -> void:
	# In editor: always draw the polygon so you can see where it is
	if Engine.is_editor_hint():
		_draw_editor_preview()
		return
	
	# Draw the territory polygon shape
	var points_to_draw := _polygon_points_backing if not _polygon_points_backing.is_empty() else original_polygon_points
	if points_to_draw.size() < 3:
		# Draw a debug rectangle if no polygon points
		if debug_visible:
			draw_rect(Rect2(0, 0, size.x, size.y), Color(1, 0, 0, 0.3), false, 2.0)
		return
	
	# Draw glow effect (outline) - shown on hover/select
	if glow_color.a > 0:
		# Draw multiple outlines for glow effect
		for i in range(3):
			var glow_points := PackedVector2Array()
			var center := _calculate_center(points_to_draw)
			var offset := glow_width * (i + 1) / 3.0
			for point in points_to_draw:
				var direction := (point - center).normalized()
				glow_points.append(point + direction * offset)
			draw_colored_polygon(glow_points, glow_color)
	
	# Draw main polygon (claimed = race color; unclaimed = white transparent glow)
	if is_claimed() and claimed_display_color.a > 0:
		var fill := claimed_display_color
		fill.a = 0.5
		draw_colored_polygon(points_to_draw, fill)
		draw_polyline(points_to_draw, claimed_display_color, 3.0, true)
	elif debug_visible:
		# Unclaimed: white transparent glow
		var unclaimed_color := Color(1.0, 1.0, 1.0, 0.35)
		draw_colored_polygon(points_to_draw, unclaimed_color)
		draw_polyline(points_to_draw, Color(1.0, 1.0, 1.0, 0.7), 2.0, true)
	elif current_color.a > 0:
		# Normal drawing when not in debug mode
		draw_colored_polygon(points_to_draw, current_color)
		draw_polyline(points_to_draw, Color(0.5, 0.5, 0.5, 0.3), 2.0, true)


func _draw_editor_preview() -> void:
	# Draw in editor so you can see the territory shape on the map
	var points_to_draw := _polygon_points_backing if not _polygon_points_backing.is_empty() else original_polygon_points
	
	if points_to_draw.size() >= 3:
		# Draw filled polygon (semi-transparent cyan so it's visible on map)
		draw_colored_polygon(points_to_draw, Color(0.2, 0.8, 1.0, 0.35))
		# Draw outline
		draw_polyline(points_to_draw, Color(0.0, 0.6, 1.0, 0.9), 2.0, true)
		# Draw vertex handles
		for i in range(points_to_draw.size()):
			var p := points_to_draw[i]
			draw_circle(p, 4.0, Color(1.0, 1.0, 0.0, 0.9))
			draw_arc(p, 4.0, 0, TAU, 8, Color(0, 0, 0, 0.8), 1.0)
	else:
		# No polygon yet: draw the control's rect so you can position/size it
		var w: float = 200.0
		var h: float = 150.0
		if size.x > 0:
			w = float(size.x)
		if size.y > 0:
			h = float(size.y)
		var rect := Rect2(0, 0, w, h)
		draw_rect(rect, Color(0.2, 0.8, 1.0, 0.25), false, 2.0)
		draw_rect(rect, Color(0.0, 0.6, 1.0, 0.8), false, 2.0)
		# Hint text would need ThemeDB - skip for now


func _notification(what: int) -> void:
	if not Engine.is_editor_hint():
		return
	if what == NOTIFICATION_RESIZED:
		if editor_sync_rect_to_size:
			# Update backing storage directly to avoid setter -> _update_size_from_polygon() -> size change -> RESIZED re-entry (stack underflow)
			var w := size.x if size.x > 0 else 200.0
			var h := size.y if size.y > 0 else 150.0
			var rect_points := PackedVector2Array([
				Vector2(0, 0),
				Vector2(w, 0),
				Vector2(w, h),
				Vector2(0, h)
			])
			_polygon_points_backing = rect_points.duplicate()
			original_polygon_points = rect_points.duplicate()
		call_deferred("queue_redraw")
	elif what == NOTIFICATION_POST_ENTER_TREE:
		# Defer so we don't trigger layout/resize in the same frame and cause re-entry
		call_deferred("set_anchors_preset", Control.PRESET_TOP_LEFT)
		queue_redraw()


func _calculate_center(points: PackedVector2Array) -> Vector2:
	if points.is_empty():
		return Vector2.ZERO
	
	var sum := Vector2.ZERO
	for point in points:
		sum += point
	return sum / points.size()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			# Check if click is inside polygon
			if _is_point_in_polygon(get_local_mouse_position()):
				_select_territory()


func _is_point_in_polygon(point: Vector2) -> bool:
	# Ray casting algorithm to check if point is inside polygon
	var points_to_check := _polygon_points_backing if not _polygon_points_backing.is_empty() else original_polygon_points
	if points_to_check.size() < 3:
		return false
	
	var inside := false
	var j := points_to_check.size() - 1
	
	for i in range(points_to_check.size()):
		var pi := points_to_check[i]
		var pj := points_to_check[j]
		
		if ((pi.y > point.y) != (pj.y > point.y)) and \
		   (point.x < (pj.x - pi.x) * (point.y - pi.y) / (pj.y - pi.y) + pi.x):
			inside = not inside
		j = i
	
	return inside


func _on_mouse_entered() -> void:
	_show_hover_glow()


func _on_mouse_exited() -> void:
	if not is_selected:
		_hide_glow()


func _show_hover_glow() -> void:
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_method(_set_glow_color, glow_color, hover_color, 0.2)
	tween.tween_method(_set_current_color, current_color, Color(1.0, 1.0, 0.0, 0.15), 0.2)


func _show_selected_glow() -> void:
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_method(_set_glow_color, glow_color, selected_color, 0.2)
	tween.tween_method(_set_current_color, current_color, Color(0.0, 1.0, 1.0, 0.2), 0.2)


func _hide_glow() -> void:
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_method(_set_glow_color, glow_color, Color(0, 0, 0, 0), 0.2)
	tween.tween_method(_set_current_color, current_color, base_color, 0.2)


func _set_glow_color(color: Color) -> void:
	glow_color = color
	queue_redraw()


func _set_current_color(color: Color) -> void:
	current_color = color
	queue_redraw()


## Initialize this node with Territory data
func initialize(territory: Territory) -> void:
	territory_data = territory
	if territory:
		territory_name = "Territory %d" % territory.territory_id
		
		# If territory_id_override is set, create/update territory data
		if territory_id_override != -1:
			if not territory_data or territory_data.territory_id != territory_id_override:
				var region_id := region_id_override if region_id_override != -1 else territory.region_id
				territory_data = Territory.new(territory_id_override, region_id, null, [])
				territory_name = "Territory %d" % territory_id_override


## Set polygon points (should match gray outline shape)
func set_polygon_points(points: PackedVector2Array) -> void:
	polygon_points = points  # This will trigger the setter


## Set polygon to a rectangle matching the current Control size. Call from editor or at runtime.
func set_polygon_to_rect() -> void:
	var w := size.x if size.x > 0 else 200.0
	var h := size.y if size.y > 0 else 150.0
	polygon_points = PackedVector2Array([
		Vector2(0, 0),
		Vector2(w, 0),
		Vector2(w, h),
		Vector2(0, h)
	])
	if Engine.is_editor_hint():
		queue_redraw()


## Set adjacent TerritoryNode references
func set_adjacent_nodes(nodes: Array[TerritoryNode]) -> void:
	adjacent_nodes = nodes.duplicate()


## Add a single adjacent TerritoryNode
func add_adjacent_node(node: TerritoryNode) -> void:
	if node and node not in adjacent_nodes:
		adjacent_nodes.append(node)


## Select this territory (emits signal)
func _select_territory() -> void:
	if not territory_data:
		push_warning("TerritoryNode '%s' has no territory_data. Cannot select." % name)
		return
	
	is_selected = true
	_show_selected_glow()
	territory_selected.emit(territory_data.territory_id)


## Deselect this territory
func deselect() -> void:
	is_selected = false
	_hide_glow()


## Notify that a card was placed (emits signal)
## This should be called by external systems when a card is placed
func notify_card_placed(player_id: int) -> void:
	if not territory_data:
		push_warning("TerritoryNode '%s' has no territory_data. Cannot notify card placement." % name)
		return
	
	card_placed.emit(territory_data.territory_id, player_id)


## Get the territory ID
func get_territory_id() -> int:
	if territory_data:
		return territory_data.territory_id
	return -1


## Get the region ID
func get_region_id() -> int:
	if territory_data:
		return territory_data.region_id
	return -1


## Check if territory is claimed
func is_claimed() -> bool:
	if territory_data:
		return territory_data.is_claimed()
	return false


## Check if territory is contested
func is_contested() -> bool:
	if territory_data:
		return territory_data.is_contested()
	return false


## Update the visual to show claimed state (race color). Call after claim state changes.
func update_claimed_visual() -> void:
	claimed_display_color = Color(0, 0, 0, 0)
	if not territory_data or not territory_data.is_claimed():
		queue_redraw()
		return
	if Engine.is_editor_hint():
		queue_redraw()
		return
	var owner_id = territory_data.owner_player_id
	var race: String = "Elf"
	for p in App.game_players:
		if p.get("id", -999) == owner_id:
			race = str(p.get("race", "Elf"))
			break
	claimed_display_color = App.get_race_color(race)
	queue_redraw()

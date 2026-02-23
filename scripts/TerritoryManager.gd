
class_name TerritoryManager
extends Node

## TerritoryManager
## Manages all territories on the map.
## Scans TerritoryNode children (editor-placed position markers),
## creates a TerritoryIndicator at each node's polygon center,
## then hides the TerritoryNode. The TerritoryIndicator handles all interaction.

## Dictionary: territory_id -> TerritoryIndicator (the interactive indicator)
var territories: Dictionary = {}

## Dictionary: territory_id -> Territory (data objects)
var territory_data: Dictionary = {}

## Dictionary: territory_id -> TerritoryNode (position source, hidden at runtime)
var _territory_nodes: Dictionary = {}

signal territories_initialized
signal territory_selected(territory_id: int)
signal card_placed(territory_id: int, player_id: int)


func _enter_tree() -> void:
	App.territory_manager = self

func _exit_tree() -> void:
	if App.territory_manager == self:
		App.territory_manager = null


## Initialize from editor-placed TerritoryNode children.
## Creates a TerritoryIndicator at each node's polygon center, hides the TerritoryNode.
func initialize_from_editor_nodes(parent_node: Node) -> void:
	if not parent_node:
		push_error("TerritoryManager: parent_node is required")
		return

	clear_territories()

	var nodes_found: Array[TerritoryNode] = []
	for child in parent_node.get_children():
		if child is TerritoryNode:
			nodes_found.append(child as TerritoryNode)

	for node in nodes_found:
		if not node.territory_data:
			continue

		var tid: int = node.territory_data.territory_id
		var territory: Territory = node.territory_data
		territory_data[tid] = territory
		_territory_nodes[tid] = node

		var indicator := TerritoryIndicator.new()
		indicator.name = "Indicator_%d" % tid
		indicator.territory_id = tid
		indicator.region_id = territory.region_id
		indicator.initialize(territory)

		parent_node.add_child(indicator)

		# Position at the center of the TerritoryNode's polygon
		var center_local: Vector2 = node.get_center_local()
		var global_center: Vector2 = node.get_global_transform_with_canvas() * center_local
		var container_center: Vector2 = parent_node.get_global_transform_with_canvas().affine_inverse() * global_center
		indicator.position = container_center - TerritoryIndicator.INDICATOR_SIZE / 2.0

		territories[tid] = indicator

		if not indicator.territory_selected.is_connected(_on_territory_selected):
			indicator.territory_selected.connect(_on_territory_selected)
		if not indicator.card_placed.is_connected(_on_card_placed):
			indicator.card_placed.connect(_on_card_placed)

		# Hide the TerritoryNode — it's just a position marker
		node.visible = false
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE

	territories_initialized.emit()
	print("[TerritoryManager] Created %d indicators from TerritoryNode positions" % territories.size())


## Initialize from config data (fallback when no TerritoryNodes in scene)
func initialize_territories(territory_configs: Array[Dictionary], parent_node: Node = null) -> void:
	if not parent_node:
		push_error("TerritoryManager: parent_node is required for initialization")
		return

	clear_territories()

	for config in territory_configs:
		var tid: int = config.get("territory_id", -1)
		var rid: int = config.get("region_id", 0)
		var adjacent_ids: Array[int] = config.get("adjacent_territory_ids", [])

		if tid == -1:
			push_warning("TerritoryManager: Skipping territory with invalid ID")
			continue

		var territory := Territory.new(tid, rid, null, adjacent_ids)
		territory_data[tid] = territory

	for config in territory_configs:
		var tid: int = config.get("territory_id", -1)
		if tid == -1 or not territory_data.has(tid):
			continue

		var territory: Territory = territory_data[tid]
		var indicator := TerritoryIndicator.new()
		indicator.name = "Indicator_%d" % tid
		indicator.territory_id = tid
		indicator.region_id = territory.region_id
		indicator.initialize(territory)

		var pos: Vector2 = config.get("position", Vector2.ZERO)
		if pos != Vector2.ZERO:
			indicator.position = pos

		parent_node.add_child(indicator)
		territories[tid] = indicator

		indicator.territory_selected.connect(_on_territory_selected)
		indicator.card_placed.connect(_on_card_placed)

	territories_initialized.emit()
	print("[TerritoryManager] Initialized %d territories from config" % territories.size())


func get_territory_node(territory_id: int) -> TerritoryIndicator:
	return territories.get(territory_id, null)


func get_territory_data(territory_id: int) -> Territory:
	return territory_data.get(territory_id, null)


func get_all_territory_ids() -> Array[int]:
	return territories.keys()


func clear_territories() -> void:
	for indicator in territories.values():
		if is_instance_valid(indicator):
			indicator.queue_free()
	territories.clear()
	territory_data.clear()
	_territory_nodes.clear()


func _on_territory_selected(territory_id: int) -> void:
	territory_selected.emit(territory_id)


func _on_card_placed(territory_id: int, player_id: int) -> void:
	card_placed.emit(territory_id, player_id)

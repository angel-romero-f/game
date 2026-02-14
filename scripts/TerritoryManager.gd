
class_name TerritoryManager
extends Node

## TerritoryManager
## Manages all territories on the map.
## Initializes territories, assigns adjacency lists, and region IDs on map load.
## No gameplay logic - only map ↔ territory linkage.

## Dictionary: territory_id -> TerritoryNode
var territories: Dictionary = {}

## Parent container type changed from Node2D to Control

## Dictionary: territory_id -> Territory (data objects)
var territory_data: Dictionary = {}

## Signal emitted when territories are initialized
signal territories_initialized

## Signal forwarded from TerritoryNode
signal territory_selected(territory_id: int)
signal card_placed(territory_id: int, player_id: int)


func _enter_tree() -> void:
	App.territory_manager = self

func _exit_tree() -> void:
	if App.territory_manager == self:
		App.territory_manager = null

func _ready() -> void:
	# Territories will be initialized when map loads
	pass


## Initialize territories from editor-placed TerritoryNode children
## Scans parent_node for TerritoryNode children and registers them
## parent_node should be a Control node
func initialize_from_editor_nodes(parent_node: Node) -> void:
	if not parent_node:
		push_error("TerritoryManager: parent_node is required")
		return
	
	clear_territories()
	
	# Find all TerritoryNode children
	for child in parent_node.get_children():
		if child is TerritoryNode:
			var node: TerritoryNode = child as TerritoryNode
			if node.territory_data:
				var territory_id: int = node.territory_data.territory_id
				territories[territory_id] = node
				territory_data[territory_id] = node.territory_data
				
				# Connect signals
				if not node.territory_selected.is_connected(_on_territory_selected):
					node.territory_selected.connect(_on_territory_selected)
				if not node.card_placed.is_connected(_on_card_placed):
					node.card_placed.connect(_on_card_placed)
	
	# Link adjacent nodes based on territory_data adjacency
	for territory_id in territories:
		var node: TerritoryNode = territories[territory_id]
		if node.territory_data:
			var adjacent_ids: Array[int] = node.territory_data.adjacent_territories
			var adjacent_nodes: Array[TerritoryNode] = []
			for adj_id in adjacent_ids:
				if territories.has(adj_id):
					adjacent_nodes.append(territories[adj_id])
			node.set_adjacent_nodes(adjacent_nodes)
	
	territories_initialized.emit()
	print("[TerritoryManager] Initialized %d territories from editor nodes" % territories.size())


## Initialize all territories on map load from config data
## territory_configs: Array of dictionaries with:
##   - territory_id: int
##   - region_id: int
##   - position: Vector2 (optional, for node placement)
##   - size: Vector2 (optional, default size if no polygon_points)
##   - polygon_points: PackedVector2Array (optional, should match gray outline shape)
##   - adjacent_territory_ids: Array[int]
func initialize_territories(territory_configs: Array[Dictionary], parent_node: Node = null) -> void:
	if not parent_node:
		push_error("TerritoryManager: parent_node is required for initialization")
		return
	
	# Clear existing territories
	clear_territories()
	
	# First pass: Create Territory data objects
	for config in territory_configs:
		var territory_id: int = config.get("territory_id", -1)
		var region_id: int = config.get("region_id", 0)
		var adjacent_ids: Array[int] = config.get("adjacent_territory_ids", [])
		
		if territory_id == -1:
			push_warning("TerritoryManager: Skipping territory with invalid ID")
			continue
		
		# Create Territory data object
		var territory := Territory.new(territory_id, region_id, null, adjacent_ids)
		territory_data[territory_id] = territory
	
	# Second pass: Create TerritoryNode instances and link them
	for config in territory_configs:
		var territory_id: int = config.get("territory_id", -1)
		if territory_id == -1 or not territory_data.has(territory_id):
			continue
		
		var territory: Territory = territory_data[territory_id]
		
		# Create TerritoryNode (Control node)
		var node := TerritoryNode.new()
		node.name = "Territory_%d" % territory_id
		node.initialize(territory)
		
		# Set position and size if provided
		var position: Vector2 = config.get("position", Vector2.ZERO)
		var size: Vector2 = config.get("size", Vector2(200, 150))
		
		if position != Vector2.ZERO:
			node.position = position
		if size != Vector2.ZERO:
			node.size = size
		
		# Set polygon points if provided (should match gray outline)
		var polygon_points: PackedVector2Array = config.get("polygon_points", PackedVector2Array())
		if polygon_points.is_empty():
			# Create default rectangular polygon if none provided
			var default_points := PackedVector2Array([
				Vector2(0, 0),
				Vector2(size.x, 0),
				Vector2(size.x, size.y),
				Vector2(0, size.y)
			])
			node.set_polygon_points(default_points)
		else:
			node.set_polygon_points(polygon_points)
		
		# Add to parent and store reference
		parent_node.add_child(node)
		territories[territory_id] = node
		
		# Connect signals
		node.territory_selected.connect(_on_territory_selected)
		node.card_placed.connect(_on_card_placed)
	
	# Third pass: Link adjacent nodes
	for config in territory_configs:
		var territory_id: int = config.get("territory_id", -1)
		if territory_id == -1 or not territories.has(territory_id):
			continue
		
		var node: TerritoryNode = territories[territory_id]
		var adjacent_ids: Array[int] = config.get("adjacent_territory_ids", [])
		
		var adjacent_nodes: Array[TerritoryNode] = []
		for adj_id in adjacent_ids:
			if territories.has(adj_id):
				adjacent_nodes.append(territories[adj_id])
		
		node.set_adjacent_nodes(adjacent_nodes)
	
	territories_initialized.emit()
	print("[TerritoryManager] Initialized %d territories" % territories.size())


## Get a TerritoryNode by ID
func get_territory_node(territory_id: int) -> TerritoryNode:
	return territories.get(territory_id, null)


## Get Territory data by ID
func get_territory_data(territory_id: int) -> Territory:
	return territory_data.get(territory_id, null)


## Get all territory IDs
func get_all_territory_ids() -> Array[int]:
	return territories.keys()


## Create a simple example territory configuration
## Returns an Array of config dictionaries for testing
static func create_example_config() -> Array[Dictionary]:
	return [
		{
			"territory_id": 1,
			"region_id": 1,
			"position": Vector2(100, 100),
			"adjacent_territory_ids": [2, 3]
		},
		{
			"territory_id": 2,
			"region_id": 1,
			"position": Vector2(300, 100),
			"adjacent_territory_ids": [1, 4]
		},
		{
			"territory_id": 3,
			"region_id": 2,
			"position": Vector2(100, 300),
			"adjacent_territory_ids": [1, 4]
		},
		{
			"territory_id": 4,
			"region_id": 2,
			"position": Vector2(300, 300),
			"adjacent_territory_ids": [2, 3]
		}
	]


## Clear all territories
func clear_territories() -> void:
	for node in territories.values():
		if is_instance_valid(node):
			node.queue_free()
	territories.clear()
	territory_data.clear()


## Signal handlers
func _on_territory_selected(territory_id: int) -> void:
	territory_selected.emit(territory_id)


func _on_card_placed(territory_id: int, player_id: int) -> void:
	card_placed.emit(territory_id, player_id)

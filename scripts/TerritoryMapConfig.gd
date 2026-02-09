class_name TerritoryMapConfig
extends Resource

## TerritoryMapConfig
## Resource that defines all territories on the map.
## Contains territory definitions with positions, regions, and adjacencies.

## Array of territory configuration dictionaries
@export var territories: Array[Dictionary] = []

## Get territory configs as array
func get_territory_configs() -> Array[Dictionary]:
	return territories.duplicate(true)


## Create default map configuration with all 31 territories
## Based on the map with gray outlines
static func create_default_config() -> TerritoryMapConfig:
	var config := TerritoryMapConfig.new()
	
	# Note: Positions are approximate and should be adjusted based on actual map layout
	# Adjacencies are based on shared gray outline borders
	# Region IDs can be assigned based on geographical features
	
	# For now, create a placeholder structure with 31 territories
	# These will need to be positioned and configured based on the actual map
	var territory_configs: Array[Dictionary] = []
	
	# Create 31 territories with placeholder data
	# In a real implementation, these would be manually configured based on the map image
	for i in range(31):
		var territory_id: int = i + 1
		
		# Assign region IDs based on approximate map regions
		# Regions: 1=North, 2=Central, 3=South, 4=East, 5=West
		var region_id: int = 1
		if territory_id <= 6:
			region_id = 1  # North
		elif territory_id <= 12:
			region_id = 2  # Central
		elif territory_id <= 18:
			region_id = 3  # South
		elif territory_id <= 24:
			region_id = 4  # East
		else:
			region_id = 5  # West
		
		# Placeholder position (will need manual adjustment)
		# Assuming map is roughly 1920x1080 or similar
		var x: float = 200.0 + (territory_id % 6) * 250.0
		var y: float = 150.0 + float(territory_id) / 6.0 * 200.0
		
		# Placeholder adjacency (will need manual configuration)
		# Territories adjacent to this one based on gray outline borders
		var adjacent_ids: Array[int] = []
		if territory_id > 1:
			adjacent_ids.append(territory_id - 1)
		if territory_id < 31:
			adjacent_ids.append(territory_id + 1)
		
		# Create default rectangular polygon (will be replaced with actual gray outline shapes)
		var default_size := Vector2(200, 150)
		var default_polygon := PackedVector2Array([
			Vector2(0, 0),
			Vector2(default_size.x, 0),
			Vector2(default_size.x, default_size.y),
			Vector2(0, default_size.y)
		])
		
		territory_configs.append({
			"territory_id": territory_id,
			"region_id": region_id,
			"position": Vector2(x, y),
			"size": default_size,
			"polygon_points": default_polygon,  # Replace with actual gray outline polygon
			"adjacent_territory_ids": adjacent_ids
		})
	
	config.territories = territory_configs
	return config

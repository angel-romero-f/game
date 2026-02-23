


extends EditorScript

## TerritoryExporter
## Helper script to export editor-placed TerritoryNodes to a config file
## Run this from Tools -> Execute Script in the editor
## This will create a TerritoryMapConfig.tres resource file

func _run() -> void:
	print("Exporting territories from GameIntro scene...")
	
	# Find GameIntro scene
	var game_intro_path := "res://scenes/ui/game_intro.tscn"
	if not ResourceLoader.exists(game_intro_path):
		push_error("GameIntro scene not found at: " + game_intro_path)
		return
	
	var game_intro_scene := load(game_intro_path) as PackedScene
	if not game_intro_scene:
		push_error("Failed to load GameIntro scene")
		return
	
	# Instantiate the scene to access its nodes
	var instance := game_intro_scene.instantiate()
	if not instance:
		push_error("Failed to instantiate GameIntro scene")
		return
	
	# Find TerritoriesContainer
	var territories_container := instance.get_node_or_null("TerritoriesContainer")
	if not territories_container:
		push_error("TerritoriesContainer not found in GameIntro scene")
		instance.queue_free()
		return
	
	# Collect all TerritoryNode instances
	var territory_configs: Array[Dictionary] = []
	var territory_nodes := []
	
	for child in territories_container.get_children():
		if child is TerritoryNode:
			territory_nodes.append(child)
	
	if territory_nodes.is_empty():
		push_error("No TerritoryNode instances found in TerritoriesContainer")
		instance.queue_free()
		return
	
	# Sort by territory_id
	territory_nodes.sort_custom(func(a, b): 
		if not a.territory_data or not b.territory_data:
			return false
		return a.territory_data.territory_id < b.territory_data.territory_id
	)
	
	# Export each territory
	for node in territory_nodes:
		if not node.territory_data:
			push_warning("TerritoryNode '%s' has no territory_data, skipping" % node.name)
			continue
		
		var territory: Territory = node.territory_data
		var config := {
			"territory_id": territory.territory_id,
			"region_id": territory.region_id,
			"position": node.position,
			"size": node.size,
			"polygon_points": node.polygon_points.duplicate(),
			"adjacent_territory_ids": territory.adjacent_territories.duplicate()
		}
		territory_configs.append(config)
		print("Exported territory %d: %d polygon points" % [territory.territory_id, node.polygon_points.size()])
	
	# Create TerritoryMapConfig resource
	var config_resource := TerritoryMapConfig.new()
	config_resource.territories = territory_configs
	
	# Save to file
	var config_path := "res://scripts/TerritoryMapConfig.tres"
	var error := ResourceSaver.save(config_resource, config_path)
	if error != OK:
		push_error("Failed to save config: " + str(error))
	else:
		print("Successfully exported %d territories to %s" % [territory_configs.size(), config_path])
	
	instance.queue_free()

extends Node

## Simple scene navigation helper
func go(path: String) -> void:
	get_tree().change_scene_to_file(path)

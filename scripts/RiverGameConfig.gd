class_name RiverGameConfig
extends Resource

## Configuration resource for the River Crossing minigame
## Centralizes all gameplay parameters for easy tuning

# Screen/Viewport bounds
@export var game_bounds: Rect2 = Rect2(-450, -450, 900, 900)

# Lane configuration - 3 lanes for the river
@export var num_lanes: int = 3

# Player settings
@export var jump_duration: float = 0.2
@export var jump_arc_height: float = 20.0
@export var drown_sink_distance: float = 20.0

# Jump offsets (for water/victory jumps)
@export var jump_to_water_offset: Vector2 = Vector2(80, 80)
@export var victory_jump_offset: Vector2 = Vector2(80, 60)

# Rock spawning
@export var spawn_interval_min: float = 3.0
@export var spawn_interval_max: float = 5.5
@export var min_rock_spacing: float = 180.0
@export var rock_speed_min: float = 40.0
@export var rock_speed_max: float = 80.0

# Path-based rock movement
@export var initial_rocks_per_lane_min: int = 1
@export var initial_rocks_per_lane_max: int = 2
@export var spawn_progress_offset: float = 0.15  # How far back to spawn new rocks (0-1)

# Player off-screen detection
@export var player_bounds: Rect2 = Rect2(-350, -350, 700, 700)

## Check if a position is within the game bounds
func is_in_bounds(pos: Vector2) -> bool:
	return game_bounds.has_point(pos)

## Check if player position is within safe bounds
func is_player_in_bounds(pos: Vector2) -> bool:
	return player_bounds.has_point(pos)

## Get a random rock speed within the configured range
func get_random_rock_speed() -> float:
	return randf_range(rock_speed_min, rock_speed_max)

## Get a random spawn interval
func get_random_spawn_interval() -> float:
	return randf_range(spawn_interval_min, spawn_interval_max)

## Get random initial rocks count
func get_initial_rock_count() -> int:
	return randi_range(initial_rocks_per_lane_min, initial_rocks_per_lane_max)

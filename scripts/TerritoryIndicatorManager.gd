extends Node

## TerritoryIndicatorManager
## Creates and manages a sprite indicator at the center of each territory.
## Indicators use assets/territory_indicator.pxo; frame depends on owner race and defending card count.
## (mouse_filter IGNORE so clicks hit the territory). Each indicator shares the same id as its territory.
## Communicates with BattleStateManager and TerritoryClaimState; refreshes when cards or owner change.

const INDICATOR_TEXTURE_PATH := "res://assets/territory_indicator.pxo"
const INDICATOR_SIZE := Vector2(128, 128)

## Frame layout: 0=unclaimed; 1-3=elf 1-3 cards; 4-6=orc; 7-9=fairy; 10-12=infernal
const RACE_FRAME_BASE: Dictionary = {
	"elf": 1,
	"orc": 4,
	"fairy": 7,
	"infernal": 10,
}

## territory_id -> TextureRect (indicator node)
var _indicators: Dictionary = {}

var _territory_manager: TerritoryManager = null
var _territories_container: Control = null
var _territory_claim_state: Node = null
var _sprite_frames: SpriteFrames = null


func _ready() -> void:
	_territory_claim_state = get_node_or_null("/root/TerritoryClaimState")


## Create one indicator per territory and add to container (drawn under territories).
func create_indicators(p_territory_manager: TerritoryManager, p_territories_container: Control) -> void:
	if not p_territory_manager or not p_territories_container:
		push_warning("[TerritoryIndicatorManager] Missing territory_manager or container.")
		return
	_territory_manager = p_territory_manager
	_territories_container = p_territories_container

	var res = load(INDICATOR_TEXTURE_PATH)
	if not res is SpriteFrames:
		push_warning("[TerritoryIndicatorManager] Could not load SpriteFrames from %s" % INDICATOR_TEXTURE_PATH)
		return
	_sprite_frames = res as SpriteFrames
	if not _sprite_frames.has_animation("default"):
		push_warning("[TerritoryIndicatorManager] No 'default' animation in %s" % INDICATOR_TEXTURE_PATH)
		return

	var territory_ids: Array = []
	for tid in _territory_manager.territories:
		territory_ids.append(tid)
	territory_ids.sort()

	# Create indicators and add to container at the beginning so they draw under territory nodes
	for tid in territory_ids:
		var territory_node: TerritoryNode = _territory_manager.territories[tid]
		if not territory_node or not is_instance_valid(territory_node):
			continue
		var indicator := _create_indicator_for_territory(tid, territory_node)
		if indicator:
			_indicators[tid] = indicator
			_territories_container.add_child(indicator)
			_territories_container.move_child(indicator, 0)
	# Put indicators in ascending id order at 0..n-1 so territory nodes follow
	var idx := 0
	for tid in territory_ids:
		if _indicators.has(tid):
			_territories_container.move_child(_indicators[tid], idx)
			idx += 1

	refresh_all_indicator_textures()
	print("[TerritoryIndicatorManager] Created %d indicators" % _indicators.size())


## Frame index from territory_indicator.pxo: 0=unclaimed; 1-3 elf; 4-6 orc; 7-9 fairy; 10-12 infernal (1-3 cards each).
func _get_indicator_frame_index(territory_id: int) -> int:
	var race: String = get_territory_owner_race(territory_id)
	var count: int = get_defending_card_count(territory_id)
	if race.is_empty() or count <= 0:
		return 0
	var r: String = race.to_lower().strip_edges()
	if not RACE_FRAME_BASE.has(r):
		return 0
	var base: int = RACE_FRAME_BASE[r]
	# 1 card -> base+0, 2 -> base+1, 3 -> base+2
	var card_offset: int = clampi(count, 1, 3) - 1
	return base + card_offset


func _create_indicator_for_territory(territory_id: int, territory_node: TerritoryNode) -> Control:
	var rect := TextureRect.new()
	rect.name = "TerritoryIndicator_%d" % territory_id
	# Texture set in refresh_indicator_texture
	rect.texture = _get_texture_for_frame(_get_indicator_frame_index(territory_id))
	rect.expand_mode = TextureRect.EXPAND_FIT_HEIGHT_PROPORTIONAL
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.custom_minimum_size = INDICATOR_SIZE
	rect.size = INDICATOR_SIZE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_meta("territory_id", territory_id)

	# Polygon points are in the territory's local draw space; position may be anchor-offset and node can be rotated.
	# Transform polygon center from territory local → global → container local so the indicator lines up visually.
	var center_local: Vector2 = territory_node.get_center_local()
	var global_center: Vector2 = territory_node.get_global_transform_with_canvas() * center_local
	var container_center: Vector2 = _territories_container.get_global_transform_with_canvas().affine_inverse() * global_center
	rect.position = container_center - INDICATOR_SIZE / 2.0

	return rect


func _get_texture_for_frame(frame_index: int) -> Texture2D:
	if not _sprite_frames or not _sprite_frames.has_animation("default"):
		return null
	var frame_count := _sprite_frames.get_frame_count("default")
	var idx := clampi(frame_index, 0, max(0, frame_count - 1))
	return _sprite_frames.get_frame_texture("default", idx)


## Update one indicator's sprite from BattleStateManager and TerritoryClaimState.
func refresh_indicator_texture(territory_id: int) -> void:
	var indicator: Control = _indicators.get(territory_id, null)
	if not indicator or not indicator is TextureRect:
		return
	var frame_idx: int = _get_indicator_frame_index(territory_id)
	var tex: Texture2D = _get_texture_for_frame(frame_idx)
	if tex:
		(indicator as TextureRect).texture = tex


## Update all indicators when defending card count or territory owner changes (e.g. after claim or battle).
func refresh_all_indicator_textures() -> void:
	if not _sprite_frames or _indicators.is_empty():
		return
	for tid in _indicators:
		refresh_indicator_texture(tid)


## Return the number of defending cards on the territory (from BattleStateManager).
func get_defending_card_count(territory_id: int) -> int:
	if not BattleStateManager:
		return 0
	var slots: Dictionary = BattleStateManager.get_defending_slots(str(territory_id))
	return slots.size()


## Return the owner player id for the territory, or null if unclaimed (from TerritoryClaimState).
func get_territory_owner_id(territory_id: int) -> Variant:
	if not _territory_claim_state or not _territory_claim_state.has_method("get_owner_id"):
		return null
	return _territory_claim_state.call("get_owner_id", territory_id)


## Return the race of the owner for the territory, or empty string if unclaimed.
func get_territory_owner_race(territory_id: int) -> String:
	var owner_id: Variant = get_territory_owner_id(territory_id)
	if owner_id == null:
		return ""
	for p in App.game_players:
		if p.get("id", -999) == owner_id:
			return str(p.get("race", ""))
	return ""


## Get the indicator node for a territory (if any).
func get_indicator(territory_id: int) -> Control:
	return _indicators.get(territory_id, null)


## Refresh indicator positions (e.g. after layout change). Call if territory positions change at runtime.
func refresh_positions() -> void:
	if not _territory_manager or _indicators.is_empty() or not _territories_container:
		return
	for tid in _indicators:
		var indicator: Control = _indicators[tid]
		var territory_node: TerritoryNode = _territory_manager.territories.get(tid, null)
		if territory_node and is_instance_valid(territory_node) and is_instance_valid(indicator):
			var center_local: Vector2 = territory_node.get_center_local()
			var global_center: Vector2 = territory_node.get_global_transform_with_canvas() * center_local
			var container_center: Vector2 = _territories_container.get_global_transform_with_canvas().affine_inverse() * global_center
			indicator.position = container_center - INDICATOR_SIZE / 2.0

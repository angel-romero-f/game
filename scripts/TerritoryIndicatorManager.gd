extends Node

## TerritoryIndicatorManager
## Creates and manages a sprite indicator at the center of each territory.
## Indicators use assets/territory_indicator.pxo frame 1 and are drawn under the territory node
## (mouse_filter IGNORE so clicks hit the territory). Each indicator shares the same id as its territory.
## Communicates with BattleStateManager to track defending card count and owner/race per territory.

const INDICATOR_TEXTURE_PATH := "res://assets/territory_indicator.pxo"
const INDICATOR_FRAME_INDEX := 1
const INDICATOR_SIZE := Vector2(128, 128)

## territory_id -> TextureRect (indicator node)
var _indicators: Dictionary = {}

var _territory_manager: TerritoryManager = null
var _territories_container: Control = null
var _territory_claim_state: Node = null


func _ready() -> void:
	_territory_claim_state = get_node_or_null("/root/TerritoryClaimState")


## Create one indicator per territory and add to container (drawn under territories).
func create_indicators(p_territory_manager: TerritoryManager, p_territories_container: Control) -> void:
	if not p_territory_manager or not p_territories_container:
		push_warning("[TerritoryIndicatorManager] Missing territory_manager or container.")
		return
	_territory_manager = p_territory_manager
	_territories_container = p_territories_container

	# Load texture from territory_indicator.pxo frame 1
	var texture: Texture2D = _load_indicator_texture()
	if not texture:
		push_warning("[TerritoryIndicatorManager] Could not load indicator texture from %s" % INDICATOR_TEXTURE_PATH)
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
		var indicator := _create_indicator_for_territory(tid, territory_node, texture)
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

	print("[TerritoryIndicatorManager] Created %d indicators" % _indicators.size())


func _load_indicator_texture() -> Texture2D:
	var res = load(INDICATOR_TEXTURE_PATH)
	if res is SpriteFrames:
		var sf: SpriteFrames = res as SpriteFrames
		if sf.has_animation("default"):
			var frame_count := sf.get_frame_count("default")
			var frame_idx := clampi(INDICATOR_FRAME_INDEX, 0, max(0, frame_count - 1))
			return sf.get_frame_texture("default", frame_idx)
	return null


func _create_indicator_for_territory(territory_id: int, territory_node: TerritoryNode, texture: Texture2D) -> Control:
	var rect := TextureRect.new()
	rect.name = "TerritoryIndicator_%d" % territory_id
	rect.texture = texture
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

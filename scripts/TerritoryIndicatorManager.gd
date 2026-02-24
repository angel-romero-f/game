extends Node

## TerritoryIndicatorManager
## Manages batch operations on TerritoryIndicator nodes.
## Since indicators are now self-contained scene nodes, this only handles
## refresh operations (e.g. after claims or battles change state).

var _territory_manager: TerritoryManager = null


func initialize(p_territory_manager: TerritoryManager) -> void:
	_territory_manager = p_territory_manager


func refresh_all_indicator_textures() -> void:
	if not _territory_manager:
		return
	for tid in _territory_manager.territories:
		var indicator: TerritoryIndicator = _territory_manager.territories[tid]
		if indicator and is_instance_valid(indicator):
			indicator.update_claimed_visual()


func refresh_indicator_texture(territory_id: int) -> void:
	if not _territory_manager:
		return
	var indicator: TerritoryIndicator = _territory_manager.territories.get(territory_id, null)
	if indicator and is_instance_valid(indicator):
		indicator.update_claimed_visual()

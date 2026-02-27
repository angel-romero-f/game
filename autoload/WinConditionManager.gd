extends Node

## WinConditionManager
## Checks if a player owns at least one territory in 5 out of 6 regions.
## Win condition: player owns >= 1 territory in 5+ distinct regions.

signal player_won(player_id: int)


## Returns true if the player owns at least one territory in 5 or more different regions.
## Uses the static TERRITORY_REGIONS mapping so this works even when the map scene is unloaded
## (e.g. during battle or minigame scenes).
func check_player_wins(player_id: int) -> bool:
	var tcs = get_node_or_null("/root/TerritoryClaimState")
	if not tcs:
		return false
	var claims_val = tcs.get("claims")
	if not claims_val is Dictionary:
		return false
	var claims: Dictionary = claims_val

	var unique_regions: Dictionary = {}  # region_id -> true

	for tid_key in claims:
		var claim_data: Dictionary = claims[tid_key]
		var owner_id: Variant = claim_data.get("owner_player_id", null)
		if owner_id == null or int(owner_id) != int(player_id):
			continue
		var tid: int = int(tid_key)
		var region_id: int = TerritoryManager.TERRITORY_REGIONS.get(tid, -1)
		if region_id < 0:
			continue
		unique_regions[region_id] = true

	return unique_regions.size() >= 5

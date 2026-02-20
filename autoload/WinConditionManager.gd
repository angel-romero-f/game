extends Node

## WinConditionManager
## Checks if a player owns at least one territory in 5 out of 6 regions.
## Win condition: player owns >= 1 territory in 5+ distinct regions.

signal player_won(player_id: int)


## Returns true if the player owns at least one territory in 5 or more different regions.
func check_player_wins(player_id: int) -> bool:
	var tcs := get_node_or_null("/root/TerritoryClaimState") as Node
	if not tcs or not tcs.has_method("get"):
		return false
	var claims: Dictionary = tcs.get("claims")
	if not claims is Dictionary:
		return false

	var unique_regions: Dictionary = {}  # region_id -> true
	var tm = App.territory_manager if App else null
	if not tm or not tm.territory_data:
		return false

	for tid_key in claims:
		var claim_data: Dictionary = (claims as Dictionary)[tid_key]
		var owner_id: Variant = claim_data.get("owner_player_id", null)
		if owner_id == null or int(owner_id) != int(player_id):
			continue
		var tid: int = int(tid_key)
		var territory: Territory = tm.territory_data.get(tid)
		if not territory:
			continue
		unique_regions[territory.region_id] = true

	return unique_regions.size() >= 5

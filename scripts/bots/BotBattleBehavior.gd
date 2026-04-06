extends RefCounted
class_name BotBattleBehavior

## Bot battle-time behavior (difficulty 4+): defender slot alignment vs a single attacker card.

const ALIGN_MOVE_DELAY_SEC := 0.2
const POST_TIMER_GRACE_SEC := 0.1

## Bump pairing from BattleManager: player slot index -> opponent slot index.
const PLAYER_SLOT_TO_OPPONENT_SLOT: Dictionary = {
	0: 2,
	1: 1,
	2: 0,
}


func on_battle_started(_bot_player_id: int) -> void:
	## Reserved for future hooks; alignment runs from BattleManager during the coordination timer.
	pass


static func should_run_defender_alignment(
	is_spectator: bool,
	player_slot_nodes: Array,
	opponent_slot_nodes: Array,
	opponent_cards_by_slot: Dictionary,
	tid_str: String,
	is_local_defender: bool,
) -> bool:
	if is_spectator:
		return false
	if tid_str.is_empty():
		return false
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return false
	var tcs: Node = tree.root.get_node_or_null("TerritoryClaimState")
	if tcs == null or not tcs.has_method("get_owner_id"):
		return false
	var owner_raw: Variant = tcs.call("get_owner_id", int(tid_str))
	var defender_id: int = int(owner_raw) if owner_raw != null else -1
	if defender_id < 0:
		return false
	# We align the opponent row, so the active bot can be either the territory defender
	# (when local is attacker) or the attacker (when local is defender).
	var opponent_bot_id: int = defender_id if not is_local_defender else int(App.pending_territory_battle_attacker_id)
	if not PlayerDataSync.is_bot_id(opponent_bot_id):
		return false
	var bot_diff: int = int(PlayerDataSync.get_bot_difficulty(opponent_bot_id))
	if bot_diff < 4:
		return false
	var p_count := 0
	for i in range(mini(3, player_slot_nodes.size())):
		var slot: Node = player_slot_nodes[i]
		if slot and slot.get("snapped_card"):
			var c: Node = slot.snapped_card
			if c and is_instance_valid(c):
				p_count += 1
	if p_count <= 0:
		return false
	var o_filled := 0
	var o_empty := -1
	for j in range(mini(3, opponent_slot_nodes.size())):
		var osl: Node = opponent_slot_nodes[j]
		if not osl:
			continue
		var oc: Node = opponent_cards_by_slot.get(osl, null)
		if oc != null and is_instance_valid(oc):
			o_filled += 1
		else:
			o_empty = j
	# Alignment requires at least one movable bot card and one empty destination.
	if o_filled <= 0 or o_empty < 0:
		return false
	var strongest_player_idx := _get_strongest_player_slot_index(player_slot_nodes)
	if strongest_player_idx < 0:
		return false
	var desired_empty: int = int(PLAYER_SLOT_TO_OPPONENT_SLOT.get(strongest_player_idx, -1))
	if desired_empty < 0 or desired_empty == o_empty:
		return false
	return true


## Returns [from_o_idx, to_o_idx] for one move, or empty array if none needed.
static func get_next_opponent_slot_move_for_alignment(
	player_slot_nodes: Array,
	opponent_slot_nodes: Array,
	opponent_cards_by_slot: Dictionary,
) -> Array:
	var strongest_player_idx := _get_strongest_player_slot_index(player_slot_nodes)
	var opp_filled_indices: Array[int] = []
	var o_empty := -1
	for j in range(mini(3, opponent_slot_nodes.size())):
		var osl: Node = opponent_slot_nodes[j]
		if not osl:
			continue
		var oc: Node = opponent_cards_by_slot.get(osl, null)
		if oc == null or not is_instance_valid(oc):
			o_empty = j
		else:
			opp_filled_indices.append(j)
	if strongest_player_idx < 0 or o_empty < 0:
		return []

	# Level 5 single-card behavior:
	# keep the bot card in the lane that directly opposes the strongest player lane.
	if opp_filled_indices.size() == 1:
		var current_opp_idx: int = opp_filled_indices[0]
		var desired_opp_idx: int = int(PLAYER_SLOT_TO_OPPONENT_SLOT.get(strongest_player_idx, -1))
		if desired_opp_idx < 0 or desired_opp_idx == current_opp_idx:
			return []
		return [current_opp_idx, desired_opp_idx]

	var desired_empty: int = int(PLAYER_SLOT_TO_OPPONENT_SLOT.get(strongest_player_idx, -1))
	if desired_empty < 0 or desired_empty == o_empty:
		return []
	# If desired slot currently has a card, vacate it first.
	var desired_slot: Node = opponent_slot_nodes[desired_empty] if desired_empty < opponent_slot_nodes.size() else null
	var desired_card: Node = opponent_cards_by_slot.get(desired_slot, null) if desired_slot else null
	if desired_card != null and is_instance_valid(desired_card):
		return [desired_empty, o_empty]

	# Desired slot is empty: move strongest opponent card into it.
	var strongest_opp_idx := _get_strongest_opponent_slot_index(opponent_slot_nodes, opponent_cards_by_slot)
	if strongest_opp_idx < 0 or strongest_opp_idx == desired_empty:
		return []
	return [strongest_opp_idx, desired_empty]


static func _get_strongest_player_slot_index(player_slot_nodes: Array) -> int:
	var best_idx := -1
	var best_power := -1
	for i in range(mini(3, player_slot_nodes.size())):
		var slot: Node = player_slot_nodes[i]
		if not slot or not slot.get("snapped_card"):
			continue
		var c: Node = slot.snapped_card
		if c == null or not is_instance_valid(c):
			continue
		var p: int = int(c.get("frame_index")) + 1
		if p > best_power:
			best_power = p
			best_idx = i
	return best_idx


static func _get_strongest_opponent_slot_index(opponent_slot_nodes: Array, opponent_cards_by_slot: Dictionary) -> int:
	var best_idx := -1
	var best_power := -1
	for i in range(mini(3, opponent_slot_nodes.size())):
		var slot: Node = opponent_slot_nodes[i]
		if not slot:
			continue
		var c: Node = opponent_cards_by_slot.get(slot, null)
		if c == null or not is_instance_valid(c):
			continue
		var p: int = int(c.get("frame_index")) + 1
		if p > best_power:
			best_power = p
			best_idx = i
	return best_idx

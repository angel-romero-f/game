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
	if not PlayerDataSync.is_bot_id(defender_id):
		return false
	if int(PlayerDataSync.get_bot_difficulty(defender_id)) < 4:
		return false
	if is_local_defender:
		return false
	var p_count := 0
	var p_only := -1
	for i in range(mini(3, player_slot_nodes.size())):
		var slot: Node = player_slot_nodes[i]
		if slot and slot.get("snapped_card"):
			var c: Node = slot.snapped_card
			if c and is_instance_valid(c):
				p_count += 1
				p_only = i
	if p_count != 1 or p_only < 0:
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
	if o_filled != 2 or o_empty < 0:
		return false
	var desired_empty: int = int(PLAYER_SLOT_TO_OPPONENT_SLOT.get(p_only, -1))
	if desired_empty < 0 or desired_empty == o_empty:
		return false
	return true


## Returns [from_o_idx, to_o_idx] for one move, or empty array if none needed.
static func get_next_opponent_slot_move_for_alignment(
	player_slot_nodes: Array,
	opponent_slot_nodes: Array,
	opponent_cards_by_slot: Dictionary,
) -> Array:
	var p_only := -1
	for i in range(mini(3, player_slot_nodes.size())):
		var slot: Node = player_slot_nodes[i]
		if slot and slot.get("snapped_card"):
			var c: Node = slot.snapped_card
			if c and is_instance_valid(c):
				p_only = i
				break
	var o_empty := -1
	for j in range(mini(3, opponent_slot_nodes.size())):
		var osl: Node = opponent_slot_nodes[j]
		if not osl:
			continue
		var oc: Node = opponent_cards_by_slot.get(osl, null)
		if oc == null or not is_instance_valid(oc):
			o_empty = j
			break
	if p_only < 0 or o_empty < 0:
		return []
	var desired_empty: int = int(PLAYER_SLOT_TO_OPPONENT_SLOT.get(p_only, -1))
	if desired_empty < 0 or desired_empty == o_empty:
		return []
	return [desired_empty, o_empty]

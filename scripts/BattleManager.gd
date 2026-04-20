extends Node
const DEBUG_LOGS := false
## Verbose logs for spectator card-back sync (BattleSync + BSM merge). Set false to silence.
const SPECTATOR_SYNC_DEBUG := true

## BattleManager
## Orchestrates: opponent backs on entry, start-battle gating, flip animation,
## attribute-based resolution, and returning to menu on SPACE.
## In multiplayer: syncs card placement, waits for all players to press Start, flips when all ready.

const CARD_SCENE: PackedScene = preload("res://scenes/card.tscn")
const MAIN_MENU_PATH := "res://scenes/ui/game_intro.tscn"
## Preload so BattleManager does not depend on global `class_name` registration order.
const _BOT_BATTLE_BEHAVIOR = preload("res://scripts/bots/BotBattleBehavior.gd")

enum State { SETUP, WAITING_FOR_PLAYER, WAITING_FOR_ALL_READY, FLIPPING, RESOLVED }
var state: State = State.SETUP

## Editor-provided attribute mapping + rules.
@export var attribute_config: Resource

## Node names (kept simple; pairing is fixed and intended to remain stable).
@export var player_slots: Array[StringName] = [&"CardSlotPL", &"CardSlotPM", &"CardSlotPR"]
@export var opponent_slots: Array[StringName] = [&"CardSlotOR", &"CardSlotOM", &"CardSlotOL"]

## Card back used for face-down opponent cards (DeckP/DeckO nodes were removed).
const CARD_BACK_FRAMES: SpriteFrames = preload("res://assets/cardback.pxo")
const CARD_BACK_FRAME_INDEX := 0

## UI node paths (created in scene).
@export var timer_label_path: NodePath = NodePath("BattleUI/UI/TimerLabel")
@export var timer_sub_label_path: NodePath = NodePath("BattleUI/UI/TimerSubLabel")
@export var result_label_path: NodePath = NodePath("BattleUI/UI/ResultLabel")
@export var continue_label_path: NodePath = NodePath("BattleUI/UI/ContinueLabel")
@export var leave_button_path: NodePath = NodePath("BattleUI/UI/LeaveButton")
@export var debug_add_card_button_path: NodePath = NodePath("BattleUI/UI/DebugAddCardButton")

## Temporary debug: show button to add a random card to hand. Toggle in editor.
@export var show_debug_add_card_button: bool = false

## Flip animation settings.
@export var flip_up_duration: float = 0.25
@export var flip_down_duration: float = 0.25
@export var offscreen_y: float = -200.0

## +1 / -1 on player cards after flip. Tweak size and offset in the inspector; run a battle to preview.
@export_group("Attribute indicator (+1/-1)")
@export var attribute_indicator_font_scale: float = 0.5
@export var attribute_indicator_offset: Vector2 = Vector2(0.0, 40.0)

var _player_slot_nodes: Array = []
var _opponent_slot_nodes: Array = []

var _timer_label: Label
var _timer_sub_label: Label
var _result_label: Label
var _continue_label: Label
var _leave_button: Button
var _debug_add_card_button: Button
var _card_manager: Node = null
var _card_scene_ui: Node = null

## Race sprites: Player (frame 1) and Opponent (frame 0) from assets/[race]_fb.pxo.
## Editor scale is the base; Elf is 1.5x that, Fairy is 1/1.5x, Orc/Infernal use base.
## Use Game Race = follow code (local/opponent from game); any specific race = override and always use that texture.
enum DefaultRace { USE_GAME, ELF, ORC, INFERNAL, FAIRY }
@export var player_default_race: DefaultRace = DefaultRace.USE_GAME
@export var opponent_default_race: DefaultRace = DefaultRace.USE_GAME

var _player_sprite: Sprite2D
var _opponent_sprite: Sprite2D

var _opponent_cards_by_slot: Dictionary = {} # slot -> card
## Spectator: face-down backs on defender row (player slots). Incrementally updated; freed immediately on change.
var _spectator_defender_back_by_slot: Dictionary = {} # CardSlot Node -> card Node

var _is_multiplayer: bool = false
var _is_spectator: bool = false

# --- Added (minimal): prevent double-reporting finish in multiplayer (SPACE + Leave, etc.)
var _reported_battle_finished: bool = false
var _round_results: Array = [] # "win", "lose", "tie" from player perspective

var battle_timer: float = 10.0
var is_timer_active: bool = false

## Bot difficulty 4+: defender slot alignment during coordination timer.
var _bot_def_align_cd: float = 0.0

# Auto-return to map after battle resolves
var _auto_return_active: bool = false
var _auto_return_timer: float = 0.0
const AUTO_RETURN_DELAY := 5.0

# Spectator state
var _spectator_status_label: Label = null
var _spectator_winner_role: String = ""  # "attacker" or "defender"
var _spectator_winner_id: int = -1

## Lane indicators between paired slots (LaneArrow0..2 ↔ player slot index 0..2).
var _lane_arrow_nodes: Array = []


func _ready() -> void:
	_is_multiplayer = multiplayer.has_multiplayer_peer() and multiplayer.get_peers().size() > 0
	_is_spectator = App.is_battle_spectator
	var my_id := multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else -1
	var role := "SERVER" if multiplayer.is_server() else "CLIENT"
	if DEBUG_LOGS: print("[BattleManager] _ready() START. peer=%d role=%s is_multiplayer=%s is_spectator=%s" % [my_id, role, str(_is_multiplayer), str(_is_spectator)])
	_cache_nodes()

	if _card_scene_ui:
		if _is_spectator:
			_card_scene_ui.apply_spectator_race_textures(_player_sprite, _opponent_sprite)
		else:
			_card_scene_ui.apply_race_textures(_player_sprite, _opponent_sprite, player_default_race, opponent_default_race)

	if _is_multiplayer:
		# Server already cleared battle state before scene transition (in BattleSync).
		# Do NOT clear here — it races with the other player's sync.
		if BattleSync.battle_cards_updated.is_connected(_on_battle_cards_updated_unified):
			BattleSync.battle_cards_updated.disconnect(_on_battle_cards_updated_unified)
		BattleSync.battle_cards_updated.connect(_on_battle_cards_updated_unified)
		if BattleSync.battle_start_requested.is_connected(_on_battle_start_requested):
			BattleSync.battle_start_requested.disconnect(_on_battle_start_requested)
		BattleSync.battle_start_requested.connect(_on_battle_start_requested)
	else:
		BattleSync.clear_battle_state()

	if _is_spectator:
		if _card_scene_ui:
			_card_scene_ui.setup_spectator_ui(_timer_label, _timer_sub_label, _continue_label, _leave_button, _debug_add_card_button, _result_label, _player_slot_nodes, _opponent_slot_nodes, get_parent() if get_parent() else get_tree().current_scene)
			if not _card_scene_ui.leave_pressed.is_connected(_on_leave_pressed):
				_card_scene_ui.leave_pressed.connect(_on_leave_pressed)
		# Ask server for full battle_placed_cards, then build backs (handles late-loading spectators).
		call_deferred("_spectator_initial_sync_and_backs")
	else:
		_setup_ui()

	if not _is_spectator:
		# Wait a couple frames so CardManager has time to initialize
		await get_tree().process_frame
		await get_tree().process_frame

		if DEBUG_LOGS: print("[BattleManager] _ready() restoring cards. battle_placed_cards keys: %s" % str(BattleSync.battle_placed_cards.keys()))
		# Restore cards after CardManager is ready
		_restore_and_sync_placed_cards()

		# Wait another frame for cards to be properly registered
		await get_tree().process_frame

		# Short delay so BattleSync.battle_placed_cards is synced before we draw opponent backs (avoids wrong count with 3+ players)
		if _is_multiplayer:
			await get_tree().create_tween().tween_interval(0.2).finished
		if DEBUG_LOGS: print("[BattleManager] _ready() placing opponent backs. battle_placed_cards keys: %s" % str(BattleSync.battle_placed_cards.keys()))
		_place_opponent_backs()
		_connect_player_slot_signals()
		call_deferred("_setup_lane_arrows")

	state = State.WAITING_FOR_PLAYER

	if not _is_spectator:
		# Start timer immediately
		battle_timer = 10.0
		is_timer_active = true
		_update_timer_visibility()
		if _timer_label:
			_timer_label.text = "Countdown to Coordinate Your Combat: %d" % ceil(battle_timer)
		if DEBUG_LOGS: print("[BattleManager] _ready() DONE. state=WAITING_FOR_PLAYER, timer started")
		_bot_def_align_cd = 0.0
		# Respace hand cards after everything is set up
		if _card_manager:
			_card_manager.call_deferred("respace_hand_cards")
	else:
		if DEBUG_LOGS: print("[BattleManager] _ready() DONE. state=WAITING_FOR_PLAYER (SPECTATOR mode)")
		# Single-player bot-vs-bot spectator battles: auto-resolve after 10 seconds.
		if not _is_multiplayer:
			call_deferred("_start_singleplayer_spectator_battle_timer")


func _cache_nodes() -> void:
	_player_slot_nodes.clear()
	_opponent_slot_nodes.clear()

	var root := get_parent()
	if root == null:
		root = get_tree().current_scene

	for slot_name in player_slots:
		_player_slot_nodes.append(root.get_node_or_null(NodePath(String(slot_name))) if root else null)
	for slot_name in opponent_slots:
		_opponent_slot_nodes.append(root.get_node_or_null(NodePath(String(slot_name))) if root else null)

	_timer_label = (root.get_node_or_null(timer_label_path) if root else null) as Label
	_timer_sub_label = (root.get_node_or_null(timer_sub_label_path) if root else null) as Label
	_result_label = (root.get_node_or_null(result_label_path) if root else null) as Label
	_continue_label = (root.get_node_or_null(continue_label_path) if root else null) as Label
	if not _result_label:
		push_warning("[BattleManager] ResultLabel not found at path: %s. Result text will not be displayed." % String(result_label_path))
	if not _continue_label:
		push_warning("[BattleManager] ContinueLabel not found at path: %s. Continue hint will not be displayed." % String(continue_label_path))
	_leave_button = (root.get_node_or_null(leave_button_path) if root else null) as Button
	_debug_add_card_button = (root.get_node_or_null(debug_add_card_button_path) if root else null) as Button
	_card_manager = root.get_node_or_null("CardManager") if root else null
	_card_scene_ui = root.get_node_or_null("CardSceneUI") if root else null
	_player_sprite = (root.get_node_or_null("Player") if root else null) as Sprite2D
	_opponent_sprite = (root.get_node_or_null("Opponent") if root else null) as Sprite2D

	_lane_arrow_nodes.clear()
	if root:
		var lane_parent := root.get_node_or_null("LaneArrows")
		if lane_parent:
			for i in range(3):
				var n := lane_parent.get_node_or_null("LaneArrow%d" % i)
				if n:
					_lane_arrow_nodes.append(n)


func _setup_lane_arrows() -> void:
	## Midpoint between each paired slot row; Y nudge slightly toward player row (under center UI text band).
	if _lane_arrow_nodes.is_empty():
		return
	var bump_pairs: Array = [
		[0, 2],  # PL + OL
		[1, 1],  # PM + OM
		[2, 0],  # PR + OR
	]
	for pair_idx in range(mini(bump_pairs.size(), _lane_arrow_nodes.size())):
		var pair: Array = bump_pairs[pair_idx]
		var pidx: int = pair[0]
		var oidx: int = pair[1]
		var pslot: Node = _player_slot_nodes[pidx] if pidx < _player_slot_nodes.size() else null
		var oslot: Node = _opponent_slot_nodes[oidx] if oidx < _opponent_slot_nodes.size() else null
		if not pslot or not oslot:
			continue
		var mid: Vector2 = (pslot.global_position + oslot.global_position) * 0.5
		mid.y += 7.0
		var la: Node = _lane_arrow_nodes[pair_idx]
		if la:
			la.global_position = mid
			if la.has_method("reset_neutral"):
				la.reset_neutral()


func _restore_and_sync_placed_cards() -> void:
	## Restore from BattleStateManager.
	if not BattleStateManager:
		return

	# CHECK FOR TERRITORY BATTLE
	var tid: String = BattleStateManager.current_territory_id
	var is_territory_battle: bool = (tid != "")

	if is_territory_battle:
		if DEBUG_LOGS: print("[BattleManager] Territory Battle detected for ID: ", tid)
		var defending_slots: Dictionary = BattleStateManager.get_defending_slots(tid)
		var attacking_slots: Dictionary = BattleStateManager.get_attacking_slots(tid)
		# Determine role: defender = territory owner, attacker = otherwise
		var is_local_defender: bool = false
		var tcs: Node = get_node_or_null("/root/TerritoryClaimState")
		if tcs and tcs.has_method("get_owner_id"):
			var owner_id: Variant = tcs.call("get_owner_id", int(tid))
			var my_id: int = int(multiplayer.get_unique_id()) if multiplayer.has_multiplayer_peer() else 1
			is_local_defender = (int(owner_id) == my_id)
		# Player slots = our cards; opponent slots = other player's cards
		var player_slots_data: Dictionary
		var opponent_slots_data: Dictionary
		if is_local_defender:
			player_slots_data = defending_slots
			opponent_slots_data = attacking_slots
			if DEBUG_LOGS: print("[BattleManager] Local player is DEFENDER. Player side=defending, opponent side=attacking.")
		else:
			player_slots_data = attacking_slots
			opponent_slots_data = defending_slots
			if DEBUG_LOGS: print("[BattleManager] Local player is ATTACKER. Player side=attacking, opponent side=defending.")
		if DEBUG_LOGS: print("[BattleManager] Player slots (our side) data: ", _debug_slots_summary(player_slots_data))
		if DEBUG_LOGS: print("[BattleManager] Opponent slots (their side) data: ", _debug_slots_summary(opponent_slots_data))

		# 1. Populate opponent slots (face-down). In multiplayer use only BattleSync (in _place_opponent_backs after a short delay) to avoid wrong count from stale BSM data.
		if not _is_multiplayer:
			var back_frames: SpriteFrames = CARD_BACK_FRAMES
			var back_frame_index: int = CARD_BACK_FRAME_INDEX
			for slot_idx in range(_opponent_slot_nodes.size()):
				var slot = _opponent_slot_nodes[slot_idx]
				if not slot: continue
				var card_data = opponent_slots_data.get(int(slot_idx))
				if card_data == null: card_data = opponent_slots_data.get(str(slot_idx))
				if card_data:
					var card := CARD_SCENE.instantiate()
					get_tree().current_scene.add_child(card)
					var area := card.get_node_or_null("Card_Collision") as Area2D
					if area: area.input_pickable = false
					card.card_sprite_frames = back_frames
					card.frame_index = back_frame_index
					_opponent_cards_by_slot[slot] = card
					if slot.has_method("force_snap_card"):
						slot.force_snap_card(card)
					card.set_meta("territory_face_path", card_data.get("path", ""))
					card.set_meta("territory_face_frame", card_data.get("frame"))

		# 2. Populate player slots from player_slots_data (our cards for this battle)
		var placed: Dictionary = player_slots_data
		if not placed.is_empty():
			_restore_cards_to_slots(placed)
			if _is_multiplayer:
				for slot_idx in placed:
					var data: Dictionary = placed[slot_idx]
					var path: String = data.get("path", "")
					var frame: int = int(data.get("frame"))
					if not path.is_empty():
						BattleSync.request_place_battle_card(slot_idx, path, frame)
				if DEBUG_LOGS: print("[BattleManager] Restore complete (territory). Requesting full sync.")
				BattleSync.request_full_sync()
		return

	# Non-territory battle: use local_slots as before
	var placed: Dictionary = BattleStateManager.get_local_slots()
	if not placed.is_empty():
		_restore_cards_to_slots(placed)
		if _is_multiplayer:
			for slot_idx in placed:
				var data: Dictionary = placed[slot_idx]
				var path: String = data.get("path", "")
				var frame: int = int(data.get("frame"))
				if not path.is_empty():
					BattleSync.request_place_battle_card(slot_idx, path, frame)
			if DEBUG_LOGS: print("[BattleManager] Restore complete (non-territory). Requesting full sync.")
			BattleSync.request_full_sync()


func _debug_slots_summary(slots: Dictionary) -> String:
	## Returns a readable summary of slot_index -> { path, frame } for debug logs.
	var parts: Array[String] = []
	for idx in slots.keys():
		var data: Variant = slots[idx]
		if data is Dictionary:
			var d: Dictionary = data
			parts.append("%s: %s frame=%s" % [idx, d.get("path", ""), d.get("frame", -1)])
		else:
			parts.append("%s: %s" % [idx, str(data)])
	parts.sort()
	return "{" + ", ".join(parts) + "}" if not parts.is_empty() else "{}"


func _restore_cards_to_slots(placed: Dictionary) -> void:
	## Spawn cards from a placed-slots dictionary and place them in player slots.
	var root := get_parent()
	if not root:
		root = get_tree().current_scene
	var hand_container := root.get_node_or_null("HandCardsLayer/HandCardsContainer")
	if not hand_container:
		hand_container = root
	for slot_idx in placed:
		if slot_idx < 0 or slot_idx >= _player_slot_nodes.size():
			continue
		var slot = _player_slot_nodes[slot_idx]
		if not slot or not slot.has_method("force_snap_card"):
			continue
		var data: Dictionary = placed[slot_idx]
		var path: String = data.get("path", "")
		var frame: int = int(data.get("frame"))
		if path.is_empty():
			continue
		var frames: SpriteFrames = load(path) as SpriteFrames
		if not frames:
			continue
		var card := CARD_SCENE.instantiate()
		if not card:
			continue

		# Add card to HandCardsContainer so it renders above the UI
		hand_container.add_child(card)

		# Set card properties
		card.card_sprite_frames = frames
		card.frame_index = frame
		card.visible = true

		# Register with CardManager BEFORE snapping (so it's set up for dragging)
		# This ensures input events are connected and card is draggable
		if _card_manager:
			if _card_manager.has_method("register_card"):
				_card_manager.register_card(card)
			# Ensure card is in card_spawn_positions for tracking
			if not _card_manager.card_spawn_positions.has(card):
				_card_manager.card_spawn_positions[card] = slot.global_position

		# Now snap to slot
		slot.force_snap_card(card)

		if _card_manager:
			_card_manager.snapped_cards[card] = slot
			# Set spawn position to slot position (in case card is unsnapped later)
			if _card_manager.has_method("set_card_spawn_position"):
				_card_manager.set_card_spawn_position(card, slot.global_position)

		# Ensure the card's Area2D remains input_pickable even when snapped
		var area := card.get_node_or_null("Card_Collision") as Area2D
		if area:
			area.input_pickable = true

	# Respace hand cards after restoration
	# Wait a frame to ensure cards are properly registered
	await get_tree().process_frame
	if _card_manager:
		_card_manager.call_deferred("respace_hand_cards")


func _on_battle_cards_updated_unified() -> void:
	if _is_spectator:
		_on_spectator_battle_cards_updated()
	else:
		_on_battle_cards_updated()


func _on_battle_cards_updated() -> void:
	## Refresh opponent slots with face-down cards from remote player(s).
	var state_name: String = ["SETUP", "WAITING_FOR_PLAYER", "WAITING_FOR_ALL_READY", "FLIPPING", "RESOLVED"][clampi(state, 0, 4)]
	if state == State.WAITING_FOR_PLAYER or state == State.WAITING_FOR_ALL_READY:
		if DEBUG_LOGS: print("[BattleManager] _on_battle_cards_updated: processing (state=%s)" % state_name)
		_update_opponent_cards_from_net()
	else:
		if DEBUG_LOGS: print("[BattleManager] _on_battle_cards_updated: SKIPPED (state=%s)" % state_name)


func _on_spectator_battle_cards_updated() -> void:
	## Live-update face-down backs when attackers/defenders move cards (same RPC as fighters).
	if not _is_spectator:
		return
	var state_name: String = ["SETUP", "WAITING_FOR_PLAYER", "WAITING_FOR_ALL_READY", "FLIPPING", "RESOLVED"][clampi(state, 0, 4)]
	if state != State.WAITING_FOR_PLAYER and state != State.WAITING_FOR_ALL_READY:
		if SPECTATOR_SYNC_DEBUG:
			print("[BattleManager][Spectator] battle_cards_updated skipped (state=%s)" % state_name)
		return
	if SPECTATOR_SYNC_DEBUG:
		var mp := get_tree().get_multiplayer() if get_tree() else null
		var uid: int = mp.get_unique_id() if mp and mp.has_multiplayer_peer() else -1
		var ids := _resolve_spectator_territory_participant_ids()
		print("[BattleManager][Spectator] battle_cards_updated peer=%s keys=%s sync_att=%s sync_def=%s resolved_att=%s resolved_def=%s pending_att=%s pending_def=%s" % [
			uid,
			str(BattleSync.battle_placed_cards.keys()) if BattleSync else "?",
			str(BattleSync.territory_battle_attacker_id) if BattleSync else "?",
			str(BattleSync.territory_battle_defender_id) if BattleSync else "?",
			ids.get("attacker_id", -1),
			ids.get("defender_id", -1),
			App.pending_territory_battle_attacker_id if App else -1,
			App.pending_territory_battle_defender_id if App else -1,
		])
	_setup_spectator_card_backs()


func _spectator_initial_sync_and_backs() -> void:
	if not _is_spectator:
		return
	if _is_multiplayer and BattleSync:
		if SPECTATOR_SYNC_DEBUG:
			print("[BattleManager][Spectator] request_full_sync then setup backs")
		BattleSync.request_full_sync()
	_setup_spectator_card_backs()


func _spectator_slot_has_card(slots: Dictionary, slot_idx: int) -> bool:
	if slots.is_empty():
		return false
	var data: Variant = slots.get(slot_idx, null)
	if data == null:
		data = slots.get(str(slot_idx), null)
	if data == null:
		for k in slots.keys():
			if str(k) == str(slot_idx):
				data = slots[k]
				break
	if data == null or not (data is Dictionary):
		return false
	return not String((data as Dictionary).get("path", "")).is_empty()


func _spectator_key_matches_peer_id(raw_key: Variant, peer_id: int) -> bool:
	if raw_key == null:
		return false
	if raw_key is int:
		return int(raw_key) == peer_id
	if raw_key is float:
		return int(raw_key) == peer_id
	var as_str: String = str(raw_key)
	if as_str == str(peer_id):
		return true
	# Handle serialized numeric strings like "-101.0"
	if as_str.is_valid_float():
		return int(float(as_str)) == peer_id
	return false


func _spectator_get_placed_for_peer(peer_id: int) -> Dictionary:
	if peer_id < 0 or not BattleSync:
		return {}
	var raw: Dictionary = BattleSync.battle_placed_cards
	var v: Variant = raw.get(peer_id, null)
	if v == null:
		v = raw.get(str(peer_id), null)
	if v == null:
		for k in raw.keys():
			if _spectator_key_matches_peer_id(k, peer_id):
				v = raw[k]
				break
	if v is Dictionary:
		return (v as Dictionary).duplicate(true)
	return {}


func _spectator_should_show_back_for_side(slot_idx: int, net_side: Dictionary, bsm_side: Dictionary) -> bool:
	## Prefer networked placement when available; otherwise fall back to BSM seed state.
	if not net_side.is_empty():
		return _spectator_slot_has_card(net_side, slot_idx)
	return _spectator_slot_has_card(bsm_side, slot_idx)


func _spectator_peer_id_plausible(pid: int) -> bool:
	if pid == -1:
		return false
	# Lobby/bot ids (see PlayerDataSync.BOT_ID_BASE)
	if pid <= -95 and pid >= -110:
		return true
	if pid > 0 and pid < 1_000_000:
		return true
	return false


func _resolve_spectator_territory_participant_ids() -> Dictionary:
	## Prefer App.pending_* (set in App.enter_territory_battle); BattleSync can be wrong on some frames.
	## Ignore garbage ints (large positive) seen as stale RPC/desync values.
	var att: int = BattleSync.territory_battle_attacker_id if BattleSync else -1
	var def: int = BattleSync.territory_battle_defender_id if BattleSync else -1
	if App:
		if _spectator_peer_id_plausible(App.pending_territory_battle_attacker_id):
			att = App.pending_territory_battle_attacker_id
		if _spectator_peer_id_plausible(App.pending_territory_battle_defender_id):
			def = App.pending_territory_battle_defender_id
	if not _spectator_peer_id_plausible(def):
		def = -1
		var tid_str := BattleStateManager.current_territory_id if BattleStateManager else ""
		if not tid_str.is_empty() and str(tid_str).is_valid_int():
			var tcs := get_node_or_null("/root/TerritoryClaimState")
			if tcs and tcs.has_method("get_owner_id"):
				var ov: Variant = tcs.call("get_owner_id", int(tid_str))
				if ov != null:
					def = int(ov)
	if not _spectator_peer_id_plausible(att):
		att = -1
		var tid_str2 := BattleStateManager.current_territory_id if BattleStateManager else ""
		if App and not tid_str2.is_empty() and str(tid_str2).is_valid_int():
			var tid_i := int(tid_str2)
			if App.territory_pending_attackers.has(tid_i):
				att = int(App.territory_pending_attackers[tid_i])
	if not _spectator_peer_id_plausible(att) and BattleSync and _spectator_peer_id_plausible(BattleSync.territory_battle_attacker_id):
		att = BattleSync.territory_battle_attacker_id
	if not _spectator_peer_id_plausible(def) and BattleSync and _spectator_peer_id_plausible(BattleSync.territory_battle_defender_id):
		def = BattleSync.territory_battle_defender_id
	return {"attacker_id": att, "defender_id": def}


func _spectator_free_card_immediate(card: Node) -> void:
	if card and is_instance_valid(card):
		card.free()


func _spectator_apply_back_to_slot(slot: Node, want_back: bool, tracked: Dictionary) -> void:
	if not slot:
		return
	var existing: Variant = tracked.get(slot, null)
	var slot_name: String = String(slot.name) if slot else "<null>"
	if want_back:
		if existing and is_instance_valid(existing):
			if SPECTATOR_SYNC_DEBUG:
				print("[BattleManager][Spectator] slot %s KEEP back (id=%s)" % [slot_name, existing.get_instance_id()])
			existing.card_sprite_frames = CARD_BACK_FRAMES
			existing.frame_index = CARD_BACK_FRAME_INDEX
			if slot.has_method("force_snap_card"):
				slot.force_snap_card(existing)
			return
		var card := CARD_SCENE.instantiate()
		if not card:
			return
		get_tree().current_scene.add_child(card)
		card.set_meta("disable_card_input", true)
		var area := card.get_node_or_null("Card_Collision") as Area2D
		if area:
			area.input_pickable = false
		card.card_sprite_frames = CARD_BACK_FRAMES
		card.frame_index = CARD_BACK_FRAME_INDEX
		if slot.has_method("force_snap_card"):
			slot.force_snap_card(card)
		tracked[slot] = card
		if SPECTATOR_SYNC_DEBUG:
			print("[BattleManager][Spectator] slot %s SPAWN back (id=%s)" % [slot_name, card.get_instance_id()])
	else:
		if existing and is_instance_valid(existing):
			if SPECTATOR_SYNC_DEBUG:
				print("[BattleManager][Spectator] slot %s REMOVE back (id=%s)" % [slot_name, existing.get_instance_id()])
			if slot.has_method("unsnap_card"):
				slot.unsnap_card()
			_spectator_free_card_immediate(existing)
			tracked.erase(slot)


func _spectator_dispose_all_tracked_backs() -> void:
	for slot in _spectator_defender_back_by_slot.keys():
		var c: Variant = _spectator_defender_back_by_slot[slot]
		if slot and is_instance_valid(slot) and slot.has_method("unsnap_card") and slot.get("snapped_card") == c:
			slot.unsnap_card()
		_spectator_free_card_immediate(c as Node)
	_spectator_defender_back_by_slot.clear()
	for slot in _opponent_cards_by_slot.keys():
		var c2: Variant = _opponent_cards_by_slot[slot]
		if slot and is_instance_valid(slot) and slot.has_method("unsnap_card") and slot.get("snapped_card") == c2:
			slot.unsnap_card()
		_spectator_free_card_immediate(c2 as Node)
	_opponent_cards_by_slot.clear()


func _on_battle_start_requested() -> void:
	## Battle runs only when both players have pressed Ready in the card battle scene (not when Attack is pressed in GameIntro).
	if state != State.WAITING_FOR_PLAYER and state != State.WAITING_FOR_ALL_READY:
		return
	if App and App.game_victor_id >= 0:
		state = State.RESOLVED
		_start_auto_return()
		return

	if _is_spectator:
		_spectator_on_battle_start()
		return

	_update_timer_visibility()
	state = State.FLIPPING
	await _flip_opponent_cards_from_pool()
	# Short delay so both clients have synced opponent cards before resolving (fixes wrong result text for one player)
	await get_tree().create_tween().tween_interval(0.2).finished
	_resolve_battle()
	if _card_manager:
		_card_manager.add_attribute_indicators(_player_slot_nodes, _opponent_slot_nodes, attribute_config, attribute_indicator_font_scale, attribute_indicator_offset)
	if DEBUG_LOGS: print("[BattleManager] _on_battle_start_requested: starting bump sequence")
	await _animate_card_bump_sequence()
	if DEBUG_LOGS: print("[BattleManager] _on_battle_start_requested: bump sequence complete, showing result")
	_show_result()
	_report_battle_resolved()
	state = State.RESOLVED
	_apply_battle_resolution_state()
	if DEBUG_LOGS: print("[BattleManager] _on_battle_start_requested: calling _start_auto_return")
	_start_auto_return()


func _report_battle_resolved() -> void:
	## Report result to BattleStateManager and sync loser's card clearance to Net (multiplayer).
	var result := _get_battle_result()
	var local_won := result == "win"
	if BattleStateManager:
		BattleStateManager.record_battle_result(result, local_won)
	if _is_multiplayer and result == "lose":
		Net.request_clear_my_battle_cards()


func _update_opponent_cards_from_net() -> void:
	## Place/update face-down cards in opponent slots from BattleSync.battle_placed_cards.
	## Clear existing opponent cards first so we never show more backs than the other player has (fixes race with 3+ players).
	if not multiplayer.has_multiplayer_peer():
		return
	var my_id := multiplayer.get_unique_id()
	var other_peer_id: int = -1
	for pid in BattleSync.battle_placed_cards:
		if int(pid) != my_id:
			other_peer_id = int(pid)
			break
	if other_peer_id == -1:
		if DEBUG_LOGS: print("[BattleManager] _update_opponent_cards_from_net: no opponent found (my_id=%d, keys=%s). Clearing." % [my_id, str(BattleSync.battle_placed_cards.keys())])
		_clear_opponent_slot_cards()
		return
	var other_cards: Dictionary = BattleSync.battle_placed_cards.get(other_peer_id, {})
	if DEBUG_LOGS: print("[BattleManager] _update_opponent_cards_from_net: my_id=%d opponent=%d opponent_slots=%s" % [my_id, other_peer_id, str(other_cards.keys())])
	_clear_opponent_slot_cards()
	var back_frames: SpriteFrames = CARD_BACK_FRAMES
	var back_frame_index: int = CARD_BACK_FRAME_INDEX
	for slot_idx in range(_opponent_slot_nodes.size()):
		var slot = _opponent_slot_nodes[slot_idx]
		if not slot:
			continue
		if other_cards.has(slot_idx):
			var existing = _opponent_cards_by_slot.get(slot, null)
			if existing and is_instance_valid(existing):
				existing.card_sprite_frames = back_frames
				existing.frame_index = back_frame_index
				if slot.has_method("force_snap_card"):
					slot.force_snap_card(existing)
			else:
				var card := CARD_SCENE.instantiate()
				get_tree().current_scene.add_child(card)
				card.set_meta("disable_card_input", true)
				var area := card.get_node_or_null("Card_Collision") as Area2D
				if area:
					area.input_pickable = false
				card.card_sprite_frames = back_frames
				card.frame_index = back_frame_index
				if slot.has_method("force_snap_card"):
					slot.force_snap_card(card)
				_opponent_cards_by_slot[slot] = card
		else:
			var existing = _opponent_cards_by_slot.get(slot, null)
			if existing and is_instance_valid(existing):
				if slot.has_method("unsnap_card"):
					slot.unsnap_card()
				existing.queue_free()
				_opponent_cards_by_slot.erase(slot)


func _clear_opponent_slot_cards() -> void:
	for slot in _opponent_slot_nodes:
		if not slot:
			continue
		var existing = _opponent_cards_by_slot.get(slot, null)
		if existing and is_instance_valid(existing):
			if slot.has_method("unsnap_card"):
				slot.unsnap_card()
			existing.queue_free()
		_opponent_cards_by_slot.erase(slot)


func _setup_spectator_card_backs() -> void:
	## Spectators see the defender's battle layout with all cards face-down and non-interactive.
	## Incrementally update per slot and use immediate free() so queue_free cannot stack ghost cards.
	if not _is_spectator:
		return
	var ids: Dictionary = _resolve_spectator_territory_participant_ids()
	var defender_id: int = int(ids.get("defender_id", -1))
	var attacker_id: int = int(ids.get("attacker_id", -1))

	var tid: String = BattleStateManager.current_territory_id if BattleStateManager else ""
	var bsm_def: Dictionary = BattleStateManager.get_defending_slots(tid) if (BattleStateManager and not tid.is_empty()) else {}
	var bsm_att: Dictionary = BattleStateManager.get_attacking_slots(tid) if (BattleStateManager and not tid.is_empty()) else {}
	var net_def: Dictionary = _spectator_get_placed_for_peer(defender_id)
	var net_att: Dictionary = _spectator_get_placed_for_peer(attacker_id)

	if SPECTATOR_SYNC_DEBUG:
		print("[BattleManager][Spectator] setup backs tid=%s def_id=%s att_id=%s net_def_keys=%s net_att_keys=%s bsm_def=%s bsm_att=%s tracked_def=%d tracked_att=%d" % [
			tid,
			defender_id,
			attacker_id,
			str(net_def.keys()),
			str(net_att.keys()),
			_debug_slots_summary(bsm_def),
			_debug_slots_summary(bsm_att),
			_spectator_defender_back_by_slot.size(),
			_opponent_cards_by_slot.size(),
		])

	# Bottom row = defender vantage (player slots); top = attacker (opponent slots).
	for slot_idx in range(_player_slot_nodes.size()):
		var slot_p: Node = _player_slot_nodes[slot_idx]
		if not slot_p:
			continue
		var want_def: bool = _spectator_should_show_back_for_side(slot_idx, net_def, bsm_def)
		_spectator_apply_back_to_slot(slot_p, want_def, _spectator_defender_back_by_slot)

	for slot_idx in range(_opponent_slot_nodes.size()):
		var slot_o: Node = _opponent_slot_nodes[slot_idx]
		if not slot_o:
			continue
		var want_att: bool = _spectator_should_show_back_for_side(slot_idx, net_att, bsm_att)
		_spectator_apply_back_to_slot(slot_o, want_att, _opponent_cards_by_slot)


func _setup_ui() -> void:
	if _timer_label:
		_timer_label.visible = false
	if _timer_sub_label:
		_timer_sub_label.visible = false

	if _result_label:
		_result_label.visible = false
	if _continue_label:
		_continue_label.visible = false

	if _leave_button:
		_leave_button.visible = true
		if not _leave_button.pressed.is_connected(_on_leave_pressed):
			_leave_button.pressed.connect(_on_leave_pressed)

	if _debug_add_card_button:
		_debug_add_card_button.visible = show_debug_add_card_button
		if show_debug_add_card_button and not _debug_add_card_button.pressed.is_connected(_on_debug_add_card_pressed):
			_debug_add_card_button.pressed.connect(_on_debug_add_card_pressed)


func _connect_player_slot_signals() -> void:
	for idx in range(_player_slot_nodes.size()):
		var slot = _player_slot_nodes[idx]
		if not slot:
			continue
		if slot.has_signal("card_snapped"):
			if not slot.card_snapped.is_connected(_on_card_snapped_to_slot):
				slot.card_snapped.connect(_on_card_snapped_to_slot.bind(idx))
		if slot.has_signal("card_unsnapped"):
			if not slot.card_unsnapped.is_connected(_on_card_unsnapped_from_slot):
				slot.card_unsnapped.connect(_on_card_unsnapped_from_slot.bind(idx))


func _on_card_snapped_to_slot(card: Node, slot_idx: int) -> void:
	if state != State.WAITING_FOR_PLAYER and state != State.WAITING_FOR_ALL_READY:
		return

	# Get card data
	var frames: SpriteFrames = card.card_sprite_frames
	var fidx: int = card.frame_index

	if frames and frames.resource_path:
		# Persist locally via BattleStateManager
		if BattleStateManager:
			BattleStateManager.set_local_slot(slot_idx, frames.resource_path, fidx)

		# Sync in multiplayer
		if _is_multiplayer:
			BattleSync.request_place_battle_card(slot_idx, frames.resource_path, fidx)
		else:
			_persist_local_placed_cards()

		# Respace hand cards (which will also update deck visibility)
		if _card_manager:
			_card_manager.call_deferred("respace_hand_cards")

	_update_timer_visibility()
	# Bot reacts after a short delay when player changes lane setup.
	_bot_def_align_cd = _BOT_BATTLE_BEHAVIOR.ALIGN_MOVE_DELAY_SEC


func _on_card_unsnapped_from_slot(card: Node, slot_idx: int) -> void:
	if state != State.WAITING_FOR_PLAYER and state != State.WAITING_FOR_ALL_READY:
		return

	# Remove from persistence
	if BattleStateManager:
		BattleStateManager.set_local_slot(slot_idx, "", 0)

	# Sync in multiplayer
	if _is_multiplayer:
		BattleSync.request_remove_battle_card(slot_idx)
	else:
		_persist_local_placed_cards()

		# Respace hand cards (which will also update deck visibility)
		if _card_manager:
			_card_manager.call_deferred("respace_hand_cards")

	# Reset deck spawned flag so it can be used again
	_update_timer_visibility()
	# Bot reacts after a short delay when player changes lane setup.
	_bot_def_align_cd = _BOT_BATTLE_BEHAVIOR.ALIGN_MOVE_DELAY_SEC


func _player_ready() -> bool:
	for slot in _player_slot_nodes:
		if not slot:
			return false
		if not slot.has_card:
			return false
		if slot.snapped_card == null:
			return false
	return true


func _update_timer_visibility() -> void:
	var visible_now = (state == State.WAITING_FOR_PLAYER and is_timer_active)
	if _timer_label:
		_timer_label.visible = visible_now
	if _timer_sub_label:
		_timer_sub_label.visible = visible_now

func _process(delta: float) -> void:
	if App and App.game_victor_id >= 0 and state != State.RESOLVED:
		# Game already has a winner; skip unresolved battles.
		state = State.RESOLVED
		is_timer_active = false
		_update_timer_visibility()
		_start_auto_return()
		return
	# Auto-return to map countdown
	if _auto_return_active:
		_auto_return_timer -= delta
		if _auto_return_timer <= 0.0:
			_auto_return_active = false
			_auto_leave_battle()
			return

	if state != State.WAITING_FOR_PLAYER:
		return

	var timer_positive := is_timer_active and battle_timer > 0.0
	# Stop bot alignment shortly before timeout so final player adjustments remain stable.
	var align_window_open := is_timer_active and battle_timer > _BOT_BATTLE_BEHAVIOR.POST_TIMER_GRACE_SEC
	if align_window_open:
		var run_align := (not _is_multiplayer) or (multiplayer.has_multiplayer_peer() and multiplayer.is_server())
		if run_align and not _is_spectator:
			_bot_def_align_cd -= delta
			if _bot_def_align_cd <= 0.0:
				var tid_str: String = BattleStateManager.current_territory_id if BattleStateManager else ""
				if _BOT_BATTLE_BEHAVIOR.should_run_defender_alignment(
					_is_spectator,
					_player_slot_nodes,
					_opponent_slot_nodes,
					_opponent_cards_by_slot,
					tid_str,
					_is_local_defender()
				):
					var mv: Array = _BOT_BATTLE_BEHAVIOR.get_next_opponent_slot_move_for_alignment(
						_player_slot_nodes,
						_opponent_slot_nodes,
						_opponent_cards_by_slot
					)
					if not mv.is_empty() and _apply_opponent_slot_move_for_bot_align(int(mv[0]), int(mv[1])):
						_bot_def_align_cd = _BOT_BATTLE_BEHAVIOR.ALIGN_MOVE_DELAY_SEC

	if is_timer_active:
		battle_timer -= delta
		if _timer_label:
			_timer_label.text = "Countdown to Coordinate Your Combat: %d" % ceil(max(0, battle_timer))

		if battle_timer <= 0.0:
			is_timer_active = false
			_update_timer_visibility()
			_on_battle_timer_expired()
	elif not timer_positive:
		return


func _on_battle_timer_expired() -> void:
	## When the player countdown reaches zero: stop any active drag, snap the dragged card into
	## the nearest available card slot, disable further dragging, then start battle resolution
	## after a short delay so the player can see the lock-in.
	if _card_manager:
		_card_manager.auto_snap_dragged_card()
	if _card_manager:
		_card_manager.disable_dragging()
	await get_tree().create_tween().tween_interval(0.5).finished
	_trigger_battle_start()

func _trigger_battle_start() -> void:
	if state != State.WAITING_FOR_PLAYER:
		return
	if App and App.game_victor_id >= 0:
		state = State.RESOLVED
		_start_auto_return()
		return

	if _is_multiplayer:
		BattleSync.request_battle_ready()
		state = State.WAITING_FOR_ALL_READY
		return

	state = State.FLIPPING
	await _flip_opponent_cards_from_pool()
	await get_tree().create_tween().tween_interval(0.2).finished
	_resolve_battle()
	if _card_manager:
		_card_manager.add_attribute_indicators(_player_slot_nodes, _opponent_slot_nodes, attribute_config, attribute_indicator_font_scale, attribute_indicator_offset)
	if DEBUG_LOGS: print("[BattleManager] _trigger_battle_start: starting bump sequence")
	await _animate_card_bump_sequence()
	if DEBUG_LOGS: print("[BattleManager] _trigger_battle_start: bump sequence complete, showing result")
	_show_result()
	_report_battle_resolved()
	state = State.RESOLVED
	_apply_battle_resolution_state()
	if DEBUG_LOGS: print("[BattleManager] _trigger_battle_start: calling _start_auto_return")
	_start_auto_return()


func _animate_card_bump_sequence() -> void:
	## Sequential bump: PL+OL, then PM+OM, then PR+OR. Player cards move up, opponent cards move down.
	## After each bump the round loser's card disappears; on tie the attacker's card disappears (defender keeps).
	## After all bumps, if the overall battle loser still has visible cards, the winner's remaining cards bump once more and then the loser's remaining cards vanish.
	## Pairing: player_slots=[PL(0), PM(1), PR(2)], opponent_slots=[OR(0), OM(1), OL(2)]
	if DEBUG_LOGS: print("[BattleManager] _animate_card_bump_sequence START")
	var bump_pairs: Array = [
		[0, 2],  # PL + OL
		[1, 1],  # PM + OM
		[2, 0],  # PR + OR
	]
	var bump_distance := 10.0
	var bump_duration := 0.30

	var local_is_defender := _is_local_defender()
	if DEBUG_LOGS: print("[BattleManager] local_is_defender=%s, _round_results=%s" % [str(local_is_defender), str(_round_results)])

	for la in _lane_arrow_nodes:
		if la and la.has_method("reset_neutral"):
			la.reset_neutral()

	for pair in bump_pairs:
		var p_idx: int = pair[0]
		var o_idx: int = pair[1]
		var pslot: Node = _player_slot_nodes[p_idx] if p_idx < _player_slot_nodes.size() else null
		var oslot: Node = _opponent_slot_nodes[o_idx] if o_idx < _opponent_slot_nodes.size() else null
		var pcard: Node = pslot.snapped_card if pslot and pslot.get("snapped_card") else null
		var ocard: Node = _opponent_cards_by_slot.get(oslot, null) if oslot else null

		var has_pcard: bool = pcard != null and is_instance_valid(pcard)
		var has_ocard: bool = ocard != null and is_instance_valid(ocard)
		if DEBUG_LOGS: print("[BattleManager] Bump pair p_idx=%d o_idx=%d has_pcard=%s has_ocard=%s" % [p_idx, o_idx, str(has_pcard), str(has_ocard)])

		if not has_pcard and not has_ocard:
			if p_idx < _lane_arrow_nodes.size():
				var la_skip: Node = _lane_arrow_nodes[p_idx]
				if la_skip:
					la_skip.visible = false
			if DEBUG_LOGS: print("[BattleManager] Skipping bump pair %d — no cards" % p_idx)
			continue

		# Record starting positions before bump
		var p_start: Vector2 = pcard.global_position if has_pcard else Vector2.ZERO
		var o_start: Vector2 = ocard.global_position if has_ocard else Vector2.ZERO

		# Bump out
		var tween: Tween = create_tween()
		tween.set_ease(Tween.EASE_OUT)
		tween.set_trans(Tween.TRANS_CUBIC)
		tween.set_parallel(true)

		if has_pcard:
			tween.tween_property(pcard, "global_position", p_start + Vector2(0, -bump_distance), bump_duration)
		if has_ocard:
			tween.tween_property(ocard, "global_position", o_start + Vector2(0, bump_distance), bump_duration)

		await tween.finished
		if DEBUG_LOGS: print("[BattleManager] Bump out finished for pair p_idx=%d" % p_idx)

		# Return to starting positions
		var return_tween: Tween = create_tween()
		return_tween.set_ease(Tween.EASE_IN_OUT)
		return_tween.set_trans(Tween.TRANS_CUBIC)
		return_tween.set_parallel(true)

		var return_has_targets := false
		if has_pcard and is_instance_valid(pcard):
			return_tween.tween_property(pcard, "global_position", p_start, bump_duration)
			return_has_targets = true
		if has_ocard and is_instance_valid(ocard):
			return_tween.tween_property(ocard, "global_position", o_start, bump_duration)
			return_has_targets = true

		if return_has_targets:
			await return_tween.finished
		else:
			return_tween.kill()
			if DEBUG_LOGS: print("[BattleManager] Return tween had no targets for pair p_idx=%d, killed" % p_idx)
		if DEBUG_LOGS: print("[BattleManager] Bump return finished for pair p_idx=%d" % p_idx)

		# Determine round result for this player slot index
		var round_result: String = _round_results[p_idx] if p_idx < _round_results.size() else "tie"
		if DEBUG_LOGS: print("[BattleManager] Round result for p_idx=%d: %s" % [p_idx, round_result])

		if round_result == "win":
			if has_ocard and is_instance_valid(ocard):
				await _grey_out_card(ocard)
		elif round_result == "lose":
			if has_pcard and is_instance_valid(pcard):
				await _grey_out_card(pcard)
		else:
			if local_is_defender:
				if has_ocard and is_instance_valid(ocard):
					await _grey_out_card(ocard)
			else:
				if has_pcard and is_instance_valid(pcard):
					await _grey_out_card(pcard)

		if p_idx < _lane_arrow_nodes.size():
			var la_res: Node = _lane_arrow_nodes[p_idx]
			if la_res and la_res.has_method("apply_lane_result"):
				var lane_col := Color.WHITE
				if round_result != "tie":
					if _card_scene_ui:
						var win_race: String = ""
						if round_result == "win":
							win_race = _card_scene_ui.get_resolved_battle_player_race(int(player_default_race))
						else:
							win_race = _card_scene_ui.get_resolved_battle_opponent_race(int(opponent_default_race))
						lane_col = _card_scene_ui.get_race_color(win_race)
					elif App:
						var wr: String = ""
						if round_result == "win":
							for p in App.game_players:
								if p.get("is_local", false):
									wr = str(p.get("race", "Fairy"))
									break
							if wr.is_empty() or wr == "Unknown":
								wr = App.selected_race if App.selected_race else "Fairy"
						else:
							wr = String(App.current_battle_metadata.get("opponent_race", "Fairy"))
						lane_col = App.get_race_color(wr)
				la_res.apply_lane_result(round_result, lane_col)

		if DEBUG_LOGS: print("[BattleManager] Fade complete for pair p_idx=%d" % p_idx)
		# Brief pause between pairs
		await get_tree().create_tween().tween_interval(0.25).finished

	# After all per-round bumps: check if the overall loser still has visible cards
	var overall_result := _get_battle_result()
	if DEBUG_LOGS: print("[BattleManager] All bumps done. overall_result=%s" % overall_result)
	if overall_result == "lose":
		await _final_winner_bump_and_clear("opponent")
	elif overall_result == "win":
		await _final_winner_bump_and_clear("player")
	elif overall_result == "tie":
		if local_is_defender:
			await _final_winner_bump_and_clear("player")
		else:
			await _final_winner_bump_and_clear("opponent")
	await _show_destroyed_card_markers()
	if DEBUG_LOGS: print("[BattleManager] _animate_card_bump_sequence DONE")


func _is_local_defender() -> bool:
	## Check if the local player is the defender in the current battle.
	var tid: String = BattleStateManager.current_territory_id if BattleStateManager else ""
	if tid.is_empty() or tid.begins_with("battle_"):
		return true  # Non-territory battles: local player is treated as defender by default
	var tcs: Node = get_node_or_null("/root/TerritoryClaimState")
	if tcs and tcs.has_method("get_owner_id"):
		var owner_id: Variant = tcs.call("get_owner_id", int(tid))
		var my_id: int = multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
		return int(owner_id) == my_id
	return true


func _apply_opponent_slot_move_for_bot_align(from_o: int, to_o: int) -> bool:
	## Move defender (opponent) card from one slot index to another; updates BattleStateManager (+ sync in MP).
	if from_o < 0 or from_o >= _opponent_slot_nodes.size():
		return false
	if to_o < 0 or to_o >= _opponent_slot_nodes.size():
		return false
	var sa: Node = _opponent_slot_nodes[from_o]
	var sb: Node = _opponent_slot_nodes[to_o]
	if not sa or not sb:
		return false
	var ca: Node = _opponent_cards_by_slot.get(sa, null)
	if ca == null or not is_instance_valid(ca):
		return false
	var cb: Node = _opponent_cards_by_slot.get(sb, null)
	if cb != null and is_instance_valid(cb):
		return false
	if sa.has_method("unsnap_card"):
		sa.unsnap_card()
	_opponent_cards_by_slot.erase(sa)
	if sb.has_method("force_snap_card"):
		sb.force_snap_card(ca)
	else:
		ca.global_position = sb.global_position
		sb.set("has_card", true)
		sb.set("snapped_card", ca)
	_opponent_cards_by_slot[sb] = ca
	_sync_defending_slots_after_opponent_swap(from_o, to_o)
	return true


func _sync_defending_slots_after_opponent_swap(from_idx: int, to_idx: int) -> void:
	if not BattleStateManager:
		return
	var tid: String = BattleStateManager.current_territory_id
	if tid.is_empty():
		return
	var d: Dictionary = BattleStateManager.get_defending_slots(tid)
	var moved: Variant = d.get(from_idx)
	if moved == null:
		moved = d.get(str(from_idx))
	if not (moved is Dictionary):
		return
	var path_m: String = String(moved.get("path", ""))
	if path_m.is_empty():
		return
	var newd: Dictionary = {}
	for k in d.keys():
		var ki: int = int(k) if str(k).is_valid_int() else -1
		if ki < 0:
			continue
		if ki == from_idx:
			continue
		if ki == to_idx:
			continue
		var entry: Variant = d[k]
		if entry is Dictionary:
			newd[ki] = entry
	newd[to_idx] = moved
	BattleStateManager.set_defending_slots(tid, newd)
	if _is_multiplayer and multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		var tcs: Node = get_node_or_null("/root/TerritoryClaimState")
		if tcs and tcs.has_method("get_owner_id"):
			var defender_id: int = int(tcs.call("get_owner_id", int(tid)))
			BattleSync.host_sync_bot_defender_slots(defender_id, newd)


func _grey_out_card(card: Node) -> void:
	## Smoothly desaturate a losing card to grey.
	if not card or not is_instance_valid(card):
		return
	var grey := Color(0.35, 0.35, 0.35, 1.0)
	var grey_tween: Tween = create_tween()
	grey_tween.tween_property(card, "modulate", grey, 0.3)
	await grey_tween.finished


func _show_destroyed_card_markers() -> void:
	## Add a red X over cards that are actually destroyed by battle rules.
	var destroyed_cards := _collect_destroyed_cards_for_visuals()
	for card in destroyed_cards:
		_add_destroyed_marker(card)
	# Small hold so players can read the marker before result text/return.
	if not destroyed_cards.is_empty():
		await get_tree().create_tween().tween_interval(0.2).finished


func _collect_destroyed_cards_for_visuals() -> Array:
	var destroyed: Array = []
	var overall_result := _get_battle_result() # local perspective
	var local_is_defender := _is_local_defender()
	var attacker_won := false
	if local_is_defender:
		attacker_won = (overall_result == "lose")
	else:
		attacker_won = (overall_result == "win")

	# Track attacker side destruction by lane (losing/tied lanes) or all cards.
	var attacker_destroy_all := not attacker_won
	var defender_destroy_all := attacker_won

	for p_idx in range(mini(_player_slot_nodes.size(), 3)):
		var round_result: String = _round_results[p_idx] if p_idx < _round_results.size() else "tie"
		var o_idx := 2 - p_idx
		var pslot: Node = _player_slot_nodes[p_idx]
		var oslot: Node = _opponent_slot_nodes[o_idx] if o_idx >= 0 and o_idx < _opponent_slot_nodes.size() else null
		var pcard: Node = pslot.snapped_card if pslot and pslot.get("snapped_card") else null
		var ocard: Node = _opponent_cards_by_slot.get(oslot, null) if oslot else null

		var player_is_attacker := not local_is_defender
		var attacker_card: Node = pcard if player_is_attacker else ocard
		var defender_card: Node = ocard if player_is_attacker else pcard

		if attacker_destroy_all:
			if attacker_card and is_instance_valid(attacker_card) and attacker_card.visible:
				if not destroyed.has(attacker_card):
					destroyed.append(attacker_card)
		else:
			# Attacker won: attacker only loses cards from losing lanes; ties also destroy attacker card.
			var attacker_lost_lane := false
			if player_is_attacker:
				attacker_lost_lane = (round_result == "lose" or round_result == "tie")
			else:
				attacker_lost_lane = (round_result == "win" or round_result == "tie")
			if attacker_lost_lane and attacker_card and is_instance_valid(attacker_card) and attacker_card.visible:
				if not destroyed.has(attacker_card):
					destroyed.append(attacker_card)

		if defender_destroy_all:
			if defender_card and is_instance_valid(defender_card) and defender_card.visible:
				if not destroyed.has(defender_card):
					destroyed.append(defender_card)
		else:
			# Defender won: defender only loses cards from losing lanes.
			var defender_lost_lane := false
			if player_is_attacker:
				defender_lost_lane = (round_result == "win")
			else:
				defender_lost_lane = (round_result == "lose")
			if defender_lost_lane and defender_card and is_instance_valid(defender_card) and defender_card.visible:
				if not destroyed.has(defender_card):
					destroyed.append(defender_card)

	return destroyed


func _add_destroyed_marker(card: Node) -> void:
	if not card or not is_instance_valid(card):
		return
	if card.get_node_or_null("DestroyedMarker"):
		return

	var marker := Node2D.new()
	marker.name = "DestroyedMarker"
	marker.z_index = 100

	var shadow_a := Line2D.new()
	shadow_a.width = 10.0
	shadow_a.default_color = Color(0.15, 0.0, 0.0, 0.85)
	shadow_a.add_point(Vector2(-32, -46))
	shadow_a.add_point(Vector2(32, 46))
	shadow_a.z_index = 0
	marker.add_child(shadow_a)

	var shadow_b := Line2D.new()
	shadow_b.width = 10.0
	shadow_b.default_color = Color(0.15, 0.0, 0.0, 0.85)
	shadow_b.add_point(Vector2(-32, 46))
	shadow_b.add_point(Vector2(32, -46))
	shadow_b.z_index = 0
	marker.add_child(shadow_b)

	var line_a := Line2D.new()
	line_a.width = 6.0
	line_a.default_color = Color(1.0, 0.12, 0.12, 0.95)
	line_a.add_point(Vector2(-32, -46))
	line_a.add_point(Vector2(32, 46))
	line_a.z_index = 1
	marker.add_child(line_a)

	var line_b := Line2D.new()
	line_b.width = 6.0
	line_b.default_color = Color(1.0, 0.12, 0.12, 0.95)
	line_b.add_point(Vector2(-32, 46))
	line_b.add_point(Vector2(32, -46))
	line_b.z_index = 1
	marker.add_child(line_b)

	card.add_child(marker)


func _final_winner_bump_and_clear(winner_side: String) -> void:
	## After per-round results, if the overall loser still has visible cards:
	## 1. Winner's remaining visible cards all bump at once (player up / opponent down).
	## 2. Then the loser's remaining visible cards vanish.
	if DEBUG_LOGS: print("[BattleManager] _final_winner_bump_and_clear START winner_side=%s" % winner_side)
	var bump_distance := 10.0
	var bump_duration := 0.30

	var winner_cards: Array = []
	var loser_cards: Array = []

	if winner_side == "opponent":
		for slot in _opponent_slot_nodes:
			var card: Node = _opponent_cards_by_slot.get(slot, null)
			if card and is_instance_valid(card) and card.visible:
				winner_cards.append(card)
		for slot in _player_slot_nodes:
			if slot and slot.get("snapped_card"):
				var card: Node = slot.snapped_card
				if card and is_instance_valid(card) and card.visible:
					loser_cards.append(card)
	else:
		for slot in _player_slot_nodes:
			if slot and slot.get("snapped_card"):
				var card: Node = slot.snapped_card
				if card and is_instance_valid(card) and card.visible:
					winner_cards.append(card)
		for slot in _opponent_slot_nodes:
			var card: Node = _opponent_cards_by_slot.get(slot, null)
			if card and is_instance_valid(card) and card.visible:
				loser_cards.append(card)

	if DEBUG_LOGS: print("[BattleManager] winner_cards=%d loser_cards=%d" % [winner_cards.size(), loser_cards.size()])

	if loser_cards.is_empty():
		if DEBUG_LOGS: print("[BattleManager] _final_winner_bump_and_clear: no loser cards, returning early")
		return

	# Winner cards bump out then return
	if not winner_cards.is_empty():
		var start_positions: Array = []
		for card in winner_cards:
			start_positions.append(card.global_position)

		var bump_tween: Tween = create_tween()
		bump_tween.set_ease(Tween.EASE_OUT)
		bump_tween.set_trans(Tween.TRANS_CUBIC)
		bump_tween.set_parallel(true)
		var bump_dir: float = -bump_distance if winner_side == "player" else bump_distance
		for card in winner_cards:
			if is_instance_valid(card):
				bump_tween.tween_property(card, "global_position", card.global_position + Vector2(0, bump_dir), bump_duration)
		await bump_tween.finished
		if DEBUG_LOGS: print("[BattleManager] _final_winner_bump_and_clear: winner bump done")

		var return_tween: Tween = create_tween()
		return_tween.set_ease(Tween.EASE_IN_OUT)
		return_tween.set_trans(Tween.TRANS_CUBIC)
		return_tween.set_parallel(true)
		var return_count := 0
		for i in range(winner_cards.size()):
			if is_instance_valid(winner_cards[i]):
				return_tween.tween_property(winner_cards[i], "global_position", start_positions[i], bump_duration)
				return_count += 1
		if return_count > 0:
			await return_tween.finished
		else:
			return_tween.kill()
		if DEBUG_LOGS: print("[BattleManager] _final_winner_bump_and_clear: winner return done")

	# Loser's remaining cards grey out
	if DEBUG_LOGS: print("[BattleManager] _final_winner_bump_and_clear: greying %d loser cards" % loser_cards.size())
	var grey := Color(0.35, 0.35, 0.35, 1.0)
	var grey_tween: Tween = create_tween()
	grey_tween.set_parallel(true)
	var grey_count := 0
	for card in loser_cards:
		if is_instance_valid(card):
			grey_tween.tween_property(card, "modulate", grey, 0.3)
			grey_count += 1
	if grey_count > 0:
		await grey_tween.finished
	else:
		grey_tween.kill()
	await get_tree().create_tween().tween_interval(0.15).finished
	if DEBUG_LOGS: print("[BattleManager] _final_winner_bump_and_clear DONE")


func _place_opponent_backs() -> void:
	# Create a non-draggable card in each opponent slot, showing the deck back.
	# In multiplayer, opponent cards are placed by _update_opponent_cards_from_net when sync arrives.
	if _is_multiplayer:
		_update_opponent_cards_from_net()
		return
	var back_frames: SpriteFrames = CARD_BACK_FRAMES
	var back_frame_index: int = CARD_BACK_FRAME_INDEX

	var is_sp_territory := BattleStateManager and BattleStateManager.current_territory_id != ""

	for slot in _opponent_slot_nodes:
		if not slot:
			continue

		# If there's already an opponent card, just update it.
		var existing = _opponent_cards_by_slot.get(slot, null)
		if existing and is_instance_valid(existing):
			existing.card_sprite_frames = back_frames
			existing.frame_index = back_frame_index
			continue

		# In single-player territory battles, _restore_and_sync_placed_cards already
		# created cards for slots with real data. Don't fill empty slots with phantom backs.
		if is_sp_territory:
			continue

		var card := CARD_SCENE.instantiate()
		get_tree().current_scene.add_child(card)
		card.set_meta("disable_card_input", true)

		# Ensure it's not interactive.
		var area := card.get_node_or_null("Card_Collision") as Area2D
		if area:
			area.input_pickable = false

		card.card_sprite_frames = back_frames
		card.frame_index = back_frame_index

		# Force-place into the opponent slot (ignoring can_snap).
		if slot.has_method("force_snap_card"):
			slot.force_snap_card(card)
		else:
			# Fallback: place visually at slot center.
			card.global_position = slot.global_position
			slot.has_card = true
			slot.snapped_card = card

		_opponent_cards_by_slot[slot] = card


func _flip_opponent_cards_from_pool() -> void:
	var chosen: Dictionary = {} # slot -> {frames, frame_index}

	if _is_multiplayer:
		# Reveal actual opponent cards based on BattleSync.battle_placed_cards.
		if not multiplayer.has_multiplayer_peer():
			return
		var my_id := multiplayer.get_unique_id()
		var other_peer_id: int = -1
		for pid in BattleSync.battle_placed_cards:
			if int(pid) != my_id:
				other_peer_id = int(pid)
				break
		if DEBUG_LOGS: print("[BattleManager] _flip_opponent_cards: my_id=%d other_peer=%d all_keys=%s" % [my_id, other_peer_id, str(BattleSync.battle_placed_cards.keys())])
		if other_peer_id != -1:
			var other_cards: Dictionary = BattleSync.battle_placed_cards.get(other_peer_id, {})
			if DEBUG_LOGS: print("[BattleManager] _flip_opponent_cards: opponent slot keys=%s" % str(other_cards.keys()))
			for slot_idx in range(_opponent_slot_nodes.size()):
				var slot = _opponent_slot_nodes[slot_idx]
				if not slot or not other_cards.has(slot_idx):
					continue
				var data: Dictionary = other_cards[slot_idx]
				var path: String = data.get("path", "")
				var fidx: int = int(data.get("frame"))
				if not path.is_empty():
					var frames: SpriteFrames = load(path) as SpriteFrames
					if frames:
						chosen[slot] = {"frames": frames, "frame_index": fidx}
		if DEBUG_LOGS: print("[BattleManager] _flip_opponent_cards: %d cards chosen for flip" % chosen.size())

	# Single-player territory battle override:
	# If cards were already placed by _restore_and_sync_placed_cards (stored in _opponent_cards_by_slot)
	# and have metadata, we use that instead of random pool.
	if not _is_multiplayer and BattleStateManager and BattleStateManager.current_territory_id != "":
		for slot in _opponent_slot_nodes:
			if not slot: continue
			var card = _opponent_cards_by_slot.get(slot, null)
			if card and card.has_meta("territory_face_path"):
				var path: String = card.get_meta("territory_face_path", "")
				var fidx: int = int(card.get_meta("territory_face_frame", 0))
				if not path.is_empty():
					var frames: SpriteFrames = load(path) as SpriteFrames
					if frames:
						chosen[slot] = {"frames": frames, "frame_index": fidx}

	# If we have no known opponent cards to reveal, keep backs as-is.
	if chosen.is_empty():
		# No known opponent cards to reveal; keep backs as-is.
		return

	# Animate: backs go up offscreen, swap, then faces come down into slots.
	var tween := create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_parallel(true)

	for slot in _opponent_slot_nodes:
		var card = _opponent_cards_by_slot.get(slot, null)
		if card and is_instance_valid(card):
			var off_pos := Vector2(slot.global_position.x, offscreen_y)
			tween.tween_property(card, "global_position", off_pos, flip_up_duration)

	tween.set_parallel(false)
	tween.tween_callback(func ():
		for slot in _opponent_slot_nodes:
			var card = _opponent_cards_by_slot.get(slot, null)
			if not (card and is_instance_valid(card)):
				continue
			var def = chosen.get(slot, null)
			if def == null:
				continue
			var frames: SpriteFrames = def.get("frames")
			var fidx: int = int(def.get("frame_index"))
			if frames:
				card.card_sprite_frames = frames
				card.frame_index = fidx
			# Ensure it's just offscreen before dropping back down.
			card.global_position = Vector2(slot.global_position.x, offscreen_y)
	)

	tween.set_parallel(true)
	for slot in _opponent_slot_nodes:
		var card = _opponent_cards_by_slot.get(slot, null)
		if card and is_instance_valid(card):
			tween.tween_property(card, "global_position", slot.global_position, flip_down_duration)

	await tween.finished


func _resolve_battle() -> void:
	## Battle must only be resolved after both players press Ready in the card battle scene.
	## Do not resolve when Attack is pressed in GameIntro; only resolve when we've transitioned to FLIPPING via Ready.
	## Allow WAITING_FOR_ALL_READY so defender still gets correct result if they reach this before state is FLIPPING (timing/race).
	if state != State.FLIPPING and state != State.WAITING_FOR_ALL_READY:
		if _result_label:
			_result_label.text = "Tie (0)"
		if DEBUG_LOGS: print("[BattleManager] _resolve_battle: early return (state=%s), set result to Tie (0)" % state)
		return
	if state == State.WAITING_FOR_ALL_READY:
		state = State.FLIPPING
	# Pairing is fixed by array ordering:
	# PR vs OR, PM vs OM, PL vs OL
	# Determine per-pair results using power values with attribute modifiers, then best-of-3 overall.
	if attribute_config == null or not attribute_config.has_method("get_attribute"):
		push_warning("BattleManager: attribute_config not set; battle will tie.")
		if _result_label:
			_result_label.text = "Tie (0)"
		if DEBUG_LOGS: print("[BattleManager] _resolve_battle: early return (no attribute_config), set result to Tie (0)")
		return

	var player_wins := 0
	var opponent_wins := 0
	var ties := 0
	_round_results.clear()
	# Pre-fill round results with ties so indices always align with player slot indices (0=PL,1=PM,2=PR).
	for _i in range(_player_slot_nodes.size()):
		_round_results.append("tie")

	# Pairing order from right to left: PR vs OR, PM vs OM, PL vs OL.
	var player_indices := [2, 1, 0]
	var opponent_indices := [0, 1, 2]
	var pair_count: int = min(
		min(player_indices.size(), opponent_indices.size()),
		min(_player_slot_nodes.size(), _opponent_slot_nodes.size())
	)

	for pair_idx in range(pair_count):
		var p_index: int = player_indices[pair_idx]
		var o_index: int = opponent_indices[pair_idx]
		if p_index >= _player_slot_nodes.size() or o_index >= _opponent_slot_nodes.size():
			continue

		var pslot = _player_slot_nodes[p_index]
		var oslot = _opponent_slot_nodes[o_index]

		var pcard = pslot.snapped_card if pslot else null
		var ocard = oslot.snapped_card if oslot else null

		# Get power values (frame_index + 1)
		var p_power: float = 0.0
		var o_power: float = 0.0
		
		if pcard:
			var p_frame_idx: int = int(pcard.get("frame_index"))
			p_power = float(p_frame_idx + 1)
		
		if ocard:
			var o_frame_idx: int = int(ocard.get("frame_index"))
			o_power = float(o_frame_idx + 1)

		# Get attributes
		var pa: String = _card_manager.get_card_attribute(pcard, attribute_config) if _card_manager else "unknown"
		var oa: String = _card_manager.get_card_attribute(ocard, attribute_config) if _card_manager else "unknown"

		# Calculate attribute modifier for player card
		var p_modifier: float = 0.0
		if pa != "unknown" and oa != "unknown":
			if pa == oa:
				# Neutral (same attribute)
				p_modifier = 0.0
			else:
				# Check if player card beats opponent card (advantageous)
				var pa_beats = attribute_config.beats.get(pa, null)
				if pa_beats == oa:
					p_modifier = 0.5
				else:
					# Check if opponent card beats player card (disadvantageous)
					var oa_beats = attribute_config.beats.get(oa, null)
					if oa_beats == pa:
						p_modifier = -0.5
					else:
						p_modifier = 0.0

		# Calculate attribute modifier for opponent card
		var o_modifier: float = 0.0
		if pa != "unknown" and oa != "unknown":
			if pa == oa:
				# Neutral (same attribute)
				o_modifier = 0.0
			else:
				# Check if opponent card beats player card (advantageous)
				var oa_beats = attribute_config.beats.get(oa, null)
				if oa_beats == pa:
					o_modifier = 0.5
				else:
					# Check if player card beats opponent card (disadvantageous)
					var pa_beats = attribute_config.beats.get(pa, null)
					if pa_beats == oa:
						o_modifier = -0.5
					else:
						o_modifier = 0.0

		# Calculate final power values
		var p_final_power: float = p_power + p_modifier
		var o_final_power: float = o_power + o_modifier

		# Determine winner based on final power values (per round)
		if p_final_power > o_final_power:
			player_wins += 1
			_round_results[p_index] = "win"
		elif o_final_power > p_final_power:
			opponent_wins += 1
			_round_results[p_index] = "lose"
		else:
			ties += 1
			_round_results[p_index] = "tie"

	# Overall result by point system: +1 win, -1 loss, 0 tie. Most points wins; equal = tie.
	# On tie overall, defender wins for card-loss purposes (handled in process_battle_resolution).
	var player_points := 0
	for r in _round_results:
		if r == "win":
			player_points += 1
		elif r == "lose":
			player_points -= 1
	# else tie: no change

	var result_text := ""
	if player_points > 0:
		result_text = "You Win (+%d)" % player_points
	elif player_points < 0:
		result_text = "You Lose (%d)" % player_points
	else:
		result_text = "Tie (0)"

	if _result_label:
		_result_label.text = result_text
		if DEBUG_LOGS: print("[BattleManager] _resolve_battle: result_text set to \"%s\"" % result_text)
	else:
		if DEBUG_LOGS: print("[BattleManager] _resolve_battle: _result_label is null, result_text would be \"%s\"" % result_text)


func _show_result() -> void:
	if DEBUG_LOGS: print("[BattleManager] _show_result() called. _result_label valid=%s _continue_label valid=%s" % [_result_label != null, _continue_label != null])
	if _result_label:
		if _result_label.text.is_empty():
			_result_label.text = "Tie (0)"
			if DEBUG_LOGS: print("[BattleManager] _show_result: result text was empty, set fallback \"Tie (0)\"")
		_result_label.add_theme_font_size_override("font_size", 48)
		# Color the result text to match the winner's race
		var winner_color := _determine_winner_color()
		_result_label.add_theme_color_override("font_color", winner_color)
		_result_label.visible = true
		if _result_label.text:
			if DEBUG_LOGS: print("[BattleManager] _show_result: ResultLabel.visible=true, text=\"%s\"" % _result_label.text)
		else:
			if DEBUG_LOGS: print("[BattleManager] _show_result: ResultLabel.visible=true but text is empty")
	# Hide continue label — auto-return handles the transition
	if _continue_label:
		_continue_label.visible = false
	# Ensure visibility is applied after any other updates this frame
	call_deferred("_apply_result_visibility")


func _determine_winner_color() -> Color:
	## Determine the winner's race color based on battle result.
	var result := _get_battle_result()
	var my_id := multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else -1
	var winner_id: int = -1
	if result == "win":
		winner_id = my_id
	elif result == "lose":
		# Opponent won
		if my_id == App.pending_territory_battle_attacker_id:
			winner_id = App.pending_territory_battle_defender_id
		else:
			winner_id = App.pending_territory_battle_attacker_id
	else:
		# Tie → defender wins for territory purposes
		winner_id = App.pending_territory_battle_defender_id
	var winner_race: String = _card_scene_ui.get_player_race(winner_id) if _card_scene_ui else ""
	return _card_scene_ui.get_race_color(winner_race) if _card_scene_ui else Color.WHITE


func _apply_result_visibility() -> void:
	if _result_label and not _result_label.visible:
		_result_label.visible = true
		if DEBUG_LOGS: print("[BattleManager] _apply_result_visibility: re-applied ResultLabel.visible=true")


func _get_battle_result() -> String:
	## Returns "win", "lose", or "tie" based on battle resolution
	if _result_label and _result_label.text:
		var text := _result_label.text.to_lower()
		if "win" in text:
			return "win"
		elif "lose" in text:
			return "lose"
	return "tie"


func _apply_battle_resolution_state() -> void:
	## Run immediately after cards flip and result is shown. Updates BSM, TCS, and collection.
	## Called once per client when state becomes RESOLVED; Leave only handles transition/cleanup.
	if state != State.RESOLVED:
		return
	if DEBUG_LOGS: print("[BattleManager] Battle RESOLVED — applying outcome and territory state (right after flip).")
	var result := _get_battle_result()
	var player_wins := result == "win"
	var tid_str: String = BattleStateManager.current_territory_id if BattleStateManager else ""

	if BattleStateManager:
		BattleStateManager.record_battle_result(result, player_wins, tid_str)
		BattleStateManager.record_round_results(_round_results, tid_str)

	# Territory battle: current_territory_id is set when we entered; pending_territory_battle_ids is already popped, so don't require it.
	var is_territory_battle: bool = not tid_str.is_empty() and not tid_str.begins_with("battle_")
	if BattleStateManager and is_territory_battle:
		var tcs: Node = get_node_or_null("/root/TerritoryClaimState")
		var my_id := multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
		var is_defender := false
		# Prefer explicit participants from App (authoritative for this battle instance).
		if App and App.pending_territory_battle_defender_id != -1:
			is_defender = int(App.pending_territory_battle_defender_id) == int(my_id)
		else:
			if tcs and tcs.has_method("get_owner_id"):
				var owner_id = tcs.call("get_owner_id", int(tid_str))
				is_defender = (int(owner_id) == int(my_id))

		if DEBUG_LOGS: print("[BattleManager] _apply_resolution: my_id=%d pending_defender_id=%d is_defender=%s result=%s _round_results=%s" % [
			my_id, App.pending_territory_battle_defender_id, str(is_defender), result, str(_round_results)])

		var lost_cards := BattleStateManager.process_battle_resolution(result, player_wins, is_defender, tid_str)
		if not lost_cards.is_empty():
			App.remove_placed_cards_from_collection_for_slots(lost_cards)

		var attacker_id: int = App.pending_territory_battle_attacker_id
		# Defender keeps territory on tie.
		var attacker_won: bool = false
		if result == "win":
			attacker_won = not is_defender
		elif result == "lose":
			attacker_won = is_defender
		if DEBUG_LOGS: print("[BattleManager] Resolution context tid=%s my_id=%d is_defender=%s result=%s attacker_won=%s" % [
			tid_str, my_id, str(is_defender), result, str(attacker_won)
		])

		if attacker_won:
			var attacker_slots: Dictionary = BattleStateManager.get_attacking_slots(tid_str)
			# Multiplayer fallback: if local attacking slots are empty on this peer,
			# use synced battle cards so conquest does not claim with empty defenders.
			if attacker_slots.is_empty() and _is_multiplayer and BattleSync:
				var synced_att: Dictionary = BattleSync.battle_placed_cards.get(attacker_id, {})
				if not synced_att.is_empty():
					attacker_slots = synced_att.duplicate(true)
			# Keep only surviving attacker cards for conquest (attacker loses tie lanes too).
			attacker_slots = _filter_surviving_attacker_slots(attacker_slots, is_defender)
			if BattleStateManager:
				BattleStateManager.set_attacking_slots(tid_str, attacker_slots)
			var cards: Array = [null, null, null]
			for idx in attacker_slots:
				var c: Dictionary = attacker_slots[idx]
				if int(idx) < 3 and c.get("path", "") != "":
					cards[int(idx)] = {"path": c.get("path", ""), "frame": int(c.get("frame"))}
			if cards[0] == null and cards[1] == null and cards[2] == null:
				push_warning("[BattleManager] attacker_won but attacker card payload is empty for territory %s; skipping conquest apply to avoid empty-claim desync." % tid_str)
				return
			if App.is_multiplayer and App.get_tree().get_multiplayer().has_multiplayer_peer():
				TerritorySync.request_conquest_territory(int(tid_str), attacker_id, cards)
			else:
				TerritoryClaimManager.apply_conquest_claim(int(tid_str), attacker_id, cards)
			var claims_dict: Variant = tcs.get("claims") if tcs else null
			if not (claims_dict is Dictionary):
				claims_dict = {}
			var owners_list: Array[String] = []
			if claims_dict is Dictionary:
				var keys: Array = (claims_dict as Dictionary).keys()
				keys.sort()
				for k in keys:
					var claim_data: Dictionary = (claims_dict as Dictionary)[k]
					var oid: Variant = claim_data.get("owner_player_id", null)
					owners_list.append("T%s->owner %s" % [k, oid])
			if DEBUG_LOGS: print("[BattleManager] Attacker wins: territory %s claimed by attacker (owner) %s. Current owners of all territories: %s" % [tid_str, attacker_id, ", ".join(owners_list)])
		else:
			if tcs and tcs.has_method("get_owner_id"):
				var owner_id = tcs.call("get_owner_id", int(tid_str))
				if owner_id != null:
					var remaining: Dictionary = BattleStateManager.get_defending_slots(tid_str)
					# Fallback: if defending_slots is unexpectedly empty after defender win, restore from TerritoryClaimState.
					if remaining.is_empty() and tcs and tcs.has_method("get_cards"):
						var tcs_cards: Array = tcs.call("get_cards", int(tid_str))
						for slot_idx in range(mini(3, tcs_cards.size())):
							if tcs_cards[slot_idx] != null and tcs_cards[slot_idx] is Dictionary:
								remaining[slot_idx] = tcs_cards[slot_idx]
						if not remaining.is_empty():
							push_warning("[BattleManager] Defender won but defending_slots empty; restored from TCS for territory %s" % tid_str)
					if DEBUG_LOGS: print("[BattleManager] Defender-wins path: remaining defending_slots=%s for territory %s" % [str(remaining), tid_str])
					var cards: Array = [null, null, null]
					for idx in remaining:
						var c: Dictionary = remaining[idx]
						if int(idx) < 3 and c.get("path", "") != "":
							cards[int(idx)] = {"path": c.get("path", ""), "frame": int(c.get("frame"))}
					# Defender keeps the territory but may have lost cards. Sync the updated defending cards to all peers.
					if App.is_multiplayer and App.get_tree().get_multiplayer().has_multiplayer_peer():
						TerritorySync.request_conquest_territory(int(tid_str), int(owner_id), cards)
					else:
						TerritoryClaimManager.apply_conquest_claim(int(tid_str), int(owner_id), cards)


func _filter_surviving_attacker_slots(attacker_slots: Dictionary, local_is_defender: bool) -> Dictionary:
	var survivors: Dictionary = attacker_slots.duplicate(true)
	for p_idx in range(mini(_round_results.size(), 3)):
		var rr := String(_round_results[p_idx])
		var attacker_lost_lane := false
		var attacker_slot_idx := p_idx
		if local_is_defender:
			# Opponent (attacker) occupies mirrored slot indices in local view.
			attacker_slot_idx = 2 - p_idx
			attacker_lost_lane = (rr == "win" or rr == "tie")
		else:
			# Local side is attacker.
			attacker_lost_lane = (rr == "lose" or rr == "tie")
		if attacker_lost_lane:
			survivors.erase(attacker_slot_idx)
			survivors.erase(str(attacker_slot_idx))
	return survivors


# ---------- SPECTATOR BATTLE RESOLUTION ----------

func _spectator_on_battle_start() -> void:
	## Called when both battlers are ready and we are spectating.
	## Compute battle result and display winner.
	state = State.FLIPPING
	var result: Dictionary = {}
	if _is_multiplayer:
		# Short delay to allow synced data to settle
		await get_tree().create_tween().tween_interval(0.5).finished
		result = _spectator_resolve_from_sync()
	else:
		result = _spectator_resolve_single_player_from_state()
	_spectator_winner_role = result.get("winner", "defender")
	_spectator_winner_id = int(result.get("winner_id", -1))

	var winner_name: String = _card_scene_ui.get_player_name(_spectator_winner_id) if _card_scene_ui else "Player"
	var tid_str: String = BattleStateManager.current_territory_id if BattleStateManager else ""

	var text := "%s Won" % winner_name
	if _spectator_winner_role == "defender":
		text += "\n%s keeps claim of this territory." % winner_name
	else:
		text += "\n%s now has claim of this territory." % winner_name

	if _result_label:
		_result_label.text = text
		_result_label.add_theme_font_size_override("font_size", 48)
		var winner_race: String = _card_scene_ui.get_player_race(_spectator_winner_id) if _card_scene_ui else ""
		_result_label.add_theme_color_override("font_color", _card_scene_ui.get_race_color(winner_race) if _card_scene_ui else Color.WHITE)
		_result_label.visible = true

	# Bot-vs-bot in multiplayer: the host must apply territory state since no
	# participant runs _apply_battle_resolution_state.
	if _is_multiplayer and multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		var ids_rr: Dictionary = _resolve_spectator_territory_participant_ids()
		var att_id: int = int(ids_rr.get("attacker_id", -1))
		var def_id: int = int(ids_rr.get("defender_id", -1))
		if PlayerDataSync.is_bot_id(att_id) and PlayerDataSync.is_bot_id(def_id):
			_apply_bot_vs_bot_territory_state(tid_str, _spectator_winner_role, att_id, def_id, result)

	state = State.RESOLVED
	_start_auto_return()
	if DEBUG_LOGS: print("[BattleManager] Spectator resolved: %s (id=%d) won territory %s" % [winner_name, _spectator_winner_id, tid_str])


func _start_singleplayer_spectator_battle_timer() -> void:
	## In single-player bot-vs-bot battles, run an automatic 5-second battle window.
	if not _is_spectator or _is_multiplayer:
		return
	if DEBUG_LOGS: print("[BattleManager] Single-player spectator battle timer started (5.0s).")
	await get_tree().create_tween().tween_interval(5.0).finished
	if state == State.RESOLVED:
		return
	_spectator_on_battle_start()


func _apply_bot_vs_bot_territory_state(tid_str: String, winner_role: String, attacker_id: int, defender_id: int, _result: Dictionary) -> void:
	## Host-only: apply territory ownership and card changes for a bot-vs-bot battle.
	if tid_str.is_empty() or tid_str.begins_with("battle_"):
		return
	if DEBUG_LOGS: print("[BattleManager] Applying bot-vs-bot territory state for territory %s (winner=%s)" % [tid_str, winner_role])

	var attacker_won := (winner_role == "attacker")
	var tcs: Node = get_node_or_null("/root/TerritoryClaimState")

	if attacker_won:
		var attacker_slots: Dictionary = BattleStateManager.get_attacking_slots(tid_str) if BattleStateManager else {}
		var cards: Array = [null, null, null]
		for idx in attacker_slots:
			var c: Dictionary = attacker_slots[idx]
			if int(idx) < 3 and String(c.get("path", "")) != "":
				cards[int(idx)] = {"path": c.get("path", ""), "frame": int(c.get("frame", 0))}
		if App.is_multiplayer and App.get_tree().get_multiplayer().has_multiplayer_peer():
			TerritorySync.request_conquest_territory(int(tid_str), attacker_id, cards)
		elif tcs and tcs.has_method("set_claim"):
			TerritoryClaimManager.apply_conquest_claim(int(tid_str), attacker_id, cards)
		if DEBUG_LOGS: print("[BattleManager] Bot attacker %d conquered territory %s" % [attacker_id, tid_str])
	else:
		if tcs and tcs.has_method("get_owner_id"):
			var remaining: Dictionary = BattleStateManager.get_defending_slots(tid_str) if BattleStateManager else {}
			var cards: Array = [null, null, null]
			for idx in remaining:
				var c: Dictionary = remaining[idx]
				if int(idx) < 3 and String(c.get("path", "")) != "":
					cards[int(idx)] = {"path": c.get("path", ""), "frame": int(c.get("frame", 0))}
			if App.is_multiplayer and App.get_tree().get_multiplayer().has_multiplayer_peer():
				TerritorySync.request_conquest_territory(int(tid_str), defender_id, cards)
			else:
				TerritoryClaimManager.apply_conquest_claim(int(tid_str), defender_id, cards)
			if DEBUG_LOGS: print("[BattleManager] Bot defender %d held territory %s" % [defender_id, tid_str])

	if BattleStateManager:
		BattleStateManager.clear_attacking_slots(tid_str)


func _spectator_resolve_from_sync() -> Dictionary:
	## Resolve the battle from BattleSync.battle_placed_cards without needing card nodes.
	## Uses the same pairing and attribute logic as _resolve_battle.
	var ids: Dictionary = _resolve_spectator_territory_participant_ids()
	var attacker_id: int = int(ids.get("attacker_id", -1))
	var defender_id: int = int(ids.get("defender_id", -1))

	var attacker_cards: Dictionary = _spectator_get_placed_for_peer(attacker_id)
	var defender_cards: Dictionary = _spectator_get_placed_for_peer(defender_id)

	var defender_wins := 0
	var attacker_wins := 0

	# Same pairing as _resolve_battle: PR vs OR, PM vs OM, PL vs OL
	# From defender perspective: defender[2] vs attacker[0], defender[1] vs attacker[1], defender[0] vs attacker[2]
	var defender_indices := [2, 1, 0]
	var attacker_indices := [0, 1, 2]

	for pair_idx in range(3):
		var d_idx: int = defender_indices[pair_idx]
		var a_idx: int = attacker_indices[pair_idx]

		var d_data: Dictionary = defender_cards.get(d_idx, {})
		var a_data: Dictionary = attacker_cards.get(a_idx, {})

		var d_power: float = 0.0
		var a_power: float = 0.0

		if not d_data.is_empty():
			d_power = float(int(d_data.get("frame", 0)) + 1)
		if not a_data.is_empty():
			a_power = float(int(a_data.get("frame", 0)) + 1)

		# Get attributes from sprite frames paths
		var da: String = _card_manager.get_attribute_from_path(d_data.get("path", ""), attribute_config) if _card_manager else "unknown"
		var aa: String = _card_manager.get_attribute_from_path(a_data.get("path", ""), attribute_config) if _card_manager else "unknown"

		var d_modifier: float = 0.0
		var a_modifier: float = 0.0

		if da != "unknown" and aa != "unknown" and da != aa:
			if attribute_config and attribute_config.has_method("get_attribute"):
				var da_beats = attribute_config.beats.get(da, null)
				if da_beats == aa:
					d_modifier = 0.5
					a_modifier = -0.5
				else:
					var aa_beats = attribute_config.beats.get(aa, null)
					if aa_beats == da:
						a_modifier = 0.5
						d_modifier = -0.5

		var d_final := d_power + d_modifier
		var a_final := a_power + a_modifier

		if d_final > a_final:
			defender_wins += 1
		elif a_final > d_final:
			attacker_wins += 1

	# Overall: defender wins ties (same as _resolve_battle)
	var defender_points := defender_wins - attacker_wins

	if defender_points >= 0:
		return {"winner": "defender", "winner_id": defender_id}
	else:
		return {"winner": "attacker", "winner_id": attacker_id}


func _spectator_resolve_single_player_from_state() -> Dictionary:
	## Resolve single-player bot-vs-bot battle from BattleStateManager attacking/defending slots.
	var tid_str: String = BattleStateManager.current_territory_id if BattleStateManager else ""
	var attacker_id := App.pending_territory_battle_attacker_id
	var defender_id := App.pending_territory_battle_defender_id
	var attacker_cards: Dictionary = BattleStateManager.get_attacking_slots(tid_str) if BattleStateManager else {}
	var defender_cards: Dictionary = BattleStateManager.get_defending_slots(tid_str) if BattleStateManager else {}

	var defender_wins := 0
	var attacker_wins := 0
	var defender_indices := [2, 1, 0]
	var attacker_indices := [0, 1, 2]

	for pair_idx in range(3):
		var d_idx: int = defender_indices[pair_idx]
		var a_idx: int = attacker_indices[pair_idx]
		var d_data: Dictionary = defender_cards.get(d_idx, {})
		var a_data: Dictionary = attacker_cards.get(a_idx, {})

		var d_power: float = float(int(d_data.get("frame", 0)) + 1) if not d_data.is_empty() else 0.0
		var a_power: float = float(int(a_data.get("frame", 0)) + 1) if not a_data.is_empty() else 0.0

		var da: String = _card_manager.get_attribute_from_path(d_data.get("path", ""), attribute_config) if _card_manager else "unknown"
		var aa: String = _card_manager.get_attribute_from_path(a_data.get("path", ""), attribute_config) if _card_manager else "unknown"
		var d_modifier: float = 0.0
		var a_modifier: float = 0.0
		if da != "unknown" and aa != "unknown" and da != aa:
			var da_beats = attribute_config.beats.get(da, null)
			if da_beats == aa:
				d_modifier = 0.5
				a_modifier = -0.5
			else:
				var aa_beats = attribute_config.beats.get(aa, null)
				if aa_beats == da:
					a_modifier = 0.5
					d_modifier = -0.5

		var d_final := d_power + d_modifier
		var a_final := a_power + a_modifier
		if d_final > a_final:
			defender_wins += 1
		elif a_final > d_final:
			attacker_wins += 1

	var defender_points := defender_wins - attacker_wins
	if defender_points >= 0:
		return {"winner": "defender", "winner_id": defender_id}
	return {"winner": "attacker", "winner_id": attacker_id}


func _clear_player_slots() -> void:
	## Clear all player slots: remove cards, reset slot state
	for slot in _player_slot_nodes:
		if not slot:
			continue
		if slot.has_card and slot.snapped_card:
			var card = slot.snapped_card
			# Remove from CardManager's snapped_cards tracking
			if _card_manager:
				if _card_manager.snapped_cards.has(card):
					_card_manager.snapped_cards.erase(card)
			# Reset slot state
			if slot.has_method("unsnap_card"):
				slot.unsnap_card()
			# Remove card node
			if card and is_instance_valid(card):
				card.queue_free()


func _start_auto_return() -> void:
	_auto_return_active = true
	_auto_return_timer = AUTO_RETURN_DELAY
	if DEBUG_LOGS: print("[BattleManager] Auto-return started. Returning to map in %.1f seconds." % AUTO_RETURN_DELAY)


func _auto_leave_battle() -> void:
	## Automatically called after the auto-return timer expires. Mirrors _on_leave_pressed logic for RESOLVED state.
	if DEBUG_LOGS: print("[BattleManager] Auto-return timer expired. Leaving battle.")
	if _is_spectator:
		App.is_battle_spectator = false
		_spectator_dispose_all_tracked_backs()
		BattleSync.clear_battle_state()
		App.switch_to_main_music()
		App.on_battle_completed()
		return

	if _is_multiplayer:
		BattleSync.notify_battle_left()
		if state == State.RESOLVED and not _reported_battle_finished:
			BattleSync.notify_battle_finished()
			_reported_battle_finished = true

	BattleSync.clear_battle_state()
	App.switch_to_main_music()
	App.on_battle_completed()


func _on_leave_pressed() -> void:
	# Cancel auto-return if player manually leaves
	_auto_return_active = false
	var state_name: String = ["SETUP", "WAITING_FOR_PLAYER", "WAITING_FOR_ALL_READY", "FLIPPING", "RESOLVED"][clampi(state, 0, 4)]
	if DEBUG_LOGS: print("[BattleManager] Leave pressed. Current battle state: %s. is_spectator=%s" % [state_name, str(_is_spectator)])

	if _is_spectator:
		App.is_battle_spectator = false
		_spectator_dispose_all_tracked_backs()
		BattleSync.clear_battle_state()
		App.switch_to_main_music()
		if state == State.RESOLVED:
			App.on_battle_completed()
		else:
			App.go(MAIN_MENU_PATH)
		return

	if _is_multiplayer:
		BattleSync.notify_battle_left()
		# Added (minimal): only report finished when leaving a resolved battle (paired tracking)
		if state == State.RESOLVED and not _reported_battle_finished:
			BattleSync.notify_battle_finished()
			_reported_battle_finished = true

	# State was already applied at flip time (_apply_battle_resolution_state). Only cleanup and transition.
	if state == State.RESOLVED:
		BattleSync.clear_battle_state()
	else:
		# Leaving unresolved battle: persist cards for restoration
		_persist_local_placed_cards()
		# Don't clear battle state - keep it for when player returns

	App.switch_to_main_music()
	if state == State.RESOLVED:
		# on_battle_completed pops next battle and request_start_territory_battle(next_id) if queue non-empty.
		# The RPC start_territory_battle pulls the other player into the new battle from wherever they are.
		App.on_battle_completed()
	else:
		# Unresolved - return to GameIntro directly
		App.go(MAIN_MENU_PATH)


func _on_debug_add_card_pressed() -> void:
	if not _debug_add_card_button or not show_debug_add_card_button:
		return
	if _card_manager and _card_manager.has_method("request_debug_add_card"):
		_card_manager.request_debug_add_card(CARD_SCENE)


func _persist_local_placed_cards() -> void:
	## Refresh BattleStateManager's local_slots from the current player slot cards.
	if not BattleStateManager:
		return
	BattleStateManager.clear_local_slots()
	for idx in range(_player_slot_nodes.size()):
		var slot = _player_slot_nodes[idx]
		if slot and slot.snapped_card:
			var card = slot.snapped_card
			var frames: SpriteFrames = card.get("card_sprite_frames")
			var fidx: int = int(card.get("frame_index"))
			if frames and frames.resource_path:
				BattleStateManager.set_local_slot(idx, frames.resource_path, fidx)

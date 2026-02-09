extends Node

## BattleManager
## Orchestrates: opponent backs on entry, start-battle gating, flip animation,
## attribute-based resolution, and returning to menu on SPACE.
## In multiplayer: syncs card placement, waits for all players to press Start, flips when all ready.

const CARD_SCENE: PackedScene = preload("res://scenes/card.tscn")
const MAIN_MENU_PATH := "res://scenes/ui/GameIntro.tscn"

enum State { SETUP, WAITING_FOR_PLAYER, WAITING_FOR_ALL_READY, FLIPPING, RESOLVED }
var state: State = State.SETUP

## Editor-provided attribute mapping + rules.
@export var attribute_config: Resource

## Node names (kept simple; pairing is fixed and intended to remain stable).
@export var player_slots: Array[StringName] = [&"CardSlotPL", &"CardSlotPM", &"CardSlotPR"]
@export var opponent_slots: Array[StringName] = [&"CardSlotOR", &"CardSlotOM", &"CardSlotOL"]

## Deck node that defines the opponent pool and the back image.
@export var deck_o_name: StringName = &"DeckO"
## Player deck (hidden when restoring cards).
@export var deck_p_name: StringName = &"DeckP"

## UI node paths (created in scene).
@export var start_button_path: NodePath = NodePath("BattleUI/UI/StartBattleButton")
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

var _player_slot_nodes: Array = []
var _opponent_slot_nodes: Array = []
var _deck_o: Node = null
var _deck_p: Node = null

var _start_button: Button
var _result_label: Label
var _continue_label: Label
var _leave_button: Button
var _debug_add_card_button: Button

var _opponent_cards_by_slot: Dictionary = {} # slot -> card

var _is_multiplayer: bool = false

# --- Added (minimal): prevent double-reporting finish in multiplayer (SPACE + Leave, etc.)
var _reported_battle_finished: bool = false


func _ready() -> void:
	_is_multiplayer = multiplayer.has_multiplayer_peer() and multiplayer.get_peers().size() > 0
	_cache_nodes()
	if _is_multiplayer:
		# Only clear battle state if starting fresh (no persisted cards)
		var has_local_slots := false
		if BattleStateManager:
			has_local_slots = not BattleStateManager.get_local_slots().is_empty()
		if not has_local_slots:
			Net.clear_battle_state()
		if Net.battle_cards_updated.is_connected(_on_battle_cards_updated):
			Net.battle_cards_updated.disconnect(_on_battle_cards_updated)
		Net.battle_cards_updated.connect(_on_battle_cards_updated)
		if Net.battle_start_requested.is_connected(_on_battle_start_requested):
			Net.battle_start_requested.disconnect(_on_battle_start_requested)
		Net.battle_start_requested.connect(_on_battle_start_requested)
	_setup_ui()

	# Wait a couple frames so CardManager has time to initialize
	await get_tree().process_frame
	await get_tree().process_frame

	# Restore cards after CardManager is ready
	_restore_and_sync_placed_cards()

	# Wait another frame for cards to be properly registered
	await get_tree().process_frame

	_place_opponent_backs()
	_connect_player_slot_signals()
	_update_start_button_visibility()
	state = State.WAITING_FOR_PLAYER

	# Update deck visibility and respace hand cards after everything is set up
	call_deferred("_update_deck_visibility")
	call_deferred("_respace_hand_cards")


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

	_deck_o = root.get_node_or_null(NodePath(String(deck_o_name))) if root else null
	_deck_p = root.get_node_or_null(NodePath(String(deck_p_name))) if root else null

	_start_button = (root.get_node_or_null(start_button_path) if root else null) as Button
	_result_label = (root.get_node_or_null(result_label_path) if root else null) as Label
	_continue_label = (root.get_node_or_null(continue_label_path) if root else null) as Label
	_leave_button = (root.get_node_or_null(leave_button_path) if root else null) as Button
	_debug_add_card_button = (root.get_node_or_null(debug_add_card_button_path) if root else null) as Button


func _restore_and_sync_placed_cards() -> void:
	## Restore from BattleStateManager. In multiplayer, restore locally and sync to server.
	var placed: Dictionary = {}
	if BattleStateManager:
		placed = BattleStateManager.get_local_slots()
	if placed.is_empty():
		return
	_restore_cards_to_slots(placed)
	if _is_multiplayer:
		for slot_idx in placed:
			var data: Dictionary = placed[slot_idx]
			var path: String = data.get("path", "")
			var frame: int = int(data.get("frame", 0))
			if not path.is_empty():
				Net.request_place_battle_card(slot_idx, path, frame)


func _restore_cards_to_slots(placed: Dictionary) -> void:
	## Spawn cards from a placed-slots dictionary and place them in player slots.
	var root := get_parent()
	if not root:
		root = get_tree().current_scene
	var hand_container := root.get_node_or_null("HandCardsLayer/HandCardsContainer")
	if not hand_container:
		hand_container = root
	var card_manager := root.get_node_or_null("CardManager")
	for slot_idx in placed:
		if slot_idx < 0 or slot_idx >= _player_slot_nodes.size():
			continue
		var slot = _player_slot_nodes[slot_idx]
		if not slot or not slot.has_method("force_snap_card"):
			continue
		var data: Dictionary = placed[slot_idx]
		var path: String = data.get("path", "")
		var frame: int = int(data.get("frame", 0))
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
		if card_manager:
			if card_manager.has_method("register_card"):
				card_manager.register_card(card)
			# Ensure card is in card_spawn_positions for tracking
			if not card_manager.card_spawn_positions.has(card):
				card_manager.card_spawn_positions[card] = slot.global_position

		# Now snap to slot
		slot.force_snap_card(card)

		if card_manager:
			card_manager.snapped_cards[card] = slot
			# Set spawn position to slot position (in case card is unsnapped later)
			if card_manager.has_method("set_card_spawn_position"):
				card_manager.set_card_spawn_position(card, slot.global_position)

		# Ensure the card's Area2D remains input_pickable even when snapped
		var area := card.get_node_or_null("Card_Collision") as Area2D
		if area:
			area.input_pickable = true

	# Update deck visibility and respace hand cards after restoration
	# Wait a frame to ensure cards are properly registered
	await get_tree().process_frame
	call_deferred("_update_deck_visibility")
	call_deferred("_respace_hand_cards")


func _on_battle_cards_updated() -> void:
	## Refresh opponent slots from remote player(s). Also refresh in RESOLVED so loser's cards clear when synced.
	if state in [State.WAITING_FOR_PLAYER, State.WAITING_FOR_ALL_READY, State.RESOLVED]:
		_update_opponent_cards_from_net()


func _on_battle_start_requested() -> void:
	## All players pressed Start; begin flip and resolve.
	if state != State.WAITING_FOR_PLAYER and state != State.WAITING_FOR_ALL_READY:
		return
	if _start_button:
		_start_button.visible = false
	state = State.FLIPPING
	await _flip_opponent_cards_from_pool()
	_resolve_battle()
	_show_result()
	_report_battle_resolved()
	state = State.RESOLVED


func _report_battle_resolved() -> void:
	## Report result to BattleStateManager and sync loser's card clearance to Net (multiplayer).
	var result := _get_battle_result()
	var local_won := result == "win"
	if BattleStateManager:
		BattleStateManager.record_battle_result(result, local_won)
	if _is_multiplayer and result == "lose":
		Net.request_clear_my_battle_cards()


func _update_opponent_cards_from_net() -> void:
	## Place/update face-down cards in opponent slots from Net.battle_placed_cards.
	var my_id := multiplayer.get_unique_id()
	var other_peer_id: int = -1
	for pid in Net.battle_placed_cards:
		if int(pid) != my_id:
			other_peer_id = int(pid)
			break
	# If no other peer (e.g. loser was cleared), other_cards is empty - we'll clear opponent slots
	var other_cards: Dictionary = Net.battle_placed_cards.get(other_peer_id, {}) if other_peer_id >= 0 else {}
	if not _deck_o:
		return
	var back_frames: SpriteFrames = _deck_o.get("deck_sprite_frames")
	var back_frame_index: int = int(_deck_o.get("frame_index"))
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


func _setup_ui() -> void:
	if _start_button:
		_start_button.visible = false
		_start_button.text = "Ready"
		if not _start_button.pressed.is_connected(_on_start_battle_pressed):
			_start_button.pressed.connect(_on_start_battle_pressed)

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
			Net.request_place_battle_card(slot_idx, frames.resource_path, fidx)
		else:
			_persist_local_placed_cards()

		# Respace hand cards (which will also update deck visibility)
		call_deferred("_respace_hand_cards")

	_update_start_button_visibility()


func _on_card_unsnapped_from_slot(card: Node, slot_idx: int) -> void:
	if state != State.WAITING_FOR_PLAYER and state != State.WAITING_FOR_ALL_READY:
		return

	# Remove from persistence
	if BattleStateManager:
		BattleStateManager.set_local_slot(slot_idx, "", 0)

	# Sync in multiplayer
	if _is_multiplayer:
		Net.request_remove_battle_card(slot_idx)
	else:
		_persist_local_placed_cards()

		# Respace hand cards (which will also update deck visibility)
		call_deferred("_respace_hand_cards")

	# Reset deck spawned flag so it can be used again
	if _deck_p and _deck_p.use_player_collection:
		if _deck_p.has_method("reset_spawned_flag"):
			_deck_p.reset_spawned_flag()

	_update_start_button_visibility()


func _player_ready() -> bool:
	for slot in _player_slot_nodes:
		if not slot:
			return false
		if not slot.has_card:
			return false
		if slot.snapped_card == null:
			return false
	return true


func _update_start_button_visibility() -> void:
	if not _start_button:
		return
	_start_button.visible = state == State.WAITING_FOR_PLAYER


func _place_opponent_backs() -> void:
	# Create a non-draggable card in each opponent slot, showing the deck back.
	# In multiplayer, opponent cards are placed by _update_opponent_cards_from_net when sync arrives.
	if _is_multiplayer:
		_update_opponent_cards_from_net()
		return
	if not _deck_o:
		push_warning("BattleManager: DeckO not found; cannot place opponent backs.")
		return

	var back_frames: SpriteFrames = _deck_o.get("deck_sprite_frames")
	var back_frame_index: int = int(_deck_o.get("frame_index"))

	for slot in _opponent_slot_nodes:
		if not slot:
			continue

		# If there's already an opponent card, just update it.
		var existing = _opponent_cards_by_slot.get(slot, null)
		if existing and is_instance_valid(existing):
			existing.card_sprite_frames = back_frames
			existing.frame_index = back_frame_index
			continue

		var card := CARD_SCENE.instantiate()
		get_tree().current_scene.add_child(card)

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


func _on_start_battle_pressed() -> void:
	if state != State.WAITING_FOR_PLAYER:
		return

	if _is_multiplayer:
		Net.request_battle_ready()
		if _start_button:
			_start_button.visible = false
		state = State.WAITING_FOR_ALL_READY
		return

	if _start_button:
		_start_button.visible = false

	state = State.FLIPPING
	await _flip_opponent_cards_from_pool()
	_resolve_battle()
	_show_result()
	_report_battle_resolved()
	state = State.RESOLVED


func _flip_opponent_cards_from_pool() -> void:
	if not _deck_o:
		return

	var chosen: Dictionary = {} # slot -> {frames, frame_index}

	if _is_multiplayer:
		# Reveal actual opponent cards based on Net.battle_placed_cards.
		var my_id := multiplayer.get_unique_id()
		var other_peer_id: int = -1
		for pid in Net.battle_placed_cards:
			if int(pid) != my_id:
				other_peer_id = int(pid)
				break
		if other_peer_id >= 0:
			var other_cards: Dictionary = Net.battle_placed_cards.get(other_peer_id, {})
			for slot_idx in range(_opponent_slot_nodes.size()):
				var slot = _opponent_slot_nodes[slot_idx]
				if not slot or not other_cards.has(slot_idx):
					continue
				var data: Dictionary = other_cards[slot_idx]
				var path: String = data.get("path", "")
				var fidx: int = int(data.get("frame", 0))
				if not path.is_empty():
					var frames: SpriteFrames = load(path) as SpriteFrames
					if frames:
						chosen[slot] = {"frames": frames, "frame_index": fidx}

	# Single-player (and multiplayer fallback if no data) uses the DeckO pool.
	if chosen.is_empty():
		var pool: Array = _deck_o.get("card_sprite_pool")
		var frame_indices: Array = _deck_o.get("card_frame_indices")
		if pool == null or pool.size() == 0:
			# In multiplayer with no other_cards, keep backs and do nothing.
			if _is_multiplayer:
				return
			push_warning("BattleManager: DeckO card_sprite_pool is empty; opponent will remain unknown.")
			return
		for slot in _opponent_slot_nodes:
			var idx := randi() % pool.size()
			var frames := pool[idx] as SpriteFrames
			var fidx := 0
			if frame_indices != null and frame_indices.size() > idx:
				fidx = int(frame_indices[idx])
			chosen[slot] = {"frames": frames, "frame_index": fidx}

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
			var frames: SpriteFrames = def.get("frames", null)
			var fidx: int = int(def.get("frame_index", 0))
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
	# Pairing is fixed by array ordering:
	# PL vs OR, PM vs OM, PR vs OL
	# Determine per-pair results, then best-of-3 overall.
	if attribute_config == null or not attribute_config.has_method("compare"):
		push_warning("BattleManager: attribute_config not set; battle will tie.")
		return

	var player_wins := 0
	var opponent_wins := 0
	var ties := 0

	for i in range(min(_player_slot_nodes.size(), _opponent_slot_nodes.size())):
		var pslot = _player_slot_nodes[i]
		var oslot = _opponent_slot_nodes[i]

		var pcard = pslot.snapped_card if pslot else null
		var ocard = oslot.snapped_card if oslot else null

		var pa := _get_card_attribute(pcard)
		var oa := _get_card_attribute(ocard)

		var outcome: String = String(attribute_config.call("compare", pa, oa))
		match outcome:
			"player":
				player_wins += 1
			"opponent":
				opponent_wins += 1
			_:
				ties += 1

	# Store summary on labels (simple for now).
	var result_text := ""
	if player_wins >= 2:
		result_text = "You Win (%d-%d-%d)" % [player_wins, opponent_wins, ties]
	elif opponent_wins >= 2:
		result_text = "You Lose (%d-%d-%d)" % [player_wins, opponent_wins, ties]
	else:
		result_text = "Tie (%d-%d-%d)" % [player_wins, opponent_wins, ties]

	if _result_label:
		_result_label.text = result_text


func _get_card_attribute(card: Node) -> String:
	if card == null:
		return "unknown"
	if attribute_config == null or not attribute_config.has_method("get_attribute"):
		return "unknown"
	# Card.gd exports card_sprite_frames + frame_index.
	var frames: SpriteFrames = card.get("card_sprite_frames")
	var fidx: int = int(card.get("frame_index"))
	return String(attribute_config.call("get_attribute", frames, fidx))


func _show_result() -> void:
	if _result_label:
		_result_label.visible = true
	if _continue_label:
		_continue_label.visible = true


func _get_battle_result() -> String:
	## Returns "win", "lose", or "tie" based on battle resolution
	if _result_label and _result_label.text:
		var text := _result_label.text.to_lower()
		if "win" in text:
			return "win"
		elif "lose" in text:
			return "lose"
	return "tie"


func _clear_player_slots() -> void:
	## Clear all player slots: remove cards, reset slot state
	var root := get_tree().current_scene
	var card_manager := root.get_node_or_null("CardManager")

	for slot in _player_slot_nodes:
		if not slot:
			continue
		if slot.has_card and slot.snapped_card:
			var card = slot.snapped_card
			# Remove from CardManager's snapped_cards tracking
			if card_manager:
				if card_manager.snapped_cards.has(card):
					card_manager.snapped_cards.erase(card)
			# Reset slot state
			if slot.has_method("unsnap_card"):
				slot.unsnap_card()
			# Remove card node
			if card and is_instance_valid(card):
				card.queue_free()


func _on_leave_pressed() -> void:
	if _is_multiplayer:
		Net.notify_battle_left()
		# Added (minimal): only report finished when leaving a resolved battle (paired tracking)
		if state == State.RESOLVED and not _reported_battle_finished:
			Net.notify_battle_finished()
			_reported_battle_finished = true

	# Handle card persistence based on battle state
	if state == State.RESOLVED:
		# Battle is resolved
		var result := _get_battle_result()
		var player_wins := result == "win"
		# Record outcome in BattleStateManager (from local perspective)
		if BattleStateManager:
			BattleStateManager.record_battle_result(result, player_wins)
		if not player_wins:
			# Loser: clear placed cards from collection and slots
			_clear_player_slots()
			if BattleStateManager:
				var placed := BattleStateManager.get_local_slots()
				App.remove_placed_cards_from_collection_for_slots(placed)
				BattleStateManager.clear_local_slots()
		else:
			# Winner/tie: persist cards in slots
			_persist_local_placed_cards()
		# Clear battle state when leaving resolved battle
		Net.clear_battle_state()
	else:
		# Leaving unresolved battle: persist cards for restoration
		_persist_local_placed_cards()
		# Don't clear battle state - keep it for when player returns

	App.switch_to_main_music()
	if state == State.RESOLVED:
		App.on_battle_completed()
	App.go(MAIN_MENU_PATH)


func _on_debug_add_card_pressed() -> void:
	## Temporary debug: add a random card to hand and spawn it.
	if not _debug_add_card_button or not show_debug_add_card_button:
		return
	App.add_card_from_minigame_win()
	if App.player_card_collection.is_empty():
		return
	var card_data: Dictionary = App.player_card_collection[App.player_card_collection.size() - 1]
	var card_path: String = card_data.get("path", "")
	var frame: int = int(card_data.get("frame", 0))
	if card_path.is_empty():
		return
	var frames: SpriteFrames = ResourceLoader.load(card_path, "SpriteFrames", ResourceLoader.CACHE_MODE_REUSE) as SpriteFrames
	if not frames:
		return
	var root := get_parent()
	if not root:
		root = get_tree().current_scene
	var hand_container := root.get_node_or_null("HandCardsLayer/HandCardsContainer")
	if not hand_container:
		hand_container = root
	var card_manager := root.get_node_or_null("CardManager")
	if not card_manager:
		return
	var card := CARD_SCENE.instantiate()
	if not card:
		return
	hand_container.add_child(card)
	card.card_sprite_frames = frames
	card.frame_index = frame
	if card_manager.has_method("register_card"):
		card_manager.register_card(card)
	# Position will be set by _respace_hand_cards - use a temporary position
	var viewport := get_viewport()
	if viewport:
		var viewport_size := viewport.get_visible_rect().size
		card.global_position = Vector2(viewport_size.x * 0.5, viewport_size.y * 0.9)
	call_deferred("_respace_hand_cards")


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


func _update_deck_visibility() -> void:
	## Update deck visibility: show only if no cards in hand (hand not visible)
	if not _deck_p or not _deck_p.use_player_collection:
		return

	# Check if there are any cards in hand (not snapped to slots)
	var root := get_tree().current_scene
	var card_manager := root.get_node_or_null("CardManager")
	var has_hand_cards := false

	if card_manager:
		# Check if there are any cards with spawn positions that aren't snapped
		for card in card_manager.card_spawn_positions:
			if is_instance_valid(card) and not card_manager.snapped_cards.has(card):
				has_hand_cards = true
				break

	# Show deck only if no hand cards AND there are available cards to spawn
	if not has_hand_cards:
		if _deck_p.has_method("has_available_cards") and _deck_p.has_available_cards():
			if _deck_p.has_method("_show_and_enable"):
				_deck_p._show_and_enable()
		else:
			if _deck_p.has_method("_hide_and_disable"):
				_deck_p._hide_and_disable()
	else:
		# Hand is visible, hide deck
		if _deck_p.has_method("_hide_and_disable"):
			_deck_p._hide_and_disable()


func _respace_hand_cards() -> void:
	## Re-space all cards in the hand evenly whenever hand size changes.
	var root := get_tree().current_scene
	if not root:
		return
	var card_manager := root.get_node_or_null("CardManager")
	if not card_manager:
		return

	# Get all cards currently in hand (have spawn positions but not snapped)
	var hand_cards: Array = []
	for card in card_manager.card_spawn_positions:
		if not card_manager.snapped_cards.has(card):
			if is_instance_valid(card):
				hand_cards.append(card)

	# Update deck visibility based on hand state
	_update_deck_visibility()

	if hand_cards.is_empty():
		return

	# Calculate evenly spaced positions (same formula as Deck)
	var viewport := get_viewport()
	if not viewport:
		return
	var viewport_size := viewport.get_visible_rect().size
	var y := viewport_size.y * 0.9  # Use same height as Deck
	var n := hand_cards.size()

	# Update spawn positions and tween cards to new positions
	for i in range(n):
		var card = hand_cards[i]
		if not is_instance_valid(card):
			continue
		if not is_instance_of(card, Node2D):
			continue
		if not card.is_inside_tree():
			continue

		var t := float(i + 1) / float(n + 1)
		var x := viewport_size.x * t
		var new_pos := Vector2(x, y)

		# Update spawn position
		if card_manager.has_method("set_card_spawn_position"):
			card_manager.set_card_spawn_position(card, new_pos)

		# Tween card to new position (only if not being dragged)
		if card_manager.dragged_card == card:
			continue

		# Create tween
		var tween := create_tween()
		if tween:
			tween.set_ease(Tween.EASE_OUT)
			tween.set_trans(Tween.TRANS_CUBIC)
			tween.tween_property(card, "global_position", new_pos, 0.25)


func _unhandled_input(event: InputEvent) -> void:
	if state != State.RESOLVED:
		return
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and key.keycode == KEY_SPACE:
			# Handle battle outcome
			var result := _get_battle_result()
			var player_wins := result == "win"
			if BattleStateManager:
				BattleStateManager.record_battle_result(result, player_wins)
			if not player_wins:
				# Loser: clear placed cards from collection
				if BattleStateManager:
					var placed := BattleStateManager.get_local_slots()
					App.remove_placed_cards_from_collection_for_slots(placed)
					BattleStateManager.clear_local_slots()
				_clear_player_slots()
			# Winner/tie: cards persist in App.battle_placed_cards

			# Added (minimal): report finished in multiplayer for paired battle tracking.
			# Also notify left to match Leave button behavior.
			if _is_multiplayer and not _reported_battle_finished:
				Net.notify_battle_finished()
				Net.notify_battle_left()
				_reported_battle_finished = true

			Net.clear_battle_state()
			App.switch_to_main_music()
			App.on_battle_completed()
			App.go(MAIN_MENU_PATH)

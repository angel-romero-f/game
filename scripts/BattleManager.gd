extends Node

## BattleManager
## Orchestrates: opponent backs on entry, start-battle gating, flip animation,
## attribute-based resolution, and returning to menu on SPACE.

const CARD_SCENE: PackedScene = preload("res://scenes/card.tscn")
const MAIN_MENU_PATH := "res://scenes/ui/GameIntro.tscn"

enum State { SETUP, WAITING_FOR_PLAYER, FLIPPING, RESOLVED }
var state: State = State.SETUP

## Editor-provided attribute mapping + rules.
@export var attribute_config: Resource

## Node names (kept simple; pairing is fixed and intended to remain stable).
@export var player_slots: Array[StringName] = [&"CardSlotPL", &"CardSlotPM", &"CardSlotPR"]
@export var opponent_slots: Array[StringName] = [&"CardSlotOR", &"CardSlotOM", &"CardSlotOL"]

## Deck node that defines the opponent pool and the back image.
@export var deck_o_name: StringName = &"DeckO"

## UI node paths (created in scene).
@export var start_button_path: NodePath = NodePath("BattleUI/UI/StartBattleButton")
@export var result_label_path: NodePath = NodePath("BattleUI/UI/ResultLabel")
@export var continue_label_path: NodePath = NodePath("BattleUI/UI/ContinueLabel")

## Flip animation settings.
@export var flip_up_duration: float = 0.25
@export var flip_down_duration: float = 0.25
@export var offscreen_y: float = -200.0

var _player_slot_nodes: Array = []
var _opponent_slot_nodes: Array = []
var _deck_o: Node = null

var _start_button: Button
var _result_label: Label
var _continue_label: Label

var _opponent_cards_by_slot: Dictionary = {} # slot -> card

func _ready() -> void:
	_cache_nodes()
	_setup_ui()
	
	# Wait a couple frames so CardManager has time to connect existing card input,
	# and so our opponent cards don't get accidentally registered as draggable.
	await get_tree().process_frame
	await get_tree().process_frame
	
	_place_opponent_backs()
	_connect_player_slot_signals()
	_update_start_button_visibility()
	state = State.WAITING_FOR_PLAYER


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
	
	_start_button = (root.get_node_or_null(start_button_path) if root else null) as Button
	_result_label = (root.get_node_or_null(result_label_path) if root else null) as Label
	_continue_label = (root.get_node_or_null(continue_label_path) if root else null) as Label


func _setup_ui() -> void:
	if _start_button:
		_start_button.visible = false
		if not _start_button.pressed.is_connected(_on_start_battle_pressed):
			_start_button.pressed.connect(_on_start_battle_pressed)
	
	if _result_label:
		_result_label.visible = false
	if _continue_label:
		_continue_label.visible = false


func _connect_player_slot_signals() -> void:
	for slot in _player_slot_nodes:
		if slot and slot.has_signal("card_snapped"):
			if not slot.card_snapped.is_connected(_on_player_slot_changed):
				slot.card_snapped.connect(_on_player_slot_changed)
		if slot and slot.has_signal("card_unsnapped"):
			if not slot.card_unsnapped.is_connected(_on_player_slot_changed):
				slot.card_unsnapped.connect(_on_player_slot_changed)


func _on_player_slot_changed(_card: Node) -> void:
	if state != State.WAITING_FOR_PLAYER:
		return
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
	_start_button.visible = _player_ready() and state == State.WAITING_FOR_PLAYER


func _place_opponent_backs() -> void:
	# Create a non-draggable card in each opponent slot, showing the deck back.
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
	if not _player_ready():
		return
	
	if _start_button:
		_start_button.visible = false
	
	state = State.FLIPPING
	await _flip_opponent_cards_from_pool()
	_resolve_battle()
	_show_result()
	state = State.RESOLVED


func _flip_opponent_cards_from_pool() -> void:
	if not _deck_o:
		return
	
	var pool: Array = _deck_o.get("card_sprite_pool")
	var frame_indices: Array = _deck_o.get("card_frame_indices")
	
	if pool == null or pool.size() == 0:
		push_warning("BattleManager: DeckO card_sprite_pool is empty; opponent will remain unknown.")
		return
	
	# Pick a random card def for each opponent slot (SpriteFrames + frame index).
	var chosen: Dictionary = {} # slot -> {frames, frame_index}
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


func _unhandled_input(event: InputEvent) -> void:
	if state != State.RESOLVED:
		return
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and key.keycode == KEY_SPACE:
			App.switch_to_main_music()
			App.go(MAIN_MENU_PATH)


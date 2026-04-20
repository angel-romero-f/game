extends Node2D

## Deck - a static deck that can spawn cards from a pool of SpriteFrames (.pxo files).
## The deck itself is static (not draggable). On click (if enabled), it spawns cards
## along the bottom of the screen and then hides itself.

## SpriteFrames (.pxo) used to render the deck image.
@export var deck_sprite_frames: SpriteFrames

## Animation settings for the deck SpriteFrames.
@export var frame_index: int = 0
@export var animation_name: StringName = "default"

## Whether clicking the deck should spawn cards.
@export var spawn_on_click: bool = true

## Whether to use player's card collection instead of card_sprite_pool
@export var use_player_collection: bool = false

## Scene to use when spawning cards (defaults to the main Card scene).
@export var card_scene: PackedScene = preload("res://scenes/card.tscn")

## Pool of SpriteFrames (.pxo) used for spawned cards' faces.
## Add your .pxo files here. Each card spawned will randomly get one SpriteFrames from this pool.
## Four cards will be spawned by default; each card's frames are chosen randomly
## from this pool.
@export var card_sprite_pool: Array[SpriteFrames] = []

## Optional: Frame indices to use for each SpriteFrames in the pool.
## If this array has the same size as card_sprite_pool, each card will use
## the corresponding frame_index. If empty or mismatched, frame_index defaults to 0.
@export var card_frame_indices: Array[int] = []

## Number of cards to spawn when the deck is clicked.
@export var cards_to_spawn: int = 4

## Vertical position as a fraction of the viewport height where cards should appear.
## 0.8 means 80% down the screen (bottom 20% of the viewport).
@export_range(0.0, 1.0, 0.01) var card_row_height: float = 0.8

var _has_spawned: bool = false

func reset_spawned_flag() -> void:
	## Reset the spawned flag so deck can be used again (when cards are removed from slots)
	_has_spawned = false

@onready var deck_img: Sprite2D = $DeckImg
@onready var deck_area: Area2D = $Area2D


func _ready() -> void:
	if App.demo_seed == 0:
		randomize()
	_update_deck_texture()
	
	if deck_area:
		deck_area.input_pickable = true
		if not deck_area.input_event.is_connected(_on_deck_input_event):
			deck_area.input_event.connect(_on_deck_input_event)
	
	# Check if deck should be visible based on available cards
	if use_player_collection:
		if has_available_cards():
			_show_and_enable()
		else:
			_hide_and_disable()


func _update_deck_texture() -> void:
	if not deck_img:
		return
	
	var texture: Texture2D = null
	
	if deck_sprite_frames:
		if deck_sprite_frames.has_animation(animation_name):
			var frames := deck_sprite_frames.get_frame_count(animation_name)
			if frames > 0 and frame_index < frames:
				texture = deck_sprite_frames.get_frame_texture(animation_name, frame_index)
	
	if texture:
		deck_img.texture = texture


func _on_deck_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if not spawn_on_click:
		return
	
	# For player collection decks, allow multiple spawns as long as cards are available
	# For pool-based decks, only allow one spawn
	if not use_player_collection and _has_spawned:
		return
	
	# Check if there are available cards to spawn
	if not has_available_cards():
		return
	
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			_spawn_cards()
			# Only hide if no more cards available
			if not has_available_cards():
				_hide_and_disable()


func has_available_cards() -> bool:
	## Returns true if there are cards available to spawn (public method)
	# Territory battles: hand = only cards placed in territory (no extra cards from collection)
	if use_player_collection and App.pending_territory_battle_ids.size() > 0:
		return false
	if use_player_collection:
		# Check if player has any cards not already placed
		var placed_paths: Array = []
		var placed_slots: Dictionary = {}
		if BattleStateManager:
			placed_slots = BattleStateManager.get_local_slots()
		for slot_idx in placed_slots:
			var data: Dictionary = placed_slots[slot_idx]
			var path: String = data.get("path", "")
			var frame: int = int(data.get("frame", 0))
			placed_paths.append({"path": path, "frame": frame})
		
		for c in App.player_card_collection:
			var is_placed := false
			for placed in placed_paths:
				if c.get("path", "") == placed.get("path", "") and int(c.get("frame", 0)) == placed.get("frame", 0):
					is_placed = true
					break
			if not is_placed:
				return true
		return false
	else:
		# For pool-based decks, check if pool has cards
		return card_sprite_pool.size() > 0

func _spawn_cards() -> void:
	if not card_scene:
		return
	
	# For pool-based decks, only spawn once
	if not use_player_collection and _has_spawned:
		return
	
	# Check if there are available cards
	if not has_available_cards():
		return
	
	# Hide deck when spawning cards (hand will be visible)
	_hide_and_disable()
	
	var root := get_tree().current_scene
	if not root:
		return
	
	# Add cards to HandCardsContainer so they render above the UI
	var hand_container := root.get_node_or_null("HandCardsLayer/HandCardsContainer")
	if not hand_container:
		hand_container = root
	
	var viewport := get_viewport()
	if not viewport:
		return
	
	# Get available cards (from collection or pool)
	var available_cards: Array = []
	
	if use_player_collection:
		# Use player's card collection, excluding cards already placed in battle
		var placed_paths: Array = []
		var placed_slots: Dictionary = {}
		if BattleStateManager:
			placed_slots = BattleStateManager.get_local_slots()
		for slot_idx in placed_slots:
			var data: Dictionary = placed_slots[slot_idx]
			var path: String = data.get("path", "")
			var frame: int = int(data.get("frame", 0))
			placed_paths.append({"path": path, "frame": frame})
		
		for c in App.player_card_collection:
			var is_placed := false
			for placed in placed_paths:
				if c.get("path", "") == placed.get("path", "") and int(c.get("frame", 0)) == placed.get("frame", 0):
					is_placed = true
					break
			if not is_placed:
				available_cards.append(c)
	else:
		# Use card_sprite_pool (original behavior)
		if card_sprite_pool.size() > 0:
			for i in range(card_sprite_pool.size()):
				var frames := card_sprite_pool[i] as SpriteFrames
				if frames:
					var frame_idx := 0
					if card_frame_indices.size() > i:
						frame_idx = card_frame_indices[i]
					available_cards.append({"frames": frames, "frame": frame_idx})
	
	if available_cards.is_empty():
		return
	
	var viewport_size := viewport.get_visible_rect().size
	var n := available_cards.size() if use_player_collection else cards_to_spawn
	n = min(n, available_cards.size())  # Don't spawn more than available
	var y := viewport_size.y * card_row_height
	
	for i in range(n):
		var card := card_scene.instantiate()
		if not card:
			continue
		
		# Position cards evenly spaced along the bottom portion of the screen.
		var t := float(i + 1) / float(n + 1)  # (1/(n+1), 2/(n+1), ..., n/(n+1))
		var x := viewport_size.x * t
		
		# Add card to HandCardsContainer so it renders above the UI
		hand_container.add_child(card)
		if card is Node2D:
			card.global_position = Vector2(x, y)
		
		# Register the new card with CardManager so it becomes draggable/hoverable.
		var card_manager := root.get_node_or_null("CardManager")
		if card_manager and card_manager.has_method("register_card"):
			card_manager.register_card(card)
		
		# Assign SpriteFrames from available cards
		var card_data = available_cards[i]
		if use_player_collection:
			# Load from path - use ResourceLoader for imported .pxo assets
			var path: String = card_data.get("path", "")
			var frame: int = int(card_data.get("frame", 0))
			if not path.is_empty():
				var frames: SpriteFrames = ResourceLoader.load(path, "SpriteFrames", ResourceLoader.CACHE_MODE_REUSE) as SpriteFrames
				if frames:
					card.card_sprite_frames = frames
					card.frame_index = frame
		else:
			# Use frames directly from pool
			var frames: SpriteFrames = card_data.get("frames")
			if frames:
				card.card_sprite_frames = frames
				card.frame_index = int(card_data.get("frame", 0))
	
	# Mark as spawned (for pool-based decks, this prevents re-spawning)
	# For player collection decks, this flag can be reset when cards are removed
	if not use_player_collection:
		_has_spawned = true


func _hide_and_disable() -> void:
	# Make the deck invisible and non-interactive when no cards available.
	visible = false
	
	if deck_area:
		deck_area.input_pickable = false
		deck_area.monitorable = false
		deck_area.monitoring = false

func _show_and_enable() -> void:
	# Make the deck visible and interactive when cards are available.
	visible = true
	
	if deck_area:
		deck_area.input_pickable = true
		deck_area.monitorable = true
		deck_area.monitoring = true

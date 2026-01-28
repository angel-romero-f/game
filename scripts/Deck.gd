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

@onready var deck_img: Sprite2D = $DeckImg
@onready var deck_area: Area2D = $Area2D


func _ready() -> void:
	randomize()
	_update_deck_texture()
	
	if deck_area:
		deck_area.input_pickable = true
		if not deck_area.input_event.is_connected(_on_deck_input_event):
			deck_area.input_event.connect(_on_deck_input_event)


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
	if not spawn_on_click or _has_spawned:
		return
	
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			_spawn_cards()
			_hide_and_disable()


func _spawn_cards() -> void:
	if _has_spawned:
		return
	
	if cards_to_spawn <= 0:
		return
	
	if not card_scene:
		return
	
	var root := get_tree().current_scene
	if not root:
		return
	
	var viewport := get_viewport()
	if not viewport:
		return
	
	var viewport_size := viewport.get_visible_rect().size
	var n := cards_to_spawn
	var y := viewport_size.y * card_row_height
	
	for i in range(n):
		var card := card_scene.instantiate()
		if not card:
			continue
		
		# Position cards evenly spaced along the bottom portion of the screen.
		var t := float(i + 1) / float(n + 1)  # (1/(n+1), 2/(n+1), ..., n/(n+1))
		var x := viewport_size.x * t
		
		# Add card to the root (same as CardBattle) so CardManager can manage it.
		root.add_child(card)
		if card is Node2D:
			card.global_position = Vector2(x, y)
		
		# Register the new card with CardManager so it becomes draggable/hoverable.
		var card_manager := root.get_node_or_null("CardManager")
		if card_manager and card_manager.has_method("register_card"):
			card_manager.register_card(card)
		
		# Assign a random SpriteFrames from the pool if available.
		if card_sprite_pool.size() > 0:
			var idx := randi() % card_sprite_pool.size()
			var frames := card_sprite_pool[idx] as SpriteFrames
			
			if frames:
				# Get the frame index - use the corresponding entry if available, otherwise default to 0
				var frame_idx := 0
				if card_frame_indices.size() > idx:
					frame_idx = card_frame_indices[idx]
				
				# Card.gd exposes @export var card_sprite_frames: SpriteFrames
				# Set the property directly - the setter will handle updating the texture
				card.card_sprite_frames = frames
				# Also set the frame_index on the card
				card.frame_index = frame_idx
	
	_has_spawned = true


func _hide_and_disable() -> void:
	# Make the deck invisible and non-interactive after use.
	visible = false
	
	if deck_area:
		deck_area.input_pickable = false
		deck_area.monitorable = false
		deck_area.monitoring = false

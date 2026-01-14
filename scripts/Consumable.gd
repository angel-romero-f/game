extends Area2D

@export var item_type: String = "health_potion"  # Can be: health_potion, mana_potion, power_up, etc.
@export var value: int = 1

var collected: bool = false

signal consumable_collected(item_type: String, value: int)

func _ready():
	add_to_group("consumables")
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D):
	if body.is_in_group("player") and not collected:
		collect()

func collect():
	if collected:
		return
	
	collected = true
	consumable_collected.emit(item_type, value)
	
	# Visual feedback
	var tween = create_tween()
	tween.tween_property(self, "scale", Vector2(1.5, 1.5), 0.1)
	tween.tween_property(self, "modulate:a", 0.0, 0.1)
	tween.tween_callback(queue_free)

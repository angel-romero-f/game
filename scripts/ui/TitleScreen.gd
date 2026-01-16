extends Control

@onready var title_label: Label = get_node_or_null("TitleLabel")
@onready var timer: Timer = get_node_or_null("Timer")

func _ready() -> void:
	if title_label:
		title_label.text = "Clover & Clobber"
	
	if timer:
		timer.timeout.connect(_on_timer_timeout)
	else:
		# Fallback if timer missing
		await get_tree().create_timer(2.0).timeout
		_on_timer_timeout()

func _on_timer_timeout() -> void:
	App.go("res://scenes/ui/MainMenu.tscn")

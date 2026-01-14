extends Node2D

@export var collection_time: float = 30.0  # 30 seconds

var time_remaining: float
var phase_complete: bool = false

signal time_up
signal phase_completed(items_collected: int)

func _ready():
	time_remaining = collection_time

func _process(delta):
	if phase_complete:
		return
	
	time_remaining -= delta
	
	if time_remaining <= 0:
		time_remaining = 0
		complete_phase()

func complete_phase():
	if phase_complete:
		return
	
	phase_complete = true
	time_up.emit()
	
	# Get items collected
	var player = get_tree().get_first_node_in_group("player")
	var items_count = 0
	if player:
		items_count = player.items_collected
	
	phase_completed.emit(items_count)

func _input(event):
	if event.is_action_pressed("ui_accept") or (event is InputEventKey and event.keycode == KEY_R):
		# Check if phase is complete or game is over
		var ui = get_node_or_null("UI")
		if ui:
			if phase_complete or ui.game_over_panel.visible:
				restart_game()

func restart_game():
	get_tree().reload_current_scene()

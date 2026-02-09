extends ColorRect

## Clickable map territory overlay.
## Add nodes with this script on top of the map image.
## They use the local player's race color as a glow.

signal territory_clicked(territory_id: String)

@export var territory_id: String = ""
@export var base_alpha: float = 0.0
@export var hover_alpha: float = 0.45
@export var claimed_alpha: float = 0.35

var _glow_color: Color
var owner_race: String = ""
var owner_id: int = -1
var is_claimed: bool = false

func _ready() -> void:
	# Default preview glow uses the local player's race color.
	_glow_color = App.get_race_color(App.selected_race)
	_apply_state()
	mouse_filter = MOUSE_FILTER_STOP  # Ensure we receive input
	add_to_group("map_territory")
	
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	gui_input.connect(_on_gui_input)


func set_glow_color(c: Color) -> void:
	_glow_color = c
	_apply_state()


func claim_for(race: String, id: int) -> void:
	owner_race = race
	owner_id = id
	is_claimed = true
	_glow_color = App.get_race_color(race)
	_apply_state()


func _apply_state() -> void:
	var c := _glow_color
	if is_claimed:
		c.a = claimed_alpha
	else:
		c.a = base_alpha
	color = c


func _on_mouse_entered() -> void:
	var c := _glow_color
	if is_claimed and hover_alpha < claimed_alpha:
		c.a = claimed_alpha
	else:
		c.a = hover_alpha
	color = c


func _on_mouse_exited() -> void:
	_apply_state()


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		territory_clicked.emit(territory_id)

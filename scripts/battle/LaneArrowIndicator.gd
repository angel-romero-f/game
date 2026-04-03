extends Node2D

## Draws a neutral grey bar between card rows; after the lane resolves, shows an arrow toward the winner
## in the winning side's race color (tie stays grey bar only).

var _resolved: bool = false
var _round_result: String = ""
var _winner_color: Color = Color.WHITE


func reset_neutral() -> void:
	_resolved = false
	_round_result = ""
	_winner_color = Color.WHITE
	visible = true
	queue_redraw()


func apply_lane_result(round_result: String, winner_color: Color = Color.WHITE) -> void:
	_resolved = true
	_round_result = round_result
	_winner_color = winner_color
	queue_redraw()


func _draw() -> void:
	var bar_w := 36.0
	var bar_h := 10.0
	var bar := Rect2(-bar_w * 0.5, -bar_h * 0.5, bar_w, bar_h)
	var grey := Color(0.5, 0.5, 0.5, 1.0)

	if not _resolved:
		draw_rect(bar, grey)
		return

	if _round_result == "tie":
		draw_rect(bar, grey)
		return

	var win := _round_result == "win"
	var main_col := _winner_color
	draw_rect(bar, main_col)

	var pts := PackedVector2Array()
	if win:
		## Arrow points down (toward player / bottom of screen).
		pts = PackedVector2Array([
			Vector2(-9, bar_h * 0.5 + 3),
			Vector2(9, bar_h * 0.5 + 3),
			Vector2(0, bar_h * 0.5 + 18),
		])
	else:
		## Arrow points up (toward opponent / top of screen).
		pts = PackedVector2Array([
			Vector2(-9, -bar_h * 0.5 - 3),
			Vector2(9, -bar_h * 0.5 - 3),
			Vector2(0, -bar_h * 0.5 - 18),
		])
	draw_colored_polygon(pts, main_col)

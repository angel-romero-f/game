extends Control

## HowToPlay — Standalone tutorial screen accessible from Settings.
## Instantiates the real game_intro scene for authentic map, territory
## indicators, card UI, etc., then runs the gnome tutorial over it.

const GnomeTutorialUIScript := preload("res://scripts/ui/game_intro/GnomeTutorialUI.gd")
const UI_FONT := preload("res://fonts/m5x7.ttf")

var gnome_ui: Node
var _back_button: Button
var _menu_button: Button
var _game_scene: Control


func _ready() -> void:
	var packed := load("res://scenes/ui/game_intro.tscn") as PackedScene
	_game_scene = packed.instantiate() as Control
	_game_scene.set_script(null)
	add_child(_game_scene)

	var map_overlay := _game_scene.get_node("MapOverlay") as ColorRect
	var territories_container := _game_scene.get_node("TerritoriesContainer") as Control
	var card_icon_button := _game_scene.get_node("CardIconButton") as Button
	var hand_display_panel := _game_scene.get_node("HandDisplayPanel") as PanelContainer
	var hand_container := _game_scene.get_node("HandDisplayPanel/MarginContainer/VBoxContainer/HandContainer") as HBoxContainer

	var territory_mgr := TerritoryManager.new()
	territory_mgr.name = "TerritoryManager"
	_game_scene.add_child(territory_mgr)
	territory_mgr.initialize_from_editor_nodes(territories_container)

	var card_icon_tex := card_icon_button.get_node_or_null("CardIcon") as TextureRect
	if card_icon_tex:
		var cardback_sf := load("res://assets/cardback.pxo") as SpriteFrames
		if cardback_sf and cardback_sf.has_animation("default") and cardback_sf.get_frame_count("default") > 0:
			card_icon_tex.texture = cardback_sf.get_frame_texture("default", 0)

	_back_button = Button.new()
	_back_button.text = "Back"
	_back_button.add_theme_font_override("font", UI_FONT)
	_back_button.add_theme_font_size_override("font_size", 28)
	_back_button.anchor_left = 0.0
	_back_button.anchor_top = 0.0
	_back_button.offset_left = 16
	_back_button.offset_top = 16
	_back_button.offset_right = 116
	_back_button.offset_bottom = 52
	_back_button.z_index = 20
	_back_button.pressed.connect(_on_back_pressed)
	add_child(_back_button)

	gnome_ui = GnomeTutorialUIScript.new()
	gnome_ui.name = "GnomeTutorialUI"
	add_child(gnome_ui)
	gnome_ui.initialize({
		"map_overlay": map_overlay,
		"showcase_container": null,
		"territory_manager": territory_mgr,
		"card_icon_button": card_icon_button,
		"hand_display_panel": hand_display_panel,
		"hand_container": hand_container,
		"standalone": true,
	})
	gnome_ui.gnome_sequence_completed.connect(_on_gnome_done)
	gnome_ui.start_sequence()


func _process(delta: float) -> void:
	if gnome_ui:
		gnome_ui.process_frame(delta)


func _on_gnome_done() -> void:
	if gnome_ui:
		gnome_ui.queue_free()
		gnome_ui = null
	_show_menu_button()


func _show_menu_button() -> void:
	_menu_button = Button.new()
	_menu_button.text = "Back to Menu"
	_menu_button.add_theme_font_override("font", UI_FONT)
	_menu_button.add_theme_font_size_override("font_size", 36)
	_menu_button.add_theme_color_override("font_color", Color(0.95, 0.9, 0.75))
	var btn_style := StyleBoxFlat.new()
	btn_style.bg_color = Color(0.18, 0.15, 0.25, 0.95)
	btn_style.border_color = Color(0.65, 0.55, 0.35, 1.0)
	btn_style.set_border_width_all(3)
	btn_style.set_corner_radius_all(8)
	btn_style.content_margin_left = 32
	btn_style.content_margin_right = 32
	btn_style.content_margin_top = 16
	btn_style.content_margin_bottom = 16
	_menu_button.add_theme_stylebox_override("normal", btn_style)
	var hover_style := btn_style.duplicate()
	hover_style.bg_color = Color(0.28, 0.24, 0.38, 0.95)
	hover_style.border_color = Color(0.85, 0.75, 0.45, 1.0)
	_menu_button.add_theme_stylebox_override("hover", hover_style)
	_menu_button.anchor_left = 0.5
	_menu_button.anchor_top = 0.5
	_menu_button.anchor_right = 0.5
	_menu_button.anchor_bottom = 0.5
	_menu_button.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_menu_button.grow_vertical = Control.GROW_DIRECTION_BOTH
	_menu_button.z_index = 20
	_menu_button.pressed.connect(_on_menu_button_pressed)
	add_child(_menu_button)

	_menu_button.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(_menu_button, "modulate:a", 1.0, 0.5)


func _on_menu_button_pressed() -> void:
	App.go("res://scenes/ui/MainMenu.tscn")


func _on_back_pressed() -> void:
	if gnome_ui:
		gnome_ui.queue_free()
		gnome_ui = null
	App.go("res://scenes/ui/MainMenu.tscn")

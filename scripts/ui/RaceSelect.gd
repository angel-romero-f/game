extends Control

var title_label: Label
var elf_button: Button
var orc_button: Button
var fairy_button: Button
var infernal_button: Button
var back_button: Button

func _ready() -> void:
	title_label = get_node_or_null("Card/Margin/VBoxContainer/TitleLabel")
	elf_button = get_node_or_null("Card/Margin/VBoxContainer/ElfButton")
	orc_button = get_node_or_null("Card/Margin/VBoxContainer/OrcButton")
	fairy_button = get_node_or_null("Card/Margin/VBoxContainer/FairyButton")
	infernal_button = get_node_or_null("Card/Margin/VBoxContainer/InfernalButton")
	back_button = get_node_or_null("Card/Margin/VBoxContainer/BackButton")
	
	if title_label:
		title_label.text = "Select Race"
	
	if elf_button:
		elf_button.pressed.connect(_on_elf_pressed)
	if orc_button:
		orc_button.pressed.connect(_on_orc_pressed)
	if fairy_button:
		fairy_button.pressed.connect(_on_fairy_pressed)
	if infernal_button:
		infernal_button.pressed.connect(_on_infernal_pressed)
	if back_button:
		back_button.pressed.connect(_on_back_pressed)

func _on_elf_pressed() -> void:
	App.go("res://scenes/Game.tscn")

func _on_orc_pressed() -> void:
	App.go("res://scenes/Game.tscn")

func _on_fairy_pressed() -> void:
	App.go("res://scenes/Game.tscn")

func _on_infernal_pressed() -> void:
	App.go("res://scenes/Game.tscn")

func _on_back_pressed() -> void:
	App.go("res://scenes/ui/PlayMenu.tscn")

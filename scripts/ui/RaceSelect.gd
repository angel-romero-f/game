extends Control

const RACES := ["Elf", "Orc", "Fairy", "Infernal"]

var title_label: Label
var start_button: Button
var back_button: Button

var race_buttons: Dictionary = {} # race_name -> Button
var race_cards: Dictionary = {} # race_name -> PanelContainer
var race_card_default_styles: Dictionary = {} # race_name -> StyleBox

var selected_race: String = ""

func _ready() -> void:
	title_label = get_node_or_null("MainContainer/TopMargin/TitleLabel")
	start_button = get_node_or_null("MainContainer/BottomMargin/ButtonContainer/StartButton")
	back_button = get_node_or_null("MainContainer/BottomMargin/ButtonContainer/BackButton")
	
	race_cards["Elf"] = get_node_or_null("MainContainer/CardsMargin/CardsContainer/ElfCard")
	race_cards["Orc"] = get_node_or_null("MainContainer/CardsMargin/CardsContainer/OrcCard")
	race_cards["Fairy"] = get_node_or_null("MainContainer/CardsMargin/CardsContainer/FairyCard")
	race_cards["Infernal"] = get_node_or_null("MainContainer/CardsMargin/CardsContainer/InfernalCard")

	race_buttons["Elf"] = get_node_or_null("MainContainer/CardsMargin/CardsContainer/ElfCard/ElfButton")
	race_buttons["Orc"] = get_node_or_null("MainContainer/CardsMargin/CardsContainer/OrcCard/OrcButton")
	race_buttons["Fairy"] = get_node_or_null("MainContainer/CardsMargin/CardsContainer/FairyCard/FairyButton")
	race_buttons["Infernal"] = get_node_or_null("MainContainer/CardsMargin/CardsContainer/InfernalCard/InfernalButton")
	
	if title_label:
		title_label.text = "Select Race"
	
	# Store default card styles
	for race in RACES:
		var card: PanelContainer = race_cards.get(race)
		if card:
			var style = card.get_theme_stylebox("panel")
			if style:
				race_card_default_styles[race] = style
	
	# Connect race buttons
	for race in RACES:
		var b: Button = race_buttons.get(race)
		if b:
			b.pressed.connect(_on_race_pressed.bind(race))
			b.mouse_entered.connect(_on_card_hover_enter.bind(race))
			b.mouse_exited.connect(_on_card_hover_exit.bind(race))
	
	if start_button:
		start_button.pressed.connect(_on_start_pressed)
		start_button.disabled = true  # Disabled until a race is selected
	if back_button:
		back_button.pressed.connect(_on_back_pressed)

func _on_race_pressed(race: String) -> void:
	selected_race = race
	_refresh_cards()
	if start_button:
		start_button.disabled = false

func _on_start_pressed() -> void:
	if selected_race.is_empty():
		return
	App.set_selected_race(selected_race)
	App.setup_single_player_game()
	App.go("res://scenes/ui/GameIntro.tscn")

func _on_back_pressed() -> void:
	App.go("res://scenes/ui/PlayMenu.tscn")

func _on_card_hover_enter(race: String) -> void:
	var card: PanelContainer = race_cards.get(race)
	if not card:
		return
	
	# Don't override selected state
	if selected_race == race:
		return
	
	# Create hover style with white border
	var hover_style = _create_hover_style(race)
	card.add_theme_stylebox_override("panel", hover_style)

func _on_card_hover_exit(race: String) -> void:
	# Refresh to restore proper state
	_refresh_cards()

func _refresh_cards() -> void:
	for race in RACES:
		var card: PanelContainer = race_cards.get(race)
		if not card:
			continue
		
		if selected_race == race:
			# Create highlighted style with vibrant border
			var selected_style = _create_selected_style(race)
			card.add_theme_stylebox_override("panel", selected_style)
		else:
			# Reset to default style
			var default_style = race_card_default_styles.get(race)
			if default_style:
				card.add_theme_stylebox_override("panel", default_style)

func _create_selected_style(race: String) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	
	# Set background color based on race
	match race:
		"Elf":
			style.bg_color = Color(1, 0.9, 0.2, 1)  # Yellow
			style.border_color = Color(0.6, 0.5, 0.1, 1)  # Darker yellow border
		"Orc":
			style.bg_color = Color(0.2, 0.8, 0.2, 1)  # Green
			style.border_color = Color(0.1, 0.4, 0.1, 1)  # Darker green border
		"Fairy":
			style.bg_color = Color(0.7, 0.3, 0.9, 1)  # Purple
			style.border_color = Color(0.4, 0.15, 0.5, 1)  # Darker purple border
		"Infernal":
			style.bg_color = Color(0.9, 0.2, 0.2, 1)  # Red
			style.border_color = Color(0.5, 0.1, 0.1, 1)  # Darker red border
	
	# Thicker border for selected state (increased from 6 to 10)
	style.border_width_left = 10
	style.border_width_top = 10
	style.border_width_right = 10
	style.border_width_bottom = 10
	
	return style

func _create_hover_style(race: String) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	
	# Set background color based on race (same as default)
	match race:
		"Elf":
			style.bg_color = Color(1, 0.9, 0.2, 1)  # Yellow
		"Orc":
			style.bg_color = Color(0.2, 0.8, 0.2, 1)  # Green
		"Fairy":
			style.bg_color = Color(0.7, 0.3, 0.9, 1)  # Purple
		"Infernal":
			style.bg_color = Color(0.9, 0.2, 0.2, 1)  # Red
	
	# White border for hover state
	style.border_color = Color(1, 1, 1, 1)
	style.border_width_left = 5
	style.border_width_top = 5
	style.border_width_right = 5
	style.border_width_bottom = 5
	
	return style

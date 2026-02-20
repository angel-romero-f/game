extends Node

## GameFlowUI — Return-from-scene logic and minigame navigation.
## Handles skip_to_game_ready when returning from minigames/battles, plus minigame button handlers.

signal phase_transition_needed
signal phase_ui_refresh_needed(map_sub_phase: int)
signal delayed_battle_transition_needed
signal collect_resources_needed
signal show_next_player_turn(player_name: String)
signal card_won

var play_minigames_button: Button
var card_icon_button: Button

func initialize(nodes: Dictionary) -> void:
	play_minigames_button = nodes.get("play_minigames_button")
	card_icon_button = nodes.get("card_icon_button")

func skip_to_game_ready() -> int:
	## Process return-from-scene logic. Returns the resolved map_sub_phase.
	var map_sub_phase: int = PhaseController.MapSubPhase.CLAIMING

	# Check returning from territory minigame
	if App.returning_from_territory_minigame:
		App.returning_from_territory_minigame = false
		if App.pending_return_map_sub_phase != -1:
			map_sub_phase = App.pending_return_map_sub_phase
			App.pending_return_map_sub_phase = -1

		# If 2 minigames done in single-player RESOURCE_COLLECTION, start delayed battle transition
		if not App.is_multiplayer and App.current_game_phase == App.GamePhase.CLAIM_CONQUER \
			and map_sub_phase == PhaseController.MapSubPhase.RESOURCE_COLLECTION \
			and App.minigames_completed_this_phase >= App.MAX_MINIGAMES_PER_PHASE:
			delayed_battle_transition_needed.emit()

		# Skip overlay when returning from minigame
		App.show_phase_transition = false

	# Check returning from territory battles
	if App.returning_from_territory_battles:
		App.returning_from_territory_battles = false

		if App.is_multiplayer and multiplayer.has_multiplayer_peer():
			PhaseSync.request_end_claiming_turn()
		else:
			if App.current_turn_index < App.turn_order.size():
				var current_id = App.current_turn_player_id
				var player_name := _get_player_name_by_id(current_id)
				App.current_game_phase = App.GamePhase.CARD_COMMAND
				map_sub_phase = PhaseController.MapSubPhase.CLAIMING
				show_next_player_turn.emit(player_name)
			else:
				# All players done -> Resource Collection
				App.current_turn_index = 0
				App.current_turn_player_id = App.turn_order[0].get("id", -1) if App.turn_order else -1
				collect_resources_needed.emit()

	# Check if we need to show phase transition overlay
	if App.show_phase_transition:
		App.show_phase_transition = false
		phase_transition_needed.emit()
	else:
		phase_ui_refresh_needed.emit(map_sub_phase)

	return map_sub_phase

func on_minigame_pressed() -> void:
	App.go("res://scenes/Game.tscn")

func on_bridge_minigame_pressed() -> void:
	App.go("res://scenes/BridgeGame.tscn")

func on_ice_fishing_pressed() -> void:
	App.go("res://scenes/IceFishingGame.tscn")

func on_play_minigames_pressed() -> void:
	## Mock button: 50/50 chance of giving a card
	if not play_minigames_button:
		return
	var got_card := randi() % 2 == 0
	play_minigames_button.disabled = true
	if got_card:
		App.add_card_from_minigame_win()
		play_minigames_button.text = "You got a card!"
		card_won.emit()
	else:
		play_minigames_button.text = "No card this time..."
	await get_tree().create_timer(1.5).timeout
	play_minigames_button.text = "Play Minigames"
	play_minigames_button.disabled = false

func on_battle_button_pressed() -> void:
	if BattleStateManager:
		BattleStateManager.set_current_territory("default")
	App.go("res://scenes/card_battle.tscn")

func _get_player_name_by_id(peer_id: int) -> String:
	for player in App.game_players:
		if player.get("id", -1) == peer_id:
			return player.get("name", "Player")
	return "Player"

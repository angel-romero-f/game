extends Node

## Simple scene navigation helper + small UI state
var player_name: String = ""
var next_scene: String = ""
var selected_race: String = "Elf"

## Game players data for turn order
## Array of dictionaries: { "id": int, "name": String, "race": String, "roll": int, "is_local": bool }
var game_players: Array = []
var turn_order: Array = []  # Sorted game_players by roll (highest first)
var is_multiplayer: bool = false

## Lives system for minigame
const MAX_LIVES: int = 3
var current_lives: int = MAX_LIVES

## Persistent minigame timer (survives scene reload on retry).
## Set to -1.0 when not active; minigame scripts use this instead of resetting.
var minigame_time_remaining: float = -1.0

## ---------- PHASE SYSTEM ----------
## Game phases: Contest (Command -> Claim) -> Collect -> loop
enum GamePhase { CONTEST_COMMAND, CONTEST_CLAIM, COLLECT }

signal game_phase_changed(new_phase: GamePhase)
signal minigame_completed_signal  # Emitted when a minigame is won
@warning_ignore("unused_signal")
signal turn_changed(player_id: int)  # Emitted when turn changes (reserved for future use)

var current_game_phase: GamePhase = GamePhase.CONTEST_COMMAND
var minigames_completed_this_phase: int = 0
const MAX_MINIGAMES_PER_PHASE: int = 2

## Deterministic pre-rolled reward card for current minigame session.
## Set before launching minigame scene; cleared after awarding or on loss.
var pending_minigame_reward: Dictionary = {}  # {"path": String, "frame": int}

## Region bonus: active when the player owns both territories in a region and plays a minigame there.
var region_bonus_active: bool = false
var pending_bonus_reward: Dictionary = {}  # {"path": String, "frame": int}
var region_bonus_used_this_phase: Array = []

## Flag to show phase transition overlay when returning to GameIntro
var show_phase_transition: bool = false
var phase_transition_text: String = ""

## When returning from a territory minigame: restore GameIntro map sub-phase. Use CLAIMING, RESOURCE_COLLECTION, or BATTLE_READY. Use -1 when not returning.
var pending_return_map_sub_phase: int = -1
## True when we left for a minigame from territory; minigame scripts call App.on_minigame_completed() before returning.
var returning_from_territory_minigame: bool = false
## True when we just finished the territory battle sequence (Finish Claiming); GameIntro shows collect resources.
var returning_from_territory_battles: bool = false
## True only on the attacker's machine (set in PhaseController.finish_claiming_turn).
## Prevents the defender from setting returning_from_territory_battles and sending a stale end-turn RPC.
var is_territory_battle_attacker: bool = false

## Turn tracking (host-authoritative in multiplayer)
var current_turn_player_id: int = -1
var current_turn_index: int = 0

## Reference to the active TerritoryManager instance (typed as Node to avoid circular parse dependency)
var territory_manager: Node = null

## ---------- BATTLE QUEUE SYSTEM ----------
## Stores selected battles for multi-battle progression
## Array of battle indices [1, 2, 3] selected by player
var battle_queue: Array = []
## Current position in battle_queue (0-based)
var current_battle_queue_index: int = -1
## Metadata for current battle: {index, opponent_id, opponent_name, opponent_race}
var current_battle_metadata: Dictionary = {}

## ---------- TERRITORY BATTLE SEQUENCE (Finish Claiming) ----------
## After "Finish Claiming", territories with both defending and attacking cards are battled in ascending id order.
## This array holds territory_id strings; when non-empty, on_battle_completed loads the next.
var pending_territory_battle_ids: Array = []
## Attacker and defender IDs for the current territory battle (set in enter_territory_battle).
var pending_territory_battle_attacker_id: int = -1
var pending_territory_battle_defender_id: int = -1

## Set when a player wins (5/6 regions). GameIntro checks this to show victory overlay.
var game_victor_id: int = -1

## True when the local player is a spectator (not attacker or defender) in a territory battle.
var is_battle_spectator: bool = false
## Single-player bot coordinator instance (set by GameIntro).
var single_player_bot_controller: Node = null
## Bot card collections by player id (single-player only): { bot_id: [ {"path","frame"}, ... ] }
var bot_card_collections: Dictionary = {}
## If true, that bot already received the one-time 4-card opening hand; empty hand later must not auto-refill.
var bot_initial_hand_dealt: Dictionary = {}
## Territory -> attacker id map used to resolve single-player battle participants.
var territory_pending_attackers: Dictionary = {}
## How to continue after territory-battle sequence in single-player: "", "command", or "collect".
var territory_battle_resume_mode: String = ""

func enter_contest_command_phase() -> void:
	current_game_phase = GamePhase.CONTEST_COMMAND
	minigames_completed_this_phase = 0
	region_bonus_active = false
	pending_bonus_reward.clear()
	region_bonus_used_this_phase.clear()
	phase_transition_text = "Contest"
	show_phase_transition = true
	print("[HOST Phase] Entering CONTEST_COMMAND")
	game_phase_changed.emit(current_game_phase)

func enter_contest_claim_phase() -> void:
	current_game_phase = GamePhase.CONTEST_CLAIM
	minigames_completed_this_phase = 0
	region_bonus_active = false
	pending_bonus_reward.clear()
	region_bonus_used_this_phase.clear()
	phase_transition_text = "Collect"
	show_phase_transition = true
	print("[HOST Phase] Entering CONTEST_CLAIM")
	game_phase_changed.emit(current_game_phase)

func enter_collect_phase() -> void:
	current_game_phase = GamePhase.COLLECT
	minigames_completed_this_phase = 0
	region_bonus_active = false
	pending_bonus_reward.clear()
	region_bonus_used_this_phase.clear()
	phase_transition_text = "Collect"
	show_phase_transition = true
	print("[HOST Phase] Entering COLLECT")
	game_phase_changed.emit(current_game_phase)

func enter_battle_phase() -> void:
	## Show "Choose Your Battles" overlay when entering battle selection (single-player map flow)
	phase_transition_text = "Collect"
	show_phase_transition = true

func on_minigame_completed() -> void:
	## Called when player wins a minigame
	minigames_completed_this_phase += 1
	print("[Phase] Minigame completed. Count: ", minigames_completed_this_phase, "/", MAX_MINIGAMES_PER_PHASE)
	minigame_completed_signal.emit()
	
	# In multiplayer, notify host of minigame completion (host controls phase)
	if is_multiplayer and multiplayer.has_multiplayer_peer():
		PhaseSync.request_increment_minigame()
		# Don't auto-transition locally - host will broadcast phase change
		return
	
	# Single player: when max minigames reached, transition depends on current phase
	if minigames_completed_this_phase >= MAX_MINIGAMES_PER_PHASE:
		if current_game_phase == GamePhase.COLLECT:
			print("[Phase] Max minigames reached, looping to Contest Command")
			enter_contest_command_phase()
		# If in CONTEST_CLAIM, GameIntro handles BATTLE_READY transition (delayed overlay)

func on_battle_completed() -> void:
	## Called when a single battle ends - handles territory battle sequence or multi-battle queue
	print("[DEBUG] App.on_battle_completed() called. Pending IDs: ", pending_territory_battle_ids)
	if game_victor_id >= 0:
		# A winner exists; stop any remaining queued battles and return to map/victory flow.
		pending_territory_battle_ids.clear()
		territory_pending_attackers.clear()
		returning_from_territory_battles = true
		go("res://scenes/ui/game_intro.tscn")
		return
	
	# Territory battle sequence (Finish Claiming): run next territory battle or return to map
	if pending_territory_battle_ids.size() > 0:
		var next_id_str = pending_territory_battle_ids.pop_front()
		var next_id = int(next_id_str)
		
		# If Multiplayer, trigger via Net
		if is_multiplayer and multiplayer.has_multiplayer_peer():
			print("[DEBUG] Requesting Multi-Player Territory Battle: ", next_id)
			BattleSync.request_start_territory_battle(next_id)
			territory_pending_attackers.erase(next_id)
			return # Wait for RPC to call enter_territory_battle
			
		# Single Player (Local)
		print("[DEBUG] Starting Single-Player Territory Battle: ", next_id)
		var tcs := get_node_or_null("/root/TerritoryClaimState")
		var defender_id: int = int(tcs.get_owner_id(next_id)) if (tcs and tcs.has_method("get_owner_id") and tcs.get_owner_id(next_id) != null) else -1
		var attacker_id: int = int(territory_pending_attackers.get(next_id, current_turn_player_id))
		territory_pending_attackers.erase(next_id)
		enter_territory_battle(next_id, attacker_id, defender_id)
		return

	# ALL BATTLES COMPLETED (if we get here, pending list is empty)
	# But we need to distinguish between "Card Battle Queue exhausted" and "Territory Battle Sequence finished"
	# We use returning_from_territory_battles flag or just checking if we were IN that mode.
	# Actually, since we are falling through from above, we might be done.
	
	# However, we must be careful not to trigger this if we weren't even IN territory battle mode.
	# But `pending_territory_battle_ids` being empty is the default state.
	
	# We need a check.
	# The flag `returning_from_territory_battles` is what triggers the *next* step (in GameIntro).
	# But we set it HERE.
	# How do we know to set it?
	# We can check if `BattleStateManager.current_territory_id` implies a territory battle was just finished?
	# Or, relying on the fact that `_on_finish_claiming_pressed` POPULATED the list.
	# If the list is empty, we don't know if it *was* populated.
	
	# FIX: `GameIntro` sets `App.returning_from_territory_battles = true`? No.
	# We need a state variable `in_territory_battle_sequence`.
	
	# Alternative: We always check returning logic if we are in CONTEST_CLAIM phase and just finished a battle?
	# `on_battle_completed` is called after EVERY battle.
	
	# Use `BattleStateManager.current_territory_id`. If it is a valid ID (numeric string), it was a territory battle.
	# If it was "battle_X" ID from queue, it's not.
	var just_finished_territory_battle = (BattleStateManager and BattleStateManager.current_territory_id != "" and not BattleStateManager.current_territory_id.begins_with("battle_"))
	
	if just_finished_territory_battle and pending_territory_battle_ids.size() == 0:
		print("[DEBUG] All territory battles completed. Returning to GameIntro with flag set.")
		pending_territory_battle_ids.clear()
		# Single-player bot flow: resume according to explicit mode.
		if not is_multiplayer and territory_battle_resume_mode != "":
			var resume_mode := territory_battle_resume_mode
			territory_battle_resume_mode = ""
			returning_from_territory_battles = false
			is_territory_battle_attacker = false
			if resume_mode == "collect":
				enter_collect_phase()
			elif resume_mode == "command":
				enter_contest_command_phase()
			go("res://scenes/ui/game_intro.tscn")
			return
		# Multiplayer: mid-command bot battle resolved → host advances the bot's turn.
		if is_multiplayer and territory_battle_resume_mode == "mp_command":
			territory_battle_resume_mode = ""
			returning_from_territory_battles = false
			is_territory_battle_attacker = false
			if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
				print("[DEBUG] Multiplayer: Bot mid-command battles done. Host advancing bot turn.")
				PhaseSync.host_advance_bot_command_turn()
				# Advancing the turn may have triggered end-of-round battles
				# (via _server_advance_contest_command_turn) which already
				# handle their own scene transitions. Don't override them.
				if territory_battle_resume_mode != "":
					return
			go("res://scenes/ui/game_intro.tscn")
			return
		# Multiplayer: command-phase battles finished → host transitions to collect.
		if is_multiplayer and territory_battle_resume_mode == "mp_collect":
			territory_battle_resume_mode = ""
			returning_from_territory_battles = false
			is_territory_battle_attacker = false
			if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
				print("[DEBUG] Multiplayer: All command-phase battles done. Host entering Contest Claim (collect).")
				PhaseSync._server_enter_contest_claim_phase()
			go("res://scenes/ui/game_intro.tscn")
			return
		if is_territory_battle_attacker:
			returning_from_territory_battles = true
		
		# If Multiplayer, we need to notify the server we are done with battles/claiming
		if is_multiplayer and multiplayer.has_multiplayer_peer():
			print("[DEBUG] Multiplayer: Requesting end claiming turn after battles.")
			pass # Logic will be handled in GameIntro._ready()
		else:
			# SINGLE PLAYER LOGIC
			# Current turn player finished claiming & battles.
			current_turn_index += 1
			print("[DEBUG] Advanced turn index locally to: ", current_turn_index)
			if current_turn_index < turn_order.size():
				# Next player's turn
				current_turn_player_id = turn_order[current_turn_index].get("id", -1)
				print("[DEBUG] Next player ID: ", current_turn_player_id)
				go("res://scenes/ui/game_intro.tscn")
				return

		go("res://scenes/ui/game_intro.tscn")
		return
	
	# Check if more battles in queue
	if battle_queue.size() > 0 and current_battle_queue_index < battle_queue.size() - 1:
		current_battle_queue_index += 1
		print("[Phase] Loading next battle from queue: ", current_battle_queue_index + 1, "/", battle_queue.size())
		_load_next_queued_battle()
	else:
		# Queue exhausted - clear and return to GameIntro
		print("[Phase] Battle queue exhausted, returning to GameIntro")
		battle_queue.clear()
		current_battle_queue_index = -1
		current_battle_metadata.clear()
		
		# In multiplayer, notify host we finished our battles
		if is_multiplayer and multiplayer.has_multiplayer_peer():
			BattleSync.notify_battle_finished()
		
		go("res://scenes/ui/game_intro.tscn")

func _load_next_queued_battle() -> void:
	## Load the next battle from the queue
	var battle_idx: int = battle_queue[current_battle_queue_index]
	current_battle_metadata = _get_battle_metadata(battle_idx)
	print("[Phase] Loading battle ", battle_idx, " vs ", current_battle_metadata.get("opponent_name", "Unknown"))
	
	if BattleStateManager:
		var territory_id := "battle_%d" % battle_idx
		BattleStateManager.set_current_territory(territory_id)
	
	go("res://scenes/card_battle.tscn")

func start_battle_queue(selected_battles: Array) -> void:
	## Start the multi-battle queue with selected battles
	battle_queue = selected_battles.duplicate()
	current_battle_queue_index = 0
	
	if battle_queue.is_empty():
		# No battles selected - skip to next player/phase
		print("[Phase] No battles selected, skipping")
		on_battle_completed()
		return
	
	_load_next_queued_battle()

func _get_battle_metadata(battle_idx: int) -> Dictionary:
	## Get opponent info for a battle (placeholder mapping for now)
	## Battle 1 -> player index 1, Battle 2 -> player index 2, etc.
	var opponent_idx := battle_idx  # 1-based battle_idx maps to player index
	var opponent_id: int = -1
	var opponent_name := "Unknown"
	var opponent_race := "Unknown"
	
	if opponent_idx < turn_order.size():
		var opponent = turn_order[opponent_idx]
		opponent_id = opponent.get("id", -1)
		opponent_name = opponent.get("name", "Unknown")
		opponent_race = opponent.get("race", "Unknown")
	
	return {
		"battle_index": battle_idx,
		"opponent_id": opponent_id,
		"opponent_name": opponent_name,
		"opponent_race": opponent_race
	}

func skip_to_done() -> void:
	## Called when player chooses to skip (during Card Collection)
	print("[Phase] Player skipping to done")
	
	# In multiplayer, request host to mark us as done
	if is_multiplayer and multiplayer.has_multiplayer_peer():
		PhaseSync.request_skip_to_done()
		return
	
	# Single player: transition immediately to next round
	enter_contest_command_phase()

func can_play_minigame() -> bool:
	## Returns true if player can still play minigames this phase
	if current_game_phase != GamePhase.COLLECT:
		return false
	# In multiplayer, check host-authoritative done state
	if is_multiplayer and multiplayer.has_multiplayer_peer():
		var my_id := multiplayer.get_unique_id()
		# If host marked us as done, we cannot play
		if PhaseController.player_done_state.get(my_id, false):
			return false
		# Also check minigame count from host
		var count: int = PhaseController.player_minigame_counts.get(my_id, 0)
		if count >= MAX_MINIGAMES_PER_PHASE:
			return false
	return minigames_completed_this_phase < MAX_MINIGAMES_PER_PHASE

func reset_phase_state() -> void:
	current_game_phase = GamePhase.CONTEST_COMMAND
	minigames_completed_this_phase = 0
	region_bonus_active = false
	pending_bonus_reward.clear()
	region_bonus_used_this_phase.clear()
	show_phase_transition = false
	phase_transition_text = ""
	current_turn_player_id = -1
	current_turn_index = 0
	battle_queue.clear()
	current_battle_queue_index = -1
	current_battle_metadata.clear()
	is_territory_battle_attacker = false
## ---------- END PHASE SYSTEM ----------

## ---------- PLAYER HAND SYSTEM ----------
## Available cards - each entry is {sprite_frames_path, frame_index}
## Race-specific card pools
const ELF_CARDS: Array = [
	{"sprite_frames": "res://assets/elf_fire_cards.pxo", "frame_index": 0},
	{"sprite_frames": "res://assets/elf_fire_cards.pxo", "frame_index": 1},
	{"sprite_frames": "res://assets/elf_fire_cards.pxo", "frame_index": 2},
	{"sprite_frames": "res://assets/elf_fire_cards.pxo", "frame_index": 3},
	{"sprite_frames": "res://assets/elf_air_cards.pxo", "frame_index": 0},
	{"sprite_frames": "res://assets/elf_air_cards.pxo", "frame_index": 1},
	{"sprite_frames": "res://assets/elf_air_cards.pxo", "frame_index": 2},
	{"sprite_frames": "res://assets/elf_air_cards.pxo", "frame_index": 3},
	{"sprite_frames": "res://assets/elf_water_cards.pxo", "frame_index": 0},
	{"sprite_frames": "res://assets/elf_water_cards.pxo", "frame_index": 1},
	{"sprite_frames": "res://assets/elf_water_cards.pxo", "frame_index": 2},
	{"sprite_frames": "res://assets/elf_water_cards.pxo", "frame_index": 3},
]

const INFERNAL_CARDS: Array = [
	{"sprite_frames": "res://assets/infernal_water_cards.pxo", "frame_index": 0},
	{"sprite_frames": "res://assets/infernal_water_cards.pxo", "frame_index": 1},
	{"sprite_frames": "res://assets/infernal_water_cards.pxo", "frame_index": 2},
	{"sprite_frames": "res://assets/infernal_water_cards.pxo", "frame_index": 3},
	{"sprite_frames": "res://assets/infernal_air_cards.pxo", "frame_index": 0},
	{"sprite_frames": "res://assets/infernal_air_cards.pxo", "frame_index": 1},
	{"sprite_frames": "res://assets/infernal_air_cards.pxo", "frame_index": 2},
	{"sprite_frames": "res://assets/infernal_air_cards.pxo", "frame_index": 3},
	{"sprite_frames": "res://assets/infernal_fire_cards.pxo", "frame_index": 0},
	{"sprite_frames": "res://assets/infernal_fire_cards.pxo", "frame_index": 1},
	{"sprite_frames": "res://assets/infernal_fire_cards.pxo", "frame_index": 2},
	{"sprite_frames": "res://assets/infernal_fire_cards.pxo", "frame_index": 3},
]

const FAIRY_CARDS: Array = [
	{"sprite_frames": "res://assets/fairy_air_cards.pxo", "frame_index": 0},
	{"sprite_frames": "res://assets/fairy_air_cards.pxo", "frame_index": 1},
	{"sprite_frames": "res://assets/fairy_air_cards.pxo", "frame_index": 2},
	{"sprite_frames": "res://assets/fairy_air_cards.pxo", "frame_index": 3},
	{"sprite_frames": "res://assets/fairy_water_card.pxo", "frame_index": 0},
	{"sprite_frames": "res://assets/fairy_water_card.pxo", "frame_index": 1},
	{"sprite_frames": "res://assets/fairy_water_card.pxo", "frame_index": 2},
	{"sprite_frames": "res://assets/fairy_water_card.pxo", "frame_index": 3},
	{"sprite_frames": "res://assets/fairy_fire_cards.pxo", "frame_index": 0},
	{"sprite_frames": "res://assets/fairy_fire_cards.pxo", "frame_index": 1},
	{"sprite_frames": "res://assets/fairy_fire_cards.pxo", "frame_index": 2},
	{"sprite_frames": "res://assets/fairy_fire_cards.pxo", "frame_index": 3},
]

const ORC_CARDS: Array = [
	{"sprite_frames": "res://assets/orc_water_cards.pxo", "frame_index": 0},
	{"sprite_frames": "res://assets/orc_water_cards.pxo", "frame_index": 1},
	{"sprite_frames": "res://assets/orc_water_cards.pxo", "frame_index": 2},
	{"sprite_frames": "res://assets/orc_water_cards.pxo", "frame_index": 3},
	{"sprite_frames": "res://assets/orc_fire_cards.pxo", "frame_index": 0},
	{"sprite_frames": "res://assets/orc_fire_cards.pxo", "frame_index": 1},
	{"sprite_frames": "res://assets/orc_fire_cards.pxo", "frame_index": 2},
	{"sprite_frames": "res://assets/orc_fire_cards.pxo", "frame_index": 3},
	{"sprite_frames": "res://assets/orc_air_cards.pxo", "frame_index": 0},
	{"sprite_frames": "res://assets/orc_air_cards.pxo", "frame_index": 1},
	{"sprite_frames": "res://assets/orc_air_cards.pxo", "frame_index": 2},
	{"sprite_frames": "res://assets/orc_air_cards.pxo", "frame_index": 3},
]

const MIXED_CARD_POOL: Array = [
	{"sprite_frames": "res://assets/elf_fire_cards.pxo", "frame_index": 0},
	{"sprite_frames": "res://assets/elf_fire_cards.pxo", "frame_index": 1},
	{"sprite_frames": "res://assets/elf_fire_cards.pxo", "frame_index": 2},
	{"sprite_frames": "res://assets/elf_fire_cards.pxo", "frame_index": 3},
	{"sprite_frames": "res://assets/elf_air_cards.pxo", "frame_index": 0},
	{"sprite_frames": "res://assets/elf_air_cards.pxo", "frame_index": 1},
	{"sprite_frames": "res://assets/elf_air_cards.pxo", "frame_index": 2},
	{"sprite_frames": "res://assets/elf_air_cards.pxo", "frame_index": 3},
	{"sprite_frames": "res://assets/elf_water_cards.pxo", "frame_index": 0},
	{"sprite_frames": "res://assets/elf_water_cards.pxo", "frame_index": 1},
	{"sprite_frames": "res://assets/elf_water_cards.pxo", "frame_index": 2},
	{"sprite_frames": "res://assets/elf_water_cards.pxo", "frame_index": 3},
	{"sprite_frames": "res://assets/infernal_water_cards.pxo", "frame_index": 0},
	{"sprite_frames": "res://assets/infernal_water_cards.pxo", "frame_index": 1},
	{"sprite_frames": "res://assets/infernal_water_cards.pxo", "frame_index": 2},
	{"sprite_frames": "res://assets/infernal_water_cards.pxo", "frame_index": 3},
	{"sprite_frames": "res://assets/infernal_air_cards.pxo", "frame_index": 0},
	{"sprite_frames": "res://assets/infernal_air_cards.pxo", "frame_index": 1},
	{"sprite_frames": "res://assets/infernal_air_cards.pxo", "frame_index": 2},
	{"sprite_frames": "res://assets/infernal_air_cards.pxo", "frame_index": 3},
	{"sprite_frames": "res://assets/infernal_fire_cards.pxo", "frame_index": 0},
	{"sprite_frames": "res://assets/infernal_fire_cards.pxo", "frame_index": 1},
	{"sprite_frames": "res://assets/infernal_fire_cards.pxo", "frame_index": 2},
	{"sprite_frames": "res://assets/infernal_fire_cards.pxo", "frame_index": 3},
	{"sprite_frames": "res://assets/fairy_air_cards.pxo", "frame_index": 0},
	{"sprite_frames": "res://assets/fairy_air_cards.pxo", "frame_index": 1},
	{"sprite_frames": "res://assets/fairy_air_cards.pxo", "frame_index": 2},
	{"sprite_frames": "res://assets/fairy_air_cards.pxo", "frame_index": 3},
	{"sprite_frames": "res://assets/fairy_water_card.pxo", "frame_index": 0},
	{"sprite_frames": "res://assets/fairy_water_card.pxo", "frame_index": 1},
	{"sprite_frames": "res://assets/fairy_water_card.pxo", "frame_index": 2},
	{"sprite_frames": "res://assets/fairy_water_card.pxo", "frame_index": 3},
	{"sprite_frames": "res://assets/fairy_fire_cards.pxo", "frame_index": 0},
	{"sprite_frames": "res://assets/fairy_fire_cards.pxo", "frame_index": 1},
	{"sprite_frames": "res://assets/fairy_fire_cards.pxo", "frame_index": 2},
	{"sprite_frames": "res://assets/fairy_fire_cards.pxo", "frame_index": 3},
	{"sprite_frames": "res://assets/orc_water_cards.pxo", "frame_index": 0},
	{"sprite_frames": "res://assets/orc_water_cards.pxo", "frame_index": 1},
	{"sprite_frames": "res://assets/orc_water_cards.pxo", "frame_index": 2},
	{"sprite_frames": "res://assets/orc_water_cards.pxo", "frame_index": 3},
	{"sprite_frames": "res://assets/orc_fire_cards.pxo", "frame_index": 0},
	{"sprite_frames": "res://assets/orc_fire_cards.pxo", "frame_index": 1},
	{"sprite_frames": "res://assets/orc_fire_cards.pxo", "frame_index": 2},
	{"sprite_frames": "res://assets/orc_fire_cards.pxo", "frame_index": 3},
	{"sprite_frames": "res://assets/orc_air_cards.pxo", "frame_index": 0},
	{"sprite_frames": "res://assets/orc_air_cards.pxo", "frame_index": 1},
	{"sprite_frames": "res://assets/orc_air_cards.pxo", "frame_index": 2},
	{"sprite_frames": "res://assets/orc_air_cards.pxo", "frame_index": 3},
]

const FIRE_CARD_POOL: Array = [
	{"sprite_frames": "res://assets/elf_fire_cards.pxo", "frame_index": 0},
	{"sprite_frames": "res://assets/elf_fire_cards.pxo", "frame_index": 1},
	{"sprite_frames": "res://assets/elf_fire_cards.pxo", "frame_index": 2},
	{"sprite_frames": "res://assets/elf_fire_cards.pxo", "frame_index": 3},
	{"sprite_frames": "res://assets/infernal_fire_cards.pxo", "frame_index": 0},
	{"sprite_frames": "res://assets/infernal_fire_cards.pxo", "frame_index": 1},
	{"sprite_frames": "res://assets/infernal_fire_cards.pxo", "frame_index": 2},
	{"sprite_frames": "res://assets/infernal_fire_cards.pxo", "frame_index": 3},
	{"sprite_frames": "res://assets/fairy_fire_cards.pxo", "frame_index": 0},
	{"sprite_frames": "res://assets/fairy_fire_cards.pxo", "frame_index": 1},
	{"sprite_frames": "res://assets/fairy_fire_cards.pxo", "frame_index": 2},
	{"sprite_frames": "res://assets/fairy_fire_cards.pxo", "frame_index": 3},
	{"sprite_frames": "res://assets/orc_fire_cards.pxo", "frame_index": 0},
	{"sprite_frames": "res://assets/orc_fire_cards.pxo", "frame_index": 1},
	{"sprite_frames": "res://assets/orc_fire_cards.pxo", "frame_index": 2},
	{"sprite_frames": "res://assets/orc_fire_cards.pxo", "frame_index": 3},
]

const WATER_CARD_POOL: Array = [
	{"sprite_frames": "res://assets/infernal_water_cards.pxo", "frame_index": 0},
	{"sprite_frames": "res://assets/infernal_water_cards.pxo", "frame_index": 1},
	{"sprite_frames": "res://assets/infernal_water_cards.pxo", "frame_index": 2},
	{"sprite_frames": "res://assets/infernal_water_cards.pxo", "frame_index": 3},
	{"sprite_frames": "res://assets/elf_water_cards.pxo", "frame_index": 0},
	{"sprite_frames": "res://assets/elf_water_cards.pxo", "frame_index": 1},
	{"sprite_frames": "res://assets/elf_water_cards.pxo", "frame_index": 2},
	{"sprite_frames": "res://assets/elf_water_cards.pxo", "frame_index": 3},
	{"sprite_frames": "res://assets/fairy_water_card.pxo", "frame_index": 0},
	{"sprite_frames": "res://assets/fairy_water_card.pxo", "frame_index": 1},
	{"sprite_frames": "res://assets/fairy_water_card.pxo", "frame_index": 2},
	{"sprite_frames": "res://assets/fairy_water_card.pxo", "frame_index": 3},
	{"sprite_frames": "res://assets/orc_water_cards.pxo", "frame_index": 0},
	{"sprite_frames": "res://assets/orc_water_cards.pxo", "frame_index": 1},
	{"sprite_frames": "res://assets/orc_water_cards.pxo", "frame_index": 2},
	{"sprite_frames": "res://assets/orc_water_cards.pxo", "frame_index": 3},
]

const AIR_CARD_POOL: Array = [
	{"sprite_frames": "res://assets/infernal_air_cards.pxo", "frame_index": 0},
	{"sprite_frames": "res://assets/infernal_air_cards.pxo", "frame_index": 1},
	{"sprite_frames": "res://assets/infernal_air_cards.pxo", "frame_index": 2},
	{"sprite_frames": "res://assets/infernal_air_cards.pxo", "frame_index": 3},
	{"sprite_frames": "res://assets/elf_air_cards.pxo", "frame_index": 0},
	{"sprite_frames": "res://assets/elf_air_cards.pxo", "frame_index": 1},
	{"sprite_frames": "res://assets/elf_air_cards.pxo", "frame_index": 2},
	{"sprite_frames": "res://assets/elf_air_cards.pxo", "frame_index": 3},
	{"sprite_frames": "res://assets/fairy_air_cards.pxo", "frame_index": 0},
	{"sprite_frames": "res://assets/fairy_air_cards.pxo", "frame_index": 1},
	{"sprite_frames": "res://assets/fairy_air_cards.pxo", "frame_index": 2},
	{"sprite_frames": "res://assets/fairy_air_cards.pxo", "frame_index": 3},
	{"sprite_frames": "res://assets/orc_air_cards.pxo", "frame_index": 0},
	{"sprite_frames": "res://assets/orc_air_cards.pxo", "frame_index": 1},
	{"sprite_frames": "res://assets/orc_air_cards.pxo", "frame_index": 2},
	{"sprite_frames": "res://assets/orc_air_cards.pxo", "frame_index": 3},
]

## In this project, "earth/life" uses the existing air card assets/pool.
const EARTH_LIFE_CARD_POOL: Array = AIR_CARD_POOL

## Region -> attribute card pool for territory minigame rewards.
## Adjust this mapping if you want different colony/region attribute identities.
const REGION_ATTRIBUTE_TYPE: Dictionary = {
	1: "earth_life",
	2: "fire",
	3: "earth_life",
	4: "water",
	5: "water",
	6: "fire",
}

## Player's current hand - array of card data dictionaries (legacy, used for hand display)
var player_hand: Array = []

## Player's card collection - the cards they own. Format: [{ "path": String, "frame": int }, ...]
## At game start: 4 random cards. After minigame win: +1 random card.
var player_card_collection: Array = []

## Legacy: persisted card placements when leaving battle early (single active battle).
## slot_index (0-2) -> { "path": String, "frame": int }
## New code should prefer BattleStateManager for per-territory state.
var battle_placed_cards: Dictionary = {}

## ---------- MAP TERRITORY OWNERSHIP ----------
## territory_id -> {
##   "owner_id": int,
##   "owner_name": String,
##   "owner_race": String,
##   "cards": Array[Dictionary]  # cards committed to this territory
## }
var territories: Dictionary = {}

func reset_territories() -> void:
	territories.clear()

func place_card_on_territory(territory_id: String, player: Dictionary, card_data: Dictionary) -> void:
	if territory_id.is_empty():
		return
	var t: Dictionary = territories.get(territory_id, {})
	t["owner_id"] = player.get("id", 0)
	t["owner_name"] = player.get("name", "Player")
	t["owner_race"] = player.get("race", "Elf")
	if not t.has("cards"):
		t["cards"] = []
	var cards: Array = t["cards"]
	cards.append(card_data.duplicate())
	t["cards"] = cards
	territories[territory_id] = t

func get_territory(territory_id: String) -> Dictionary:
	return territories.get(territory_id, {})

## ---------- END MAP TERRITORY OWNERSHIP ----------

func initialize_player_hand(hand_size: int = 3) -> void:
	## Randomly selects cards from the appropriate pool based on selected race
	player_hand.clear()
	
	# Choose card pool based on race
	var card_pool: Array
	match selected_race:
		"Elf":
			card_pool = ELF_CARDS.duplicate()
		"Infernal":
			card_pool = INFERNAL_CARDS.duplicate()
		"Fairy":
			card_pool = FAIRY_CARDS.duplicate()
		"Orc":
			card_pool = ORC_CARDS.duplicate()
			print("[Hand] Using Infernal card pool")
		_:
			card_pool = MIXED_CARD_POOL.duplicate()	
	card_pool.shuffle()
	for i in range(mini(hand_size, card_pool.size())):
		player_hand.append(card_pool[i].duplicate())
	print("[Hand] Initialized player hand with ", player_hand.size(), " cards")

func reset_player_hand() -> void:
	## Clears the player's hand
	player_hand.clear()

## Remove cards described by a placed-slots dictionary from the player's collection.
## placed_slots: slot_index -> { "path": String, "frame": int }
## reason: for logging only - "battle_lost" (default), "placed_attacking", "placed_defending", etc.
func remove_placed_cards_from_collection_for_slots(placed_slots: Dictionary, reason: String = "battle_lost") -> void:
	var removed := 0
	for slot_idx in placed_slots:
		var card_data: Dictionary = placed_slots[slot_idx]
		var path: String = card_data.get("path", "")
		var frame: int = int(card_data.get("frame", 0))
		for i in range(player_card_collection.size() - 1, -1, -1):
			var c: Dictionary = player_card_collection[i]
			if c.get("path", "") == path and int(c.get("frame", 0)) == frame:
				player_card_collection.remove_at(i)
				removed += 1
				break
	if removed > 0:
		print("[Cards] Removed ", removed, " placed cards from collection (", reason, ")")
		_notify_card_count_changed()


## Backwards-compatible helper using legacy battle_placed_cards.
func remove_placed_cards_from_collection() -> void:
	remove_placed_cards_from_collection_for_slots(battle_placed_cards)

## Initialize player's card collection with 4 random cards at game start
func initialize_player_card_collection() -> void:
	player_card_collection.clear()
	var card_pool: Array
	match selected_race:
		"Elf":
			card_pool = ELF_CARDS.duplicate()
		"Infernal":
			card_pool = INFERNAL_CARDS.duplicate()
		"Fairy":
			card_pool = FAIRY_CARDS.duplicate()
		"Orc":
			card_pool = ORC_CARDS.duplicate()
		_:
			card_pool = MIXED_CARD_POOL.duplicate()
	card_pool.shuffle()
	for i in range(mini(4, card_pool.size())):
		var c: Dictionary = card_pool[i].duplicate()
		player_card_collection.append({"path": c.get("sprite_frames", ""), "frame": int(c.get("frame_index", 0))})
	print("[Cards] Initialized collection with ", player_card_collection.size(), " cards")
	_notify_card_count_changed()

## Add a random card when player wins a minigame
func add_card_from_minigame_win() -> void:
	var card_pool: Array = MIXED_CARD_POOL.duplicate()
	if card_pool.is_empty():
		return
	var c: Dictionary = card_pool[randi() % card_pool.size()].duplicate()
	player_card_collection.append({"path": c.get("sprite_frames", ""), "frame": int(c.get("frame_index", 0))})
	print("[Cards] Added card from minigame win. Collection size: ", player_card_collection.size())
	_notify_card_count_changed()

## Pre-roll (deterministically pick) the reward card before the minigame scene loads.
## Stores it in pending_minigame_reward so the minigame UI can preview it.
func pre_roll_minigame_reward() -> void:
	pre_roll_minigame_reward_for_region(-1)

func pre_roll_minigame_reward_for_region(region_id: int) -> void:
	var card_pool: Array = _get_card_pool_for_region(region_id)
	if card_pool.is_empty():
		pending_minigame_reward = {}
		return
	var c: Dictionary = card_pool[randi() % card_pool.size()].duplicate()
	pending_minigame_reward = {"path": c.get("sprite_frames", ""), "frame": int(c.get("frame_index", 0))}
	# Reset the persistent timer so the new minigame gets a fresh 30s
	minigame_time_remaining = -1.0
	print("[Cards] Pre-rolled reward: %s frame %d" % [pending_minigame_reward.get("path", ""), pending_minigame_reward.get("frame", 0)])

## Pre-roll a bonus reward card for the region bonus (called when player owns full region).
func pre_roll_bonus_reward() -> void:
	pre_roll_bonus_reward_for_region(-1)

func pre_roll_bonus_reward_for_region(region_id: int) -> void:
	var card_pool: Array = _get_card_pool_for_region(region_id)
	if card_pool.is_empty():
		pending_bonus_reward = {}
		return
	var c: Dictionary = card_pool[randi() % card_pool.size()].duplicate()
	pending_bonus_reward = {"path": c.get("sprite_frames", ""), "frame": int(c.get("frame_index", 0))}
	print("[Cards] Pre-rolled region bonus reward: %s frame %d" % [pending_bonus_reward.get("path", ""), pending_bonus_reward.get("frame", 0)])

func _get_card_pool_for_region(region_id: int) -> Array:
	if region_id < 0:
		return MIXED_CARD_POOL.duplicate()
	var attribute: String = str(REGION_ATTRIBUTE_TYPE.get(region_id, "mixed"))
	match attribute:
		"fire":
			return FIRE_CARD_POOL.duplicate()
		"water":
			return WATER_CARD_POOL.duplicate()
		"earth_life":
			return EARTH_LIFE_CARD_POOL.duplicate()
		_:
			return MIXED_CARD_POOL.duplicate()

## Award the pre-rolled reward card (called on minigame WIN instead of add_card_from_minigame_win).
## Also awards the region bonus card if the player owns the full region.
func add_card_from_pending_reward() -> void:
	if pending_minigame_reward.is_empty():
		add_card_from_minigame_win()
	else:
		player_card_collection.append(pending_minigame_reward.duplicate())
		print("[Cards] Awarded pending reward card. Collection size: ", player_card_collection.size())
		pending_minigame_reward.clear()

	if region_bonus_active and not pending_bonus_reward.is_empty():
		player_card_collection.append(pending_bonus_reward.duplicate())
		print("[Cards] Awarded region bonus card! Collection size: ", player_card_collection.size())
		pending_bonus_reward.clear()
	region_bonus_active = false
	_notify_card_count_changed()

func _notify_card_count_changed() -> void:
	if is_multiplayer and get_tree().get_multiplayer().has_multiplayer_peer():
		PhaseSync.report_card_count()
	else:
		var players: Array = game_players if not game_players.is_empty() else turn_order
		for p in players:
			var pid: int = int(p.get("id", -1))
			if bool(p.get("is_local", false)):
				PhaseController.player_card_counts[pid] = player_card_collection.size()
			else:
				var bot_cards: Array = bot_card_collections.get(pid, [])
				PhaseController.player_card_counts[pid] = bot_cards.size()
		if not players.is_empty():
			PhaseController.card_counts_updated.emit()
## ---------- END PLAYER HAND SYSTEM ----------

func reset_lives() -> void:
	current_lives = MAX_LIVES

func lose_life() -> bool:
	## Returns true if game over (no lives left)
	current_lives -= 1
	return current_lives <= 0

func get_lives() -> int:
	return current_lives

var main_music: AudioStreamPlayer
var battle_music: AudioStreamPlayer
var ui_sfx: AudioStreamPlayer
var blip_select_stream: AudioStream

func _ready() -> void:
	# Ensure audio buses exist
	_setup_audio_buses()
	
	# Create and start main music immediately on game launch
	main_music = AudioStreamPlayer.new()
	main_music.name = "MainMusic"
	main_music.bus = "Music"  # Assign to Music bus
	add_child(main_music)
	
	# Load the music stream
	var stream: AudioStreamMP3 = load("res://music/main_music.mp3")
	if stream == null and FileAccess.file_exists("res://music/main_music.mp3"):
		stream = AudioStreamMP3.new()
		stream.data = FileAccess.get_file_as_bytes("res://music/main_music.mp3")
	
	if stream:
		stream.loop = true
		main_music.stream = stream
		main_music.play()
		print("Main music started from App autoload")
	
	# Create battle music player
	battle_music = AudioStreamPlayer.new()
	battle_music.name = "BattleMusic"
	battle_music.bus = "Music"  # Assign to Music bus
	add_child(battle_music)
	
	# Load the battle music stream
	var battle_stream: AudioStreamMP3 = load("res://music/battle_music.mp3")
	if battle_stream == null and FileAccess.file_exists("res://music/battle_music.mp3"):
		battle_stream = AudioStreamMP3.new()
		battle_stream.data = FileAccess.get_file_as_bytes("res://music/battle_music.mp3")
	
	if battle_stream:
		battle_stream.loop = true
		battle_music.stream = battle_stream
		print("Battle music loaded in App autoload")

	# UI SFX (button blips, etc.)
	ui_sfx = AudioStreamPlayer.new()
	ui_sfx.name = "UISfx"
	ui_sfx.bus = "UI"  # Assign to UI bus
	add_child(ui_sfx)
	blip_select_stream = load("res://sounds/blipSelect.wav")
	if blip_select_stream:
		ui_sfx.stream = blip_select_stream

	# Auto-hook any buttons added to the scene tree (covers all screens/scenes).
	if not get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.connect(_on_node_added)
	call_deferred("_hook_buttons_on_current_scene")

	# Win condition: show victory when a player owns 5/6 regions
	if WinConditionManager and not WinConditionManager.player_won.is_connected(_on_player_won):
		WinConditionManager.player_won.connect(_on_player_won)

func go(path: String) -> void:
	get_tree().change_scene_to_file(path)
	call_deferred("_hook_buttons_on_current_scene")

@warning_ignore("shadowed_variable_base_class")
func set_player_name(name: String) -> void:
	player_name = name.strip_edges()

func set_next_scene(path: String) -> void:
	next_scene = path

func set_selected_race(race: String) -> void:
	selected_race = race.strip_edges()

func setup_single_player_game() -> void:
	is_multiplayer = false
	game_players.clear()
	turn_order.clear()
	reset_lives()
	reset_phase_state()
	reset_territories()
	bot_card_collections.clear()
	bot_initial_hand_dealt.clear()
	single_player_bot_controller = null
	territory_pending_attackers.clear()
	territory_battle_resume_mode = ""
	initialize_player_hand()
	initialize_player_card_collection()
	# Use path built from parts so the autoload name is not parsed as an identifier
	var tcs_path: String = "/root/" + "Territory" + "Claim" + "State"
	var tcs: Node = get_node_or_null(tcs_path)
	if tcs and tcs.has_method("clear_all"):
		tcs.clear_all()
	
	# Add the local player
	var local_player := {
		"id": 1,
		"name": player_name if not player_name.is_empty() else "Player",
		"race": selected_race,
		"roll": 0,
		"is_local": true
	}
	game_players.append(local_player)
	
	# Generate 3 AI opponents with the remaining races
	var all_races := ["Elf", "Orc", "Fairy", "Infernal"]
	var available_races: Array = []
	for r in all_races:
		if r != selected_race:
			available_races.append(r)
	available_races.shuffle()
	
	var ai_names := ["Thorne", "Mira", "Grak", "Lyra", "Korrin", "Sable", "Dusk", "Ember"]
	ai_names.shuffle()
	
	for i in range(3):
		var ai_player := {
			"id": i + 100,  # AI IDs start at 100
			"name": ai_names[i],
			"race": available_races[i],
			"roll": 0,
			"is_local": false
		}
		game_players.append(ai_player)

func setup_multiplayer_game() -> void:
	is_multiplayer = true
	game_players.clear()
	turn_order.clear()
	reset_lives()
	reset_phase_state()
	reset_territories()
	bot_card_collections.clear()
	bot_initial_hand_dealt.clear()
	single_player_bot_controller = null
	territory_pending_attackers.clear()
	territory_battle_resume_mode = ""
	initialize_player_hand()
	initialize_player_card_collection()
	# Clear territory claims so all territories start unclaimed (multiplayer uses Net sync)
	var tcs_path: String = "/root/" + "Territory" + "Claim" + "State"
	var tcs: Node = get_node_or_null(tcs_path)
	if tcs and tcs.has_method("clear_all"):
		tcs.clear_all()
	
	# Build player list from PlayerDataSync.player_names and PlayerDataSync.player_races
	var my_id := multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
	
	for pid in PlayerDataSync.player_races.keys():
		var p := {
			"id": int(pid),
			"name": String(PlayerDataSync.player_names.get(pid, "Player")),
			"race": String(PlayerDataSync.player_races[pid]),
			"roll": 0,
			"is_local": int(pid) == my_id,
			"is_bot": PlayerDataSync.is_bot_id(int(pid))
		}
		game_players.append(p)

func get_race_texture_path(race: String) -> String:
	match race:
		"Elf":
			return "res://pictures/elf_girl_1/eg1_south.png"
		"Orc":
			return "res://pictures/orc_boy_1/ob1_south.png"
		"Fairy":
			return "res://pictures/fairy_girl_1/fg1_south.png"
		"Infernal":
			return "res://pictures/infernal_boy_1/ib1_south.png"
	return ""

func get_race_color(race: String) -> Color:
	match race:
		"Elf":
			return Color(1, 0.9, 0.2, 1)  # Yellow
		"Orc":
			return Color(0.2, 0.8, 0.2, 1)  # Green
		"Fairy":
			return Color(0.7, 0.3, 0.9, 1)  # Purple
		"Infernal":
			return Color(0.9, 0.2, 0.2, 1)  # Red
	return Color.WHITE

func get_region_color(region_id: int) -> Color:
	match region_id:
		3:
			return Color(1.0, 0.55, 0.15, 1.0)   # Orange
		5:
			return Color(0.25, 0.5, 1.0, 1.0)     # Blue
		6:
			return Color(1.0, 1.0, 1.0, 1.0)      # White
		4:
			return Color(0.6, 0.6, 0.6, 1.0)      # Gray
		2:
			return Color(0.2, 0.78, 0.7, 1.0)     # Teal
		1:
			return Color(0.82, 0.7, 0.45, 1.0)    # Tan / Beige
	return Color(0.8, 0.8, 0.8, 1.0)

func stop_main_music() -> void:
	if main_music and main_music.playing:
		main_music.stop()

func play_main_music() -> void:
	if main_music and not main_music.playing:
		main_music.play()

func stop_battle_music() -> void:
	if battle_music and battle_music.playing:
		battle_music.stop()

func play_battle_music() -> void:
	if battle_music and not battle_music.playing:
		battle_music.play()

func switch_to_battle_music() -> void:
	stop_main_music()
	play_battle_music()

func switch_to_main_music() -> void:
	stop_battle_music()
	play_main_music()

func play_blip_select() -> void:
	if not ui_sfx or not ui_sfx.stream:
		return
	# Restart so rapid presses still feel responsive.
	if ui_sfx.playing:
		ui_sfx.stop()
	ui_sfx.play()

func _on_player_won(player_id: int) -> void:
	game_victor_id = player_id
	# End any remaining battle sequence immediately; the game already has a winner.
	pending_territory_battle_ids.clear()
	territory_pending_attackers.clear()

func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		_connect_button_sfx(node)

func _hook_buttons_on_current_scene() -> void:
	var scene := get_tree().current_scene
	if scene:
		_hook_buttons_recursive(scene)

func _hook_buttons_recursive(root: Node) -> void:
	if root is BaseButton:
		_connect_button_sfx(root)
	for child in root.get_children():
		_hook_buttons_recursive(child)

func _connect_button_sfx(button: BaseButton) -> void:
	var cb := Callable(self, "play_blip_select")
	if not button.pressed.is_connected(cb):
		button.pressed.connect(cb)

func _setup_audio_buses() -> void:
	# Check if Music bus exists, if not create it
	var music_bus_idx = AudioServer.get_bus_index("Music")
	if music_bus_idx == -1:
		AudioServer.add_bus()
		var new_bus_idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(new_bus_idx, "Music")
		AudioServer.set_bus_send(new_bus_idx, "Master")
		print("Created Music audio bus")
	
	# Check if SFX bus exists, if not create it
	var sfx_bus_idx = AudioServer.get_bus_index("SFX")
	if sfx_bus_idx == -1:
		AudioServer.add_bus()
		var new_bus_idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(new_bus_idx, "SFX")
		AudioServer.set_bus_send(new_bus_idx, "Master")
		print("Created SFX audio bus")
	
	# Check if UI bus exists, if not create it
	var ui_bus_idx = AudioServer.get_bus_index("UI")
	if ui_bus_idx == -1:
		AudioServer.add_bus()
		var new_bus_idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(new_bus_idx, "UI")
		AudioServer.set_bus_send(new_bus_idx, "Master")
		print("Created UI audio bus")

## Called by Net via RPC start_territory_battle
func enter_territory_battle(territory_id: int, attacker_id: int, defender_id: int) -> void:
	pending_territory_battle_attacker_id = attacker_id
	pending_territory_battle_defender_id = defender_id
	print("[App] Entering Territory Battle: ", territory_id)
	
	if not BattleStateManager:
		return
		
	var tid_str: String = str(territory_id)
	BattleStateManager.set_current_territory(tid_str)
	BattleStateManager.clear_local_slots(tid_str)
	
	var my_id: int = multiplayer.get_unique_id() if (is_multiplayer and multiplayer.has_multiplayer_peer()) else int(_get_local_player_id_for_single_player())
	
	# Determine if I am participating and who my opponent is (for current_battle_metadata / opponent sprite)
	var is_attacker = (my_id == attacker_id)
	var is_defender = (my_id == defender_id)
	var opponent_id: int = defender_id if is_attacker else (attacker_id if is_defender else -1)
	var opponent_name := "Unknown"
	var opponent_race := "Fairy"
	for p in game_players:
		if int(p.get("id", -1)) == opponent_id:
			opponent_name = p.get("name", "Unknown")
			opponent_race = p.get("race", "Fairy")
			break
	current_battle_metadata = {
		"battle_index": territory_id,
		"opponent_id": opponent_id,
		"opponent_name": opponent_name,
		"opponent_race": opponent_race
	}
	
	is_battle_spectator = not is_attacker and not is_defender

	if is_attacker:
		print("[App] I am the ATTACKER. Loading attacking slots.")
		var atts: Dictionary = BattleStateManager._get_state(tid_str).get("attacking_slots", {})
		for idx in atts:
			var c: Dictionary = atts[idx]
			BattleStateManager.set_local_slot(int(idx), c.get("path", ""), int(c.get("frame", 0)), tid_str)
		go("res://scenes/card_battle.tscn")
			
	elif is_defender:
		print("[App] I am the DEFENDER. Loading defending slots.")
		var defs: Dictionary = BattleStateManager.get_defending_slots(tid_str)
		for idx in defs:
			var c: Dictionary = defs[idx]
			BattleStateManager.set_local_slot(int(idx), c.get("path", ""), int(c.get("frame", 0)), tid_str)
		go("res://scenes/card_battle.tscn")
			
	else:
		print("[App] I am a SPECTATOR. Entering battle scene as spectator.")
		go("res://scenes/card_battle.tscn")


func _get_local_player_id_for_single_player() -> int:
	for p in game_players:
		if p.get("is_local", false):
			return int(p.get("id", 1))
	return 1

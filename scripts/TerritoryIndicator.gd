class_name TerritoryIndicator
extends Control

const DEBUG_LOGS := true

## TerritoryIndicator — Clickable sprite-based territory on the map.
## Created programmatically by TerritoryManager at the center of each TerritoryNode.
## Handles clicking, claim visuals (race-colored sprite), and selection glow.

signal territory_selected(territory_id: int)
signal card_placed(territory_id: int, player_id: int)
signal defending_cards_preview_requested(territory_id: int)

const INDICATOR_TEXTURE_PATH := "res://assets/territory_indicator.pxo"
const INDICATOR_SIZE := Vector2(100, 100)

const RACE_FRAME_BASE: Dictionary = {
	"elf": 1,
	"orc": 4,
	"fairy": 7,
	"infernal": 10,
}

var territory_id: int = -1
var region_id: int = -1

var territory_data: Territory = null
var is_selected: bool = false

var _texture_rect: TextureRect = null
var _sprite_frames: SpriteFrames = null
var _glow_alpha: float = 0.0
var _hover_timer: Timer = null
const HOVER_PREVIEW_DELAY_SEC := 1.0

# ---------- CONTEST BLINK ----------
var _contest_blink_active: bool = false
var _contest_blink_show_attacker: bool = false
var _contest_blink_timer: float = 0.0
var _contest_attacker_race: String = ""
var _contest_attacker_card_count: int = 0
const CONTEST_BLINK_INTERVAL := 0.5


func _ready() -> void:
	custom_minimum_size = INDICATOR_SIZE
	size = INDICATOR_SIZE
	mouse_filter = MOUSE_FILTER_STOP

	_load_sprite_frames()
	_setup_texture_rect()
	_setup_hover_timer()
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

	if territory_id != -1 and not territory_data:
		territory_data = Territory.new(territory_id, region_id if region_id != -1 else 1, null, [])

	_update_sprite_frame()


func _load_sprite_frames() -> void:
	if ResourceLoader.exists(INDICATOR_TEXTURE_PATH):
		var res = load(INDICATOR_TEXTURE_PATH)
		if res is SpriteFrames:
			_sprite_frames = res as SpriteFrames


func _setup_texture_rect() -> void:
	_texture_rect = TextureRect.new()
	_texture_rect.name = "Sprite"
	_texture_rect.set_anchors_preset(PRESET_FULL_RECT)
	_texture_rect.expand_mode = TextureRect.EXPAND_FIT_HEIGHT_PROPORTIONAL
	_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_texture_rect.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_texture_rect)


func _setup_hover_timer() -> void:
	_hover_timer = Timer.new()
	_hover_timer.name = "HoverPreviewTimer"
	_hover_timer.one_shot = true
	_hover_timer.wait_time = HOVER_PREVIEW_DELAY_SEC
	_hover_timer.timeout.connect(_on_hover_timer_timeout)
	add_child(_hover_timer)


func _draw() -> void:
	if _glow_alpha > 0.01:
		var center := INDICATOR_SIZE / 2.0
		var radius := INDICATOR_SIZE.x / 2.0 + 6.0
		draw_circle(center, radius, Color(0.0, 1.0, 1.0, _glow_alpha))


func _update_sprite_frame() -> void:
	if not _texture_rect or not _sprite_frames:
		return
	if not _sprite_frames.has_animation("default"):
		return
	var frame_idx := _get_frame_index()
	var count := _sprite_frames.get_frame_count("default")
	frame_idx = clampi(frame_idx, 0, maxi(0, count - 1))
	_texture_rect.texture = _sprite_frames.get_frame_texture("default", frame_idx)


func _get_frame_index() -> int:
	var tcs: Node = get_node_or_null("/root/TerritoryClaimState")
	if not tcs or not tcs.has_method("is_claimed"):
		return 0
	if not tcs.call("is_claimed", territory_id):
		return 0

	var owner_id: Variant = tcs.call("get_owner_id", territory_id)
	if owner_id == null:
		return 0

	var race := ""
	for p in App.game_players:
		if p.get("id", -999) == owner_id:
			race = str(p.get("race", "")).to_lower().strip_edges()
			break
	if race.is_empty() or not RACE_FRAME_BASE.has(race):
		return 0

	var card_count := _count_defending_cards(tcs)
	if card_count <= 0:
		return 0

	return RACE_FRAME_BASE[race] + clampi(card_count, 1, 3) - 1


func _count_defending_cards(tcs: Node) -> int:
	# Prefer TerritoryClaimState (synced across peers) for accurate cross-player display
	if tcs and tcs.has_method("get_cards"):
		var cards: Array = tcs.call("get_cards", territory_id)
		var count := 0
		for c in cards:
			if c != null:
				count += 1
		if count > 0:
			return count
	# Fall back to BattleStateManager for real-time local updates (during card placement)
	if BattleStateManager:
		var slots: Dictionary = BattleStateManager.get_defending_slots(str(territory_id))
		if slots.size() > 0:
			return slots.size()
	return 0


# ---------- HOVER PREVIEW ----------

func _on_mouse_entered() -> void:
	if _hover_timer:
		_hover_timer.start()


func _on_mouse_exited() -> void:
	if _hover_timer and _hover_timer.time_left > 0:
		_hover_timer.stop()


func _on_hover_timer_timeout() -> void:
	# Don't open hover preview during resource collection / minigame phase.
	if PhaseController and PhaseController.map_sub_phase == PhaseController.MapSubPhase.RESOURCE_COLLECTION:
		return
	if not _is_claimed_by_local_player():
		return
	defending_cards_preview_requested.emit(territory_id)


func _is_claimed_by_local_player() -> bool:
	var tcs: Node = get_node_or_null("/root/TerritoryClaimState")
	if not tcs or not tcs.has_method("is_claimed") or not tcs.call("is_claimed", territory_id):
		return false
	var owner_id: Variant = tcs.call("get_owner_id", territory_id)
	if owner_id == null:
		return false
	var local_id: Variant = null
	for p in App.game_players:
		if p.get("is_local", false):
			local_id = p.get("id", -999)
			break
	return local_id != null and int(owner_id) == int(local_id)


# ---------- INPUT ----------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			if territory_data:
				if DEBUG_LOGS: print("[TerritoryIndicator] Clicked territory_id=%d  region_id=%d  position=%s" % [territory_id, get_region_id(), global_position])
				territory_selected.emit(territory_data.territory_id)


# ---------- PUBLIC API ----------

func initialize(territory: Territory) -> void:
	territory_data = territory
	if territory:
		if territory_id == -1:
			territory_id = territory.territory_id
		if region_id == -1:
			region_id = territory.region_id


func get_territory_id() -> int:
	if territory_data:
		return territory_data.territory_id
	return territory_id


func get_region_id() -> int:
	if territory_data:
		return territory_data.region_id
	return region_id


func is_claimed() -> bool:
	if territory_data:
		return territory_data.is_claimed()
	return false


func is_contested() -> bool:
	if territory_data:
		return territory_data.is_contested()
	return false


func show_selection_glow() -> void:
	is_selected = true
	var tween := create_tween()
	tween.tween_method(_set_glow_alpha, _glow_alpha, 0.35, 0.2)


func deselect() -> void:
	is_selected = false
	var tween := create_tween()
	tween.tween_method(_set_glow_alpha, _glow_alpha, 0.0, 0.2)


func _set_glow_alpha(value: float) -> void:
	_glow_alpha = value
	queue_redraw()


func update_claimed_visual() -> void:
	_update_sprite_frame()


func notify_card_placed(player_id: int) -> void:
	if territory_data:
		card_placed.emit(territory_data.territory_id, player_id)


# ---------- CONTEST BLINK API ----------

func start_contest_blink(attacker_race: String, attacker_card_count: int) -> void:
	_contest_attacker_race = attacker_race.to_lower()
	_contest_attacker_card_count = attacker_card_count
	_contest_blink_timer = 0.0
	_contest_blink_show_attacker = false
	_contest_blink_active = true


func stop_contest_blink() -> void:
	_contest_blink_active = false
	_contest_blink_show_attacker = false
	_update_sprite_frame()  # Reset to owner view


func is_contest_blinking() -> bool:
	return _contest_blink_active


func _process(delta: float) -> void:
	if not _contest_blink_active:
		return
	_contest_blink_timer += delta
	if _contest_blink_timer >= CONTEST_BLINK_INTERVAL:
		_contest_blink_timer -= CONTEST_BLINK_INTERVAL
		_contest_blink_show_attacker = not _contest_blink_show_attacker
		_apply_contest_blink_frame()


func _apply_contest_blink_frame() -> void:
	if not _texture_rect or not _sprite_frames:
		return
	if not _sprite_frames.has_animation("default"):
		return
	var frame_idx: int
	if _contest_blink_show_attacker:
		frame_idx = _get_attacker_frame_index()
	else:
		frame_idx = _get_frame_index()
	var count := _sprite_frames.get_frame_count("default")
	frame_idx = clampi(frame_idx, 0, maxi(0, count - 1))
	_texture_rect.texture = _sprite_frames.get_frame_texture("default", frame_idx)


func _get_attacker_frame_index() -> int:
	if _contest_attacker_race.is_empty() or not RACE_FRAME_BASE.has(_contest_attacker_race):
		return 0
	if _contest_attacker_card_count <= 0:
		return 0
	return RACE_FRAME_BASE[_contest_attacker_race] + clampi(_contest_attacker_card_count, 1, 3) - 1

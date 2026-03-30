extends RefCounted

## BotBattleBehavior
## Bots do not move cards during battle; this script intentionally does nothing.

func on_battle_started(_bot_player_id: int) -> void:
	# Intentionally no-op.
	pass

# Clover and Clobber (game)

## Godot MCP (Cursor)

This repo includes Cursor MCP config at `.cursor/mcp.json`. It expects:

- **Node** on your PATH
- **godot-mcp** built at `~/godot-mcp/build/index.js` (adjust `args` if yours differs)
- **`GODOT_PROJECT_PATH`** = (`path/to/godot`)

Enable the Godot MCP server in **Cursor → Settings → MCP**, then use your MCP client’s “run project” / Godot actions to start the game from the editor integration.

To run without MCP: open the folder in **Godot 4** and press Play, or use the Godot binary with `--path` pointing at this directory.

## VS-AI bot difficulty

In **single-player** (race select → start), all three AI opponents use `App.single_player_bot_difficulty` (default **3**, range **0–5**). Change it in code or from another script before `setup_single_player_game()` if you want a different default.

Multiplayer bot levels are still set from the **host lobby** sliders (`PlayerDataSync`).

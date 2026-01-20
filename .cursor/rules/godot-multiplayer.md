# Godot 4.5.1 Multiplayer Rules (Clover & Clobber demo)

- Engine: Godot 4.5.1, language: GDScript.
- Networking: ENetMultiplayerPeer with host authoritative server.
- Use Godot high-level multiplayer: @rpc annotations, multiplayer.is_server(), get_remote_sender_id().
- Reliable RPC for gameplay actions; unreliable only for cosmetic/hover.
- Use MultiplayerSpawner for replicating spawned Player nodes.
- Keep node paths stable between peers; avoid referencing editor-only node names that might differ.
- Prefer small, readable scripts with comments. No overengineering.

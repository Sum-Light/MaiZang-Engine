# Architecture

## Direction

Use a modern, data-driven Godot architecture rather than a literal line-by-line port of the GBA C engine.

The original project should be treated as authoritative source data and behavioral reference. Godot should own the runtime architecture, scene graph, UI, input, save system, and rendering.

## Layering

1. Source import layer
   - Reads `pokeemerald-expansion` files.
   - Converts GBA-specific formats into stable intermediate data.
   - Never mutates the source project unless explicitly requested.

2. Generated data layer
   - Stores normalized JSON, Godot Resources, textures, TileSets, and import manifests.
   - Should be reproducible from source files.

3. Runtime domain layer
   - Owns game rules: map state, flags, vars, party, Pokemon data, encounters, battles, inventory, and save data.
   - Should avoid depending directly on scene-node layout.

4. Presentation layer
   - Godot scenes, UI controls, TileMapLayer rendering, animations, audio, and camera.
   - Should consume runtime state through clear APIs.

5. Tooling and verification layer
   - Import validators, unsupported-script reports, asset coverage reports, and smoke tests.

## Core Modules

- `GameState`: flags, vars, player profile, party, inventory, story state.
- `DataRegistry`: read-only access to generated Pokemon, moves, items, maps, tilesets, trainers, and encounters.
- `MapLoader`: builds Godot map scenes from generated map data.
- `GridMover`: shared grid movement for player and NPCs.
- `EventManager`: dispatches map events, warps, signs, object interaction, and coordinate triggers.
- `ScriptVM`: interprets converted event scripts.
- `BattleEngine`: deterministic battle rules separate from battle UI.
- `SaveService`: serializes runtime state.
- `ImportReport`: records missing assets, unsupported opcodes, broken links, and conversion warnings.

## First Vertical Slice

The first playable milestone should load `LittlerootTown`, render its layout, spawn the player and NPCs, support grid movement, run one simple NPC dialogue, and handle at least one warp placeholder.

This proves the import pipeline, map runtime, event dispatch, and basic presentation pipeline before the project expands into battle systems.

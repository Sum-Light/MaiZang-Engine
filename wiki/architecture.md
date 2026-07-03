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
- `MapRuntime`: current map query service for bounds, collision, elevation, metatile ids, metatile behavior, and layer type.
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

## Current Scaffold

- `GameState` stores current map id, player grid position, flags, and vars.
- `DataRegistry` stores first-slice constants for LittlerootTown and loads generated map/tileset JSON when they exist.
- `MapRuntime` configures the current generated map and exposes simple passability and metatile queries.
- `MapRuntime` indexes generated object events, BG/sign events, and warp events; visible object-event cells are occupied for first-pass movement.
- `MapRuntime.get_interaction_target` resolves the player's faced object/sign target, or a warp placeholder from the current cell.
- `GridMover` provides tweened tile movement.
- `PlayerController` reads directional input, tracks facing direction, moves one tile at a time after checking `MapRuntime.can_enter_cell`, and emits interaction requests on `ui_accept`.
- `EventManager` currently emits debug dialogue lines for object, BG/sign, and warp interaction placeholders. It should later call `ScriptVM` after event scripts and text are converted.
- `DebugMapPlane` draws the first generated `block_ids` metatile grid from a palette-baked RGBA metatile atlas, with the old color blocks as fallback.
- `ObjectEventSpawner` draws generated object events as simple placeholders until overworld sprite import is ready.
- `Main` connects the debug world, player, camera, HUD status label, and debug dialogue panel, and shows whether map data came from generated JSON or fallback constants.

## Generated Map Runtime Contract

- First-slice generated map JSON is loaded through `DataRegistry`.
- First-slice generated tileset JSON is loaded through `DataRegistry`.
- `block_ids` contains unpacked 10-bit metatile ids for simple render previews.
- `map_grid.raw`, `map_grid.collision`, and `map_grid.elevation` preserve the original 16-bit map-grid data split into runtime-friendly layers.
- First-pass movement uses generated `map_grid.collision`: cells with collision `0` are enterable and nonzero or out-of-bounds cells are blocked.
- `MapRuntime` also indexes generated metatile attributes so later rules can inspect behavior and layer type without reparsing tileset JSON in presentation scripts.
- Generated `events.object_events` are preserved in map JSON and indexed by `MapRuntime`; visible events block their current grid cell before event scripts or sprite imports are implemented.
- Generated `events.bg_events` and `events.warp_events` are preserved in map JSON and indexed by `MapRuntime` for the first interaction/warp placeholder path.
- Generated metatile atlases use metatile id as atlas index, so map `block_ids` can render directly during the first slice.
- Palette handling belongs to the import layer. Godot runtime should consume normal RGBA textures and metadata, not GBA palette slots.
- Real TileMapLayer rendering should later consume the generated atlas/metadata instead of the current debug Node2D renderer.

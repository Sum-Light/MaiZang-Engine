# Project Context

## Goal

Port the `pokeemerald-expansion` GBA ROM hack base into a modern Godot 4.7 stable project.

The port should be data-driven: preserve source data and assets where practical, convert them into Godot-friendly formats, and rebuild the runtime systems in Godot instead of trying to compile the original GBA engine into Godot.

## Local Paths

- Godot target project: `C:\Users\YbbNa\OneDrive\Documents\pokeemerald-godot`
- Source project: `C:\Users\YbbNa\OneDrive\Project-Azoth\pokeemerald-expansion-master\pokeemerald-expansion-master`
- Project skill: `C:\Users\YbbNa\.codex\skills\pokeemerald-godot-port`

## Current Godot Project State

- Godot project now has a minimal runtime scaffold.
- `project.godot` targets Godot 4.7 features and mobile rendering.
- `project.godot` sets `res://scenes/main.tscn` as the main scene.
- Autoloads are configured for `GameState`, `DataRegistry`, `MapRuntime`, `ScriptVM`, and `EventManager`.
- `DataRegistry` now loads the first generated map at `res://data/generated/maps/littleroot_town.json` when present.
- `DataRegistry` now loads the first generated tileset metadata at `res://data/generated/tilesets/littleroot_town.json` when present.
- `DataRegistry` now loads the first generated event script data at `res://data/generated/scripts/littleroot_town.json` when present.
- `MapRuntime` now configures the first generated map and exposes bounds, collision, elevation, metatile id, behavior, and layer-type lookups.
- `MapRuntime` now indexes first-slice object events, BG/sign events, and warp events.
- `MapRuntime` treats visible object-event cells as occupied and can resolve the player's current interaction target from grid position plus facing direction.
- `MapRuntime` now indexes first-slice coordinate events and resolves step-triggered coord event scripts by x/y/elevation plus source var/flag trigger state.
- `MapRuntime` can apply `ScriptVM` movement-effect results to in-memory object-event positions and `GameState.player_grid_position`, then rebuild object occupancy and notify the main scene to refresh placeholders/player position.
- `scenes/main.tscn` displays a 20x20 LittlerootTown debug map from generated metatile ids and a palette-baked metatile atlas, visible object-event placeholders, plus a movable player placeholder that is blocked by generated map-grid collision and object-event occupancy.
- `scenes/main.tscn` includes a debug dialogue panel driven by `EventManager`; object/sign interactions and first-pass coordinate triggers now execute the first generated script slice through `ScriptVM` and show emitted dialogue text, while warps remain placeholders.
- Player movement currently uses Godot's default `ui_up`, `ui_down`, `ui_left`, and `ui_right` actions.
- Player interaction currently uses Godot's default `ui_accept` action.
- Godot validation uses `C:\Users\YbbNa\Downloads\Godot_v4.7-stable_win64\Godot_v4.7-stable_win64_console.exe`.
- Validated Godot version: `4.7.stable.official.5b4e0cb0f`.
- The project directory was not a git repository during the initial inspection.
- The project directory is now a standalone git repository initialized on 2026-07-03.
- Local git line-ending config was set to `core.autocrlf=false` and `core.eol=lf`, matching the existing `.gitattributes` LF policy.
- The project should be maintained with focused commits after completed file changes.

## Source Project Facts

- Source is `pokeemerald-expansion`, built on the `pokeemerald` decompilation.
- It is a ROM hack base, not a standalone playable game by itself.
- Approximate file count from `rg --files`: 29,969.
- Major directories include `data`, `graphics`, `include`, `src`, `sound`, `tools`, and `docs`.
- The source project is inside a larger git worktree rooted at `C:\Users\YbbNa\OneDrive\Project-Azoth`; git status from the source path includes unrelated parent-tree noise.
- `tools/importer/source_probe.py` currently verifies the source path and first-slice map inputs.
- `tools/importer/export_map.py` exports `LittlerootTown` into generated Godot JSON.
- `tools/importer/export_tilesets.py` exports the `LittlerootTown` primary/secondary tileset pair into Godot-friendly metadata and an RGBA metatile atlas.
- `tools/importer/export_event_scripts.py` exports `LittlerootTown` map script labels, instruction streams, movement labels, local text labels, first-pass `msgbox` previews, and source behavior trace notes.
- Generated first-slice map data lives at `data/generated/maps/littleroot_town.json`.
- Generated first-slice tileset metadata lives at `data/generated/tilesets/littleroot_town.json`.
- Generated first-slice metatile atlas lives at `assets/generated/tilesets/littleroot_town_metatiles.png`.
- Generated first-slice event script data lives at `data/generated/scripts/littleroot_town.json`.
- Generated import manifest lives at `data/generated/import_manifest.json`.
- Latest source probe for `LittlerootTown` found 939 map JSON files, 887 map script files, 5 primary tilesets, 127 secondary tilesets, and no missing first-slice files.
- Latest map export for `LittlerootTown` decoded 400 map-grid entries into 63 unique metatile ids.
- Latest tileset export for `LittlerootTown` uses `gTileset_General` and `gTileset_Petalburg`, writes a 656-metatile RGBA atlas, reports 63 used metatile ids, records 8 fully covered source tile notes, and has 0 visible warnings.
- Latest event script export for `LittlerootTown` found 130 labels, 78 scripts, 34 movement labels, 18 local text labels, and 0 orphan instructions.
- Latest event script export records first-pass preview support for direct `msgbox`/`message` text only; full opcode behavior remains a future `ScriptVM` task grounded in source C traces and referenced resources.
- `ScriptVM` now executes the first synchronous dialogue and movement-effect subset for generated scripts: `msgbox`, `message`, `lock`, `lockall`, `release`, `releaseall`, `faceplayer`, `waitmessage`, `waitbuttonpress`, `closemessage`, `goto`, `call`, `return`, `end`, basic `*_if_*` branches, `setflag`, `clearflag`, `setvar`, `applymovement`, `applymovementat`, `waitmovement`, and `waitmovementat`.
- `ScriptVM` expands `MSGBOX_NPC`, `MSGBOX_SIGN`, and `MSGBOX_DEFAULT` according to the source standard scripts. Current waits and locks are recorded as execution effects; real asynchronous UI, object freezing, and player/object facing animation remain future work.
- `ScriptVM` expands generated movement labels into result `movements` entries with target local id, structured steps, net tile delta, final facing, and unsupported-step reporting. Real dispatch now fast-forwards those net deltas into runtime map/player state; scene-node animation, object task queues, source collision timing, and real wait blocking remain future work.
- `EventManager` applies `ScriptVM` movement effects only during real interaction dispatch, not during `get_script_preview`, so previews stay read-only.
- `LittlerootTown` generated collision currently has 268 passable cells and 132 blocked cells.
- `LittlerootTown` has 8 generated object events; the first runtime pass shows them as placeholders and blocks movement into their occupied cells.
- `LittlerootTown` has 4 generated BG/sign events and 3 generated warp events indexed by `MapRuntime`.
- `LittlerootTown` has 9 generated coordinate events indexed by `MapRuntime`; the first runtime pass dispatches normal trigger scripts after player tile movement, including the NeedPokemon grass-blocking trigger.
- Porymap (`https://github.com/huderlem/porymap`) is a useful source-format and editor-behavior reference, but the Godot port should still use its own runtime architecture.

## Known Source Formats

- Map metadata: `data/maps/*/map.json`
- Map scripts: `data/maps/*/scripts.inc`
- Layout metadata: `data/layouts/layouts.json`
- Layout block data: `data/layouts/*/map.bin`
- Layout border data: `data/layouts/*/border.bin`
- Tilesets: `data/tilesets/primary|secondary/*`
- Tileset images: `tiles.png`
- Tileset metatiles: `metatiles.bin`
- Tileset behavior data: `metatile_attributes.bin`
- Palettes: `palettes/*.pal`
- Pokemon data: `src/data/pokemon/species_info.h`
- Move data: `src/data/moves_info.h`
- Item data: `src/data/items.h`
- Wild encounters: `src/data/wild_encounters.json`
- Trainers: `src/data/trainers.party`

## Important Risk

Text currently appears garbled when read directly in the shell. Do not hand-fix strings. Build a `charmap.txt`-driven text extraction and decoding flow before treating text data as final.

Avoid using PowerShell for script-like file rewriting or text conversion unless necessary. If PowerShell is used, explicitly consider encoding and verify the result, especially for Chinese text.

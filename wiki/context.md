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
- Autoloads are configured for `GameState` and `DataRegistry`.
- `DataRegistry` now loads the first generated map at `res://data/generated/maps/littleroot_town.json` when present.
- `scenes/main.tscn` displays a 20x20 LittlerootTown debug grid from generated metatile ids and a movable player placeholder.
- Player movement currently uses Godot's default `ui_up`, `ui_down`, `ui_left`, and `ui_right` actions.
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
- Generated first-slice map data lives at `data/generated/maps/littleroot_town.json`.
- Generated import manifest lives at `data/generated/import_manifest.json`.
- Latest source probe for `LittlerootTown` found 939 map JSON files, 887 map script files, 5 primary tilesets, 127 secondary tilesets, and no missing first-slice files.
- Latest map export for `LittlerootTown` decoded 400 map-grid entries into 63 unique metatile ids.

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

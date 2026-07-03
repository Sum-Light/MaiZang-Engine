# Session Log

## 2026-07-03

- Inspected the empty Godot project at `C:\Users\YbbNa\OneDrive\Documents\pokeemerald-godot`.
- Inspected the source `pokeemerald-expansion` project and identified major source-data directories.
- Established the migration direction: modern data-driven Godot rebuild, not direct C engine embedding.
- Created this project wiki and started a project-specific Codex skill.
- Created and validated the `pokeemerald-godot-port` Codex skill at `C:\Users\YbbNa\.codex\skills\pokeemerald-godot-port`.
- Installed `PyYAML 6.0.1` into the local Python 3.7 environment so the skill validation script can run.
- Added project rules to minimize PowerShell file rewriting, protect Chinese/text encoding, and commit completed project changes.
- Initialized the Godot project as a standalone git repository and set local LF line-ending config.
- Added the first Godot runtime scaffold: main scene, autoloads, placeholder LittlerootTown debug grid, camera, HUD label, and tile-based player movement.
- Added `tools/importer/source_probe.py` plus `tools/import_config.example.json` for read-only source probing.
- Verified the source probe with `LittlerootTown`: no missing first-slice files; source contains 939 map JSON files and 887 map script files.
- Could not run a Godot scene-load check because `godot`/`godot4` were not found in PATH or common install locations.
- Located and validated Godot 4.7 at `C:\Users\YbbNa\Downloads\Godot_v4.7-stable_win64\Godot_v4.7-stable_win64_console.exe`; version is `4.7.stable.official.5b4e0cb0f`.
- Added `tools/importer/export_map.py` to export `LittlerootTown` from source `map.json`, `layouts.json`, `map.bin`, and `border.bin`.
- Generated `data/generated/maps/littleroot_town.json` and `data/generated/import_manifest.json`.
- Decoded `map.bin` as little-endian u16 map-grid entries with metatile id, collision, and elevation layers.
- Updated `DataRegistry`, `Main`, and `DebugMapPlane` so the main scene reads generated map JSON and colors the debug grid from generated metatile ids.
- Verified Python import tools and Godot headless main-scene startup with the generated first-slice map data.
- Added `tools/importer/export_tilesets.py` to bake the `LittlerootTown` `gTileset_General` + `gTileset_Petalburg` pair into an RGBA metatile atlas and generated tileset JSON.
- Decided that GBA palettes are import-time inputs only; Godot runtime should consume palette-baked images rather than a runtime palette system.
- Used Porymap as a source-format reference for map/tileset/palette semantics while keeping the Godot runtime architecture independent.
- Generated `assets/generated/tilesets/littleroot_town_metatiles.png` and `data/generated/tilesets/littleroot_town.json`.
- Updated `DataRegistry`, `Main`, and `DebugMapPlane` so the main scene renders `LittlerootTown` from the generated atlas with color-block fallback.
- Verified Python import tools, tileset export with 0 visible warnings, and Godot 4.7 headless main-scene startup.

## 2026-07-04

- Added `MapRuntime` as a current-map query autoload for bounds, collision, elevation, metatile ids, behavior, and layer type.
- Updated `PlayerController` so grid movement is blocked by generated map-grid collision and map bounds.
- Updated `Main` to configure `MapRuntime` from generated first-slice map and tileset data and to show the last blocked movement during debug play.
- Added `tools/godot_smoke/map_runtime_smoke.gd` to validate first-slice map runtime queries.
- Verified Godot 4.7 headless main-scene startup and the `MapRuntime` smoke script.

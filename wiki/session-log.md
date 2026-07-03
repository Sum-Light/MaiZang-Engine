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
- Indexed generated `object_events` in `MapRuntime` and made visible object-event cells block movement.
- Added `ObjectEventSpawner` and placeholder object-event drawing for the 8 LittlerootTown object events.
- Updated the `MapRuntime` smoke script to verify object-event count and occupied-cell blocking.
- Used Porymap's event model as a reference point for object, BG/sign, and warp events while keeping the Godot runtime architecture independent.
- Extended `MapRuntime` to index generated BG/sign events and warp events, and to resolve interaction targets from player position plus facing direction.
- Added `EventManager` as a debug event dispatcher and connected `ui_accept` interaction to a HUD dialogue panel for object/sign/warp placeholders.
- Updated the `MapRuntime` smoke script to verify object, BG/sign, and warp interaction target lookup.
- Added the rule that event script and gameplay behavior must be traced from source C plus referenced resources before implementation, while GBA graphics hardware constraints stay import-time concerns.
- Added `tools/importer/export_event_scripts.py` to export `LittlerootTown` script labels, instruction streams, movement labels, local text labels, and first-pass dialogue preview data.
- Generated `data/generated/scripts/littleroot_town.json` with 130 labels, 78 scripts, 34 movement labels, 18 text labels, and 0 orphan instructions.
- Updated `DataRegistry` and `EventManager` so object/BG interactions can preview the first generated `msgbox`/`message` text when available.
- Added `tools/godot_smoke/event_manager_smoke.gd` to verify generated script preview lookup for a Twin NPC script and the town sign script.
- Traced the source `msgbox` macro, `gStdScripts`, `Std_MsgboxNPC`, `Std_MsgboxSign`, `Std_MsgboxDefault`, and relevant `src/scrcmd.c` commands before implementing the first VM slice.
- Added `ScriptVM` as an autoload with synchronous execution for the first dialogue subset, including source-derived `MSGBOX_NPC/SIGN/DEFAULT` expansion, basic flow control, simple flag/var operations, and unsupported-op reporting.
- Updated `EventManager` so object/BG interactions use `ScriptVM` when available and fall back to direct preview only if the VM is unavailable.
- Added `tools/godot_smoke/script_vm_smoke.gd` and expanded `event_manager_smoke.gd` to verify VM execution for the Twin NPC and LittlerootTown town sign scripts.
- Traced `ScrCmd_applymovement`, `ScrCmd_applymovementat`, `ScrCmd_waitmovement`, `ScrCmd_waitmovementat`, `src/script_movement.c`, and `asm/macros/movement.inc` before implementing the first movement command slice.
- Added first-pass `ScriptVM` support for `applymovement`, `applymovementat`, `waitmovement`, and `waitmovementat` as structured movement-effect results.
- Expanded `tools/godot_smoke/script_vm_smoke.gd` to verify `LittlerootTown_EventScript_NeedPokemonTriggerLeft`, including call/return flow, 2 dialogue messages, 4 movement effects, and 3 waitmovement effects.
- Extended `MapRuntime` to index object events by local id, apply `ScriptVM` movement-effect net deltas to runtime object/player positions, rebuild occupancy, and emit refresh signals.
- Updated `EventManager` to apply movement effects during real interaction dispatch while keeping `get_script_preview` read-only.
- Expanded `map_runtime_smoke.gd` and `event_manager_smoke.gd` to verify movement-effect application for `LittlerootTown_EventScript_NeedPokemonTriggerLeft`.
- Traced source coordinate-event handling in `field_control_avatar.c` and added first-pass Godot coord-event dispatch after player movement, including `VAR_LITTLEROOT_TOWN_STATE` gated LittlerootTown triggers.
- Traced source object-event script commands in `src/scrcmd.c`, `src/event_object_movement.c`, `src/overworld.c`, and `asm/macros/event.inc`.
- Added first-pass `ScriptVM` object effects for `setobjectxy`, `setobjectxyperm`, `setobjectmovementtype`, `addobject`, `removeobject`, `showobject`, and `hideobject` variants.
- Extended `MapRuntime` and `EventManager` so real dispatch applies object effects to runtime object position, template position, movement type metadata, visibility, add/remove, and hide flags while previews stay read-only.
- Expanded VM, map runtime, and event manager smoke tests to cover LittlerootTown Twin, Rival/Birch, and Mom object-effect scripts.
- Traced `ScrCmd_checkplayergender` and `MALE`/`FEMALE` constants, then added `GameState.player_gender` plus VM support for writing `VAR_RESULT`.
- Expanded `script_vm_smoke.gd` to verify LittlerootTown male/female sign text and Rival/Birch dex-upgrade object positions.

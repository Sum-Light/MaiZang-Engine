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
- `GameState` stores current map id, player gender, player name, player grid position, flags, and vars.
- `DataRegistry` now loads `data/generated/import_manifest.json` and can resolve generated map, tileset, script, and global text JSON while preserving the first-slice start-map API.
- `MapRuntime` now configures the first generated map and exposes bounds, collision, elevation, metatile id, behavior id, behavior name, and layer-type lookups.
- `MapRuntime` now indexes first-slice object events, BG/sign events, warp events, and coordinate events.
- `MapRuntime` treats visible object-event cells as occupied and can resolve the player's current interaction target from grid position plus facing direction.
- `MapRuntime` now indexes first-slice coordinate events and resolves step-triggered coord event scripts by x/y/elevation plus source var/flag trigger state.
- `MapRuntime` can apply `ScriptVM` movement-effect results to in-memory object-event positions and `GameState.player_grid_position`, then rebuild object occupancy and notify the main scene to refresh placeholders/player position.
- `MapRuntime` can apply first-pass `ScriptVM` object-effect results for object coordinates, template coordinates, movement type metadata, runtime visibility, add/remove, and source hide flags.
- `scenes/main.tscn` displays a 20x20 LittlerootTown debug map from generated metatile ids and a palette-baked metatile atlas, visible object-event placeholders, plus a movable player placeholder that is blocked by generated map-grid collision and object-event occupancy.
- `scenes/main.tscn` includes a debug dialogue panel driven by `EventManager`; object/sign interactions, first-pass coordinate triggers, and generated map warp events now execute through `ScriptVM`/`EventManager`, apply dispatch-time runtime effects, show emitted dialogue text, and can switch between generated maps.
- `EventManager` now emits source-traced `transition_sequence_requested` data before applying generated map transitions. Normal/silent transitions record lock, fade, load, reveal, destination exit-task selection, conditional destination door-exit steps, and unlock steps; door transitions also record freeze, door sound intent, 16-frame door open, 16-frame player step-in, hide-player, and 16-frame door close.
- `Main` configures deferred transition application and delegates sequence playback to `TransitionSequencePlayer`, which applies the generated map change at the sequence `load_map` step, drives the first-pass black fade overlay, locks player input, hides/shows the player, animates recorded player steps, plays generated door animation overlays when sequence data includes them, and updates the final player grid position after `Task_ExitDoor` step-out. Real sound playback, exact fade color selection, non-animated door/stair exit playback, and map-script chaining remain future work.
- Blocked front-cell door warp dispatch now only runs when the player is facing north, matching source `TryDoorWarp` behavior.
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
- `tools/importer/export_tilesets.py` parses `include/constants/metatile_behaviors.h` and writes behavior names into generated tileset metadata so runtime rules can compare source behavior names instead of hardcoded numeric ids.
- `tools/importer/export_tilesets.py` also parses `include/constants/metatile_labels.h` and `src/field_door.c` to bake supported used door animation strips from `graphics/door_anims/*.png` into normal RGBA frame atlases and generated `door_animations` metadata.
- `tools/importer/export_event_scripts.py` exports `LittlerootTown` map script labels, instruction streams, movement labels, local text labels, first-pass `msgbox` previews, and source behavior trace notes.
- `tools/importer/export_event_scripts.py` now validates local map-script text labels against source `charmap.txt`, preserving UTF-8 `display_text` plus source bytes, control codes, placeholders, terminator metadata, and warnings.
- `tools/importer/export_text.py` exports global `data/text/*.inc` labels into `data/generated/text/global_text.json`, preserving normal `.string` charmap metadata, `.braille` byte metadata, `brailleformat` headers, and `IS_FRLG` preprocessor branch decisions for the Emerald target.
- Generated map data currently exists for `LittlerootTown`, `LittlerootTown_BrendansHouse_1F`, and `LittlerootTown_MaysHouse_1F`.
- Generated tileset metadata and palette-baked metatile atlases currently exist for `LittlerootTown`, `LittlerootTown_BrendansHouse_1F`, and `LittlerootTown_MaysHouse_1F`.
- Generated tileset metadata now includes a `metatile_behaviors` name table plus per-metatile `attribute.behavior_name` values.
- Generated `LittlerootTown` tileset metadata now includes door animation metadata for `METATILE_Petalburg_Door_Littleroot` and `METATILE_Petalburg_Door_BirchsLab`, with generated RGBA atlases under `assets/generated/door_anims/`.
- Generated event script data currently exists for `LittlerootTown`, `LittlerootTown_BrendansHouse_1F`, and `LittlerootTown_MaysHouse_1F`.
- Generated global text data currently exists at `data/generated/text/global_text.json` and is indexed by the import manifest `texts` entry.
- Generated import manifest lives at `data/generated/import_manifest.json`.
- Latest source probe for `LittlerootTown` found 939 map JSON files, 887 map script files, 5 primary tilesets, 127 secondary tilesets, and no missing first-slice files.
- Latest map export for `LittlerootTown` decoded 400 map-grid entries into 63 unique metatile ids.
- Latest tileset export for `LittlerootTown` uses `gTileset_General` and `gTileset_Petalburg`, writes a 656-metatile RGBA atlas, reports 63 used metatile ids, records 8 fully covered source tile notes, exports 2 door animation atlases, and has 0 visible warnings.
- Latest event script export for `LittlerootTown` found 130 labels, 78 scripts, 34 movement labels, 18 local text labels, 0 charmap warnings, and 0 orphan instructions.
- Latest global text export found 37 source files, 3454 labels/text records, 3393 normal `.string` records, 61 `.braille` records, 0 charmap warnings, 0 braille warnings, 6 `IS_FRLG` preprocessor decisions, 0 preprocessor warnings, and 0 unsupported directives.
- Generated `LittlerootTown_BrendansHouse_1F` is 11x9 and has 26 scripts, 11 movement labels, 29 text labels, 0 charmap warnings, and 0 script orphan instructions.
- Generated `LittlerootTown_MaysHouse_1F` is 11x9 and has 31 scripts, 11 movement labels, 8 text labels, 0 charmap warnings, and 0 script orphan instructions.
- Latest event script export records first-pass preview support for direct `msgbox`/`message` text only; full opcode behavior remains a future `ScriptVM` task grounded in source C traces and referenced resources.
- `ScriptVM` now executes the first synchronous dialogue, movement-effect, object-effect, field-effect, UI-effect, special-effect, audio-effect, transition-effect, and player-effect subset for generated scripts: `msgbox`, `message`, `yesnobox`, `special`, `lock`, `lockall`, `release`, `releaseall`, `faceplayer`, `waitmessage`, `waitbuttonpress`, `closemessage`, `goto`, `call`, `return`, `end`, basic `*_if_*` branches, `setflag`, `clearflag`, `setvar`, `checkplayergender`, `applymovement`, `applymovementat`, `waitmovement`, `waitmovementat`, `setobjectxy`, `setobjectxyperm`, `setobjectmovementtype`, `addobject`, `addobjectat`, `removeobject`, `removeobjectat`, `showobject`, `showobjectat`, `hideobject`, `hideobjectat`, `delay`, `opendoor`, `closedoor`, `waitdooranim`, `waitstate`, `playse`, `playfanfare`, `waitfanfare`, `warp`, `warpsilent`, and `hideplayer`.
- `ScriptVM` expands `MSGBOX_NPC`, `MSGBOX_SIGN`, `MSGBOX_DEFAULT`, and `MSGBOX_YESNO` according to the source standard scripts. `MSGBOX_YESNO`/`yesnobox` records a UI effect with the source default menu position `21,9`, size `5x4`, default `YES`, `B = NO`, about 5 frames of input delay, and `VAR_RESULT` semantics. Without an injected UI/test choice it stops with `status = waiting_for_ui` and `VAR_RESULT = 0xFF` rather than inventing a player answer. Current waits, locks, and UI effects are recorded as execution results; real asynchronous UI, object freezing, and player/object facing animation remain future work.
- `ScriptVM` now source-traces the first string-placeholder `special` slice: `GetPlayerBigGuyGirlString` and `GetRivalSonDaughterString` write `STR_VAR_1` from `GameState.player_gender` using the source Chinese strings from `src/field_specials.c`, record `special_effects`, and let message execution expand `{PLAYER}`, `{KUN}`, `{RIVAL}`, `{STR_VAR_1}`, `{STR_VAR_2}`, and `{STR_VAR_3}` while preserving `unexpanded_text`, source placeholder ids, substitution metadata, and runtime string vars.
- `{PLAYER}` maps to source placeholder id `0x1` and reads `gSaveBlock2Ptr->playerName`; `{KUN}` maps to source placeholder id `0x5`, but both `gText_ExpandedPlaceholder_Kun` and `gText_ExpandedPlaceholder_Chan` are empty strings in the current Chinese source. The Godot `GameState.player_name` fallback `"玩家"` is only a debug/profile placeholder until the real new-game naming flow and preset-name selection are ported from `src/main_menu.c`/`src/oak_speech.c`.
- `{RIVAL}` maps to source placeholder id `0x6`. Because this source target has `IS_FRLG = 0`, it does not use a custom `gSaveBlock1Ptr->rivalName`; it expands to `gText_ExpandedPlaceholder_May` (`小遥`) for a male player and `gText_ExpandedPlaceholder_Brendan` (`小悠`) for a female player.
- `ScriptVM` now parses the first runtime text-control slice after placeholder expansion: `{COLOR ...}`, `{SHADOW ...}`, `{FONT_NORMAL}`, `{FONT_MALE}`, `{FONT_FEMALE}`, `{PAUSE n}`, and `{PAUSE_UNTIL_PRESS}` are removed from visible message `text` and preserved as `text_controls` metadata with source `EXT_CTRL_CODE_*` ids, source lengths, values, offsets, and wait intent.
- `ScriptVM` now expands the first battle/message dynamic text token `{B_PC_CREATOR_NAME}` from source `BattleStringExpandPlaceholders` id `0x27`, using `FLAG_SYS_PC_LANETTE` and the Emerald `IS_FRLG = 0` branch to choose `SOMEONES` or `LANETTES` PC creator text while preserving substitution `source` and `value_key` metadata. Broader battle text tokens remain future traced work.
- `DataRegistry` can load global generated text by category and return text records or `display_text` by source label. `ScriptVM` and `EventManager` now resolve message text from local generated map-script labels first, then global text labels through `DataRegistry`, matching source script message pointers that can reference either scope.
- `ScriptVM` expands generated movement labels into result `movements` entries with target local id, structured steps, net tile delta, final facing, and unsupported-step reporting. Real dispatch now fast-forwards those net deltas into runtime map/player state; scene-node animation, object task queues, source collision timing, and real wait blocking remain future work.
- `ScriptVM` records `delay`, `opendoor`, `closedoor`, and `waitdooranim` as `field_effects` after tracing `ScrCmd_delay`, `ScrCmd_opendoor`, `ScrCmd_closedoor`, `ScrCmd_waitdooranim`, and `src/field_door.c`; transition presentation now consumes generated door animation metadata for the first door-warp overlay slice, while standalone script-driven door animation, real audio playback, and asynchronous wait timing remain future presentation/runtime work.
- `ScriptVM` records `waitstate`, `playse`, `playfanfare`, `waitfanfare`, `warp`, `warpsilent`, and `hideplayer` as structured wait, audio, transition, and player-effect results after tracing the source script command table, macros, `src/scrcmd.c`, `src/field_screen_effect.c`, and `src/overworld.c`; real sound playback, fanfare waiting, map loading/fades, and player node visibility remain future systems.
- `EventManager` now consumes `ScriptVM.transition_effects` and map warp events when the destination map has generated data: explicit-position transitions use script coordinates, while warp-id transitions look up the destination map's generated `events.warp_events[warp_id]`, then choose the destination exit task from the destination metatile behavior name, reconfigure `MapRuntime`, update `GameState.current_map_id` and player grid position, and swap `ScriptVM` to the destination map script data. Dynamic warp ids, fade timing, save callbacks, and chained destination map scripts remain future work.
- `EventManager` sources door animation metadata from `MapRuntime` for door transition sequences. Generated Littleroot door transitions now carry `SE_DOOR`, source open frame order `[-1, 0, 1, 2]`, source close frame order `[2, 1, 0, -1]`, and generated RGBA door atlas metadata into presentation playback.
- `EventManager` applies `ScriptVM` movement and object effects only during real interaction dispatch, not during `get_script_preview`, so previews stay read-only.
- `LittlerootTown` generated collision currently has 268 passable cells and 132 blocked cells.
- `LittlerootTown` has 8 generated object events; the first runtime pass shows them as placeholders and blocks movement into their occupied cells.
- `LittlerootTown` has 4 generated BG/sign events and 3 generated warp events indexed by `MapRuntime`; first-pass map warp dispatch can enter generated Brendan/May house maps and return through destination warp-id coordinates.
- `LittlerootTown` has 9 generated coordinate events indexed by `MapRuntime`; the first runtime pass dispatches normal trigger scripts after player tile movement, including the NeedPokemon grass-blocking trigger.
- Porymap (`https://github.com/huderlem/porymap`) is a useful source-format and editor-behavior reference, but the Godot port should still use its own runtime architecture.
- For every gameplay feature, script command, and code-backed system, preserve the source game's visible rules, outcomes, interaction sequencing, waits/timing, and audiovisual feedback while dropping GBA hardware/resource constraints from the Godot runtime. For map transitions this includes door animation, player step-in behavior, fade/black-screen order, frame waits, and sound timing, not just the final destination map/position. Current transition work records those details as structured sequence data and plays the first generated door animation overlay slice; final audio, fade, and sprite presentation remain future work. Palette slots, tile/palette memory limits, binary metatile/map packing, images split into source `.bin` map data, and similar representation details should be decoded into normal Godot assets/data unless a gameplay rule specifically depends on them.

## Known Source Formats

- Map metadata: `data/maps/*/map.json`
- Map scripts: `data/maps/*/scripts.inc`
- Global text: `data/text/*.inc`
- Layout metadata: `data/layouts/layouts.json`
- Layout block data: `data/layouts/*/map.bin`
- Layout border data: `data/layouts/*/border.bin`
- Tilesets: `data/tilesets/primary|secondary/*`
- Tileset images: `tiles.png`
- Tileset metatiles: `metatiles.bin`
- Tileset behavior data: `metatile_attributes.bin`
- Metatile behavior names: `include/constants/metatile_behaviors.h`
- Palettes: `palettes/*.pal`
- Pokemon data: `src/data/pokemon/species_info.h`
- Move data: `src/data/moves_info.h`
- Item data: `src/data/items.h`
- Wild encounters: `src/data/wild_encounters.json`
- Trainers: `src/data/trainers.party`

## Important Risk

Text may appear garbled when read directly in the shell because console encoding can differ from the UTF-8 source files. Do not hand-fix strings. Local map-script text labels and global `data/text/*.inc` labels now have source-backed validation passes, including `.braille` and the current `IS_FRLG` branch. C string macros still need the same treatment before they are final.

Avoid using PowerShell for script-like file rewriting or text conversion unless necessary. If PowerShell is used, explicitly consider encoding and verify the result, especially for Chinese text.

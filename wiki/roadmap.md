# Roadmap

## Milestone 0 - Knowledge Base and Skill

- Create project wiki.
- Create project-specific Codex skill.
- Establish update protocol for future Q&A and work sessions.

## Milestone 1 - Godot Foundation

- Add project directory structure. Done.
- Add `Main.tscn`, runtime autoloads, and basic input map. Main scene and autoloads are done; movement currently uses default `ui_*` actions.
- Add placeholder player scene with grid movement. Done.
- Add smoke-test scene startup.

## Milestone 2 - Import Pipeline

- Read source path from local config. First pass done with `tools/import_config.example.json`.
- Parse `layouts.json` and `map.json`. First probe done for `LittlerootTown`.
- Decode layout `map.bin` into metatile ids, collision values, elevation values, and raw u16 map-grid values. First pass done for `LittlerootTown`.
- Build a generated manifest for maps, layouts, and tilesets. First map manifest done for `LittlerootTown`.
- Report missing or unsupported data without failing the whole import. First probe report implemented for required files and first-slice assets.

## Milestone 3 - Map Rendering Slice

- Convert one tileset pair used by `LittlerootTown`. First pass done for `gTileset_General` + `gTileset_Petalburg` as a palette-baked RGBA metatile atlas.
- Render `LittlerootTown` in Godot. Debug rendering now uses generated map ids plus the generated metatile atlas; real TileMapLayer rendering remains.
- Add collision and movement permissions. First pass done with generated map-grid collision through `MapRuntime`; metatile behavior-specific movement rules remain.
- Spawn object events from `map.json`. First pass done as visible placeholders with occupied-cell blocking; real overworld sprites and event scripts remain.

## Milestone 4 - Event Script Slice

- Index object, BG/sign, warp, and coordinate events for interaction lookup. First pass done in `MapRuntime`.
- Add an interaction dispatcher path from player facing direction to debug dialogue. First pass done with `EventManager`; real script execution remains.
- Trigger coordinate events after player movement. First pass done for normal `var`/`var_value` coord triggers through `MapRuntime` and `EventManager`; full weather, wild encounter, step-count, and forced-movement chain remains future work.
- Trigger generated map warp events. First pass done for source-style x/y/elevation matching, step warps after coordinate checks, and blocked front-cell door warps; generated destination maps are loaded through warp-id coordinates when available.
- Add source-visible transition presentation. First structured sequence slice done: `EventManager` emits normal/silent and door transition sequences with traced source step order, 16-frame door/player timings, source-derived door sound intent, generated door animation metadata, and source-derived destination exit-task selection from metatile behavior names. `TransitionSequencePlayer` now consumes that contract for first-pass black fades, input lock, player hide/show, generated door animation overlays, scripted player step-in/out movement, deferred map-load timing, and `Task_ExitDoor` final step-down position. Future work must add real audio cues, exact fade color selection/timing, non-animated door and stair exit playback, destination map scripts, and final sprite presentation.
- Parse `.inc` event scripts into labels and instructions. First pass done for `LittlerootTown`, including script labels, movement labels, local text labels, and direct `msgbox`/`message` references.
- Preview simple generated dialogue from object/BG event scripts. First pass done through `EventManager.get_script_preview`; this is not a full `ScriptVM`.
- Add a minimal `ScriptVM` execution path. First pass done for synchronous dialogue scripts, including `msgbox`, `message`, source-derived `MSGBOX_NPC/SIGN/DEFAULT` expansion, basic flow control, simple flag/var operations, and VM result reporting.
- Support a minimal ScriptVM command set:
  - `msgbox`. First pass done for `MSGBOX_NPC`, `MSGBOX_SIGN`, and `MSGBOX_DEFAULT`.
  - `setflag`, `clearflag`, `checkflag`. First pass done for `setflag` and `clearflag`.
  - `setvar`, `addvar`, `compare`. First pass done for `setvar` and simple branch-time var reads.
  - `checkplayergender`. First pass done by reading `GameState.player_gender` and writing `VAR_RESULT` as `MALE`/`FEMALE`.
  - `goto`, `call`, `return`, `end`. First pass done.
  - `goto_if_eq`, `call_if_eq`, `call_if_set`, `call_if_unset`. First pass done for set/unset/eq/ne variants used by the first slice.
  - `warp`, `warpsilent`. First pass done as `ScriptVM` transition-effect records with destination, optional warp id/position, normal/silent style, and source reset semantics. Explicit-position transitions and generated warp-id transitions now reconfigure runtime map/script data and emit first-pass source-traced transition sequence data; dynamic warp ids, real animation/audio/fade playback, save callbacks, and destination map scripts remain.
  - `applymovement`, `waitmovement`. First pass done as `ScriptVM` movement-effect records with generated movement label lookup and fast-forward application through `MapRuntime`; real animation/task waiting remains.
  - `lock`, `lockall`, `release`, `releaseall`. First pass records execution effects; real object freezing remains.
  - `setobjectxy`, `setobjectxyperm`, `setobjectmovementtype`. First pass done as `ScriptVM` object-effect records with dispatch-time application through `MapRuntime`.
  - `showobject`, `hideobject`, `addobject`, `removeobject`. First pass done for current-map runtime visibility, add/remove, and source hide-flag behavior; full object lifecycle and save persistence remain.
  - `delay`, `opendoor`, `closedoor`, `waitdooranim`. First pass done as `ScriptVM` field-effect records after source C tracing; door transitions now consume generated door animation metadata for first-pass visible overlays, while standalone script-driven door animation, real frame wait integration, and real door sounds remain.
  - `waitstate`. First pass done as a `ScriptVM` field-effect wait marker for source `ScriptContext_Enable`; real async continuation remains.
  - `playse`, `playfanfare`, `waitfanfare`. First pass done as `ScriptVM` audio-effect records; real audio playback and fanfare wait tasks remain.
  - `hideplayer`. First pass done as a `ScriptVM` player-effect record; real player presentation visibility remains.

## Milestone 5 - Text Pipeline

- Parse `charmap.txt`. First pass done for map-script local text labels and global `data/text/*.inc` labels using a source-preprocessor-compatible charmap reader.
- Extract text macros and labels. First pass done for local `.string` labels inside generated map scripts and global `data/text/*.inc` labels. C text macros such as `_("")` and `COMPOUND_STRING()` remain.
- Convert text into UTF-8 Godot resources. First pass done for generated map-script labels and global text labels as UTF-8 `display_text`.
- Preserve control codes and placeholders. First pass done as generated text encoding metadata: source bytes/hex, terminator presence, control codes, placeholders, status, and warnings.
- Preserve source braille text. First pass done for `.braille` labels with `brailleformat` headers, source-derived braille bytes, and the `ScrCmd_braillemessage` 6-byte pointer skip.
- Resolve text preprocessor branches. First pass done for `#if IS_FRLG/#else/#endif` in `data/text/pc_transfer.inc`, using the Emerald `IS_FRLG = false` branch traced to `include/constants/global.h`.
- Add runtime access. First pass done through `DataRegistry.get_text_data`, `get_text_record`, and `get_text_display_text`; VM/UI integration for global text labels remains.

## Milestone 6 - Pokemon Data Slice

- Export species, moves, abilities, items, wild encounters, and trainers.
- Build `DataRegistry` accessors.
- Add validation for cross-references.

## Milestone 7 - Battle Prototype

- Implement simple single battle.
- Add type chart, damage formula, move PP, HP, fainting, and battle messages.
- Keep battle rules separate from UI.

## Milestone 8 - Full Game Systems

- Party menu, bag, Pokemon summary, Pokedex, shops, healing, saving, and overworld effects.
- Expand event script support by unsupported-opcode reports.
- Add advanced expansion mechanics after the base loop is stable.

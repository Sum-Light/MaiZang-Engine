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
- Add source-visible transition presentation. First structured sequence slice done: `EventManager` emits normal/silent and door transition sequences with traced source step order, 16-frame door/player timings, source-derived door sound intent, generated door animation metadata, and source-derived destination exit-task selection from metatile behavior names. `TransitionSequencePlayer` now consumes that contract for first-pass black fades, input lock, player hide/show, generated door animation overlays, scripted player step-in/out movement, deferred map-load timing, and `Task_ExitDoor` final step-down position. First-pass destination map-load scripts now run in source order (`MAP_SCRIPT_ON_TRANSITION`, affected object-template sync, then `MAP_SCRIPT_ON_LOAD`); future work must add real audio cues, exact fade color selection/timing, non-animated door and stair exit playback, remaining lifecycle hooks, and final sprite presentation.
- Parse `.inc` event scripts into labels and instructions. First pass done for `LittlerootTown` and the first indoor maps, including script labels, movement labels, local text labels, shared script bundles, and direct `msgbox`/`message` references.
- Preview simple generated dialogue from object/BG event scripts. First pass done through `EventManager.get_script_preview`; this is not a full `ScriptVM`.
- Add a minimal `ScriptVM` execution path. First pass done for synchronous dialogue scripts, including `msgbox`, `message`, source-derived `MSGBOX_NPC/SIGN/DEFAULT/YESNO` expansion, basic flow control, simple flag/var operations, and VM result reporting.
- Support a minimal ScriptVM command set:
  - `msgbox`. First pass done for `MSGBOX_NPC`, `MSGBOX_SIGN`, `MSGBOX_DEFAULT`, and `MSGBOX_YESNO`.
  - `yesnobox`. First pass done as a `ScriptVM` UI-effect record with source default YES/NO menu placement, default `YES`, `B = NO`, 5-frame input delay metadata, and `VAR_RESULT` values. Without an injected UI/test choice, execution stops with `waiting_for_ui`; real asynchronous menu presentation and resume remain future work.
  - `special`. First pass done for the first-slice string placeholder functions `GetPlayerBigGuyGirlString` and `GetRivalSonDaughterString`, writing `STR_VAR_1` and expanding `{PLAYER}`, `{KUN}`, `{RIVAL}`, `{B_PC_CREATOR_NAME}`, and `{STR_VAR_1/2/3}` in runtime messages while preserving unexpanded text, source placeholder ids, substitution metadata, source function names, value keys, and runtime string vars. Broader `gSpecials`, `specialvar`, version/team placeholders, and other battle/message placeholders remain future work.
  - `setflag`, `clearflag`, `checkflag`. First pass done for `setflag` and `clearflag`.
  - `setvar`, `addvar`, `compare`. First pass done for `setvar` and branch-time var reads, including source-style `<`, `=`, `>`, `<=`, `>=`, and `!=` conditional variants used by `*_if_*` macros. Numeric `LOCALID_*` operands now resolve from current-map generated object-event order plus source special ids, including OnFrame table comparisons and movement target operands that pass through source-style `VarGet`.
  - `checkplayergender`. First pass done by reading `GameState.player_gender` and writing `VAR_RESULT` as `MALE`/`FEMALE`.
  - `goto`, `call`, `return`, `end`. First pass done.
  - `goto_if_*`, `call_if_*`. First pass done for set/unset and lt/eq/gt/le/ge/ne comparison variants used by the first slice.
  - `warp`, `warpsilent`. First pass done as `ScriptVM` transition-effect records with destination, optional warp id/position, normal/silent style, and source reset semantics. Explicit-position transitions and generated warp-id transitions now reconfigure runtime map/script data, emit first-pass source-traced transition sequence data, and run destination map-load scripts (`MAP_SCRIPT_ON_TRANSITION` plus `MAP_SCRIPT_ON_LOAD`); dynamic warp ids, real animation/audio/fade playback, save callbacks, and remaining map-script hooks remain.
  - `applymovement`, `waitmovement`. First pass done as `ScriptVM` movement-effect records with generated/shared movement label lookup, raw/resolved target metadata, source-style `VarGet` local-id resolution, `waitmovement 0` last-target semantics, and fast-forward application through `MapRuntime`; real animation/task waiting remains.
  - `lock`, `lockall`, `release`, `releaseall`. First pass records execution effects; real object freezing remains.
  - `setobjectxy`, `setobjectxyperm`, `setobjectmovementtype`. First pass done as `ScriptVM` object-effect records with dispatch-time application through `MapRuntime`.
  - `showobject`, `hideobject`, `addobject`, `removeobject`. First pass done for current-map runtime visibility, add/remove, and source hide-flag behavior; full object lifecycle and save persistence remain.
  - `setmetatile`. First pass done after tracing `ScrCmd_setmetatile`, map-grid masks, and `MapGridSetMetatileIdAt`: `ScriptVM` resolves generated source metatile labels and `MapRuntime` applies the current-map mutation while preserving elevation. Automatic `MAP_SCRIPT_ON_TRANSITION` and `MAP_SCRIPT_ON_LOAD` dispatch is first-pass done for generated map loads; `MAP_SCRIPT_ON_FRAME_TABLE`/`map_script_2` dispatch is first-pass done for Brendan/May intro and clock paths, including the shared `PlayersHouse_1F` moving-in script path. `Main`/`PlayerController` now run a first-pass field-input precheck that dispatches OnFrame before accept/movement input and consumes the frame when matched; resume, return-to-field, dive-warp hooks, full step/wild-encounter ordering, and async script timing remain future work.
  - `delay`, `opendoor`, `closedoor`, `waitdooranim`. First pass done as `ScriptVM` field-effect records after source C tracing; door transitions now consume generated door animation metadata for first-pass visible overlays, while standalone script-driven door animation, real frame wait integration, and real door sounds remain.
  - `waitstate`. First pass done as a `ScriptVM` field-effect wait marker for source `ScriptContext_Enable`; real async continuation remains.
  - `playse`, `playfanfare`, `waitfanfare`. First pass done as `ScriptVM` audio-effect records; real audio playback and fanfare wait tasks remain.
  - `hideplayer`. First pass done as a `ScriptVM` player-effect record; real player presentation visibility remains.

## Milestone 5 - Text Pipeline

- Parse `charmap.txt`. First pass done for map-script local text labels and global `data/text/*.inc` labels using a source-preprocessor-compatible charmap reader.
- Extract text macros and labels. First pass done for local `.string` labels inside generated map scripts and global `data/text/*.inc` labels. C text macros such as `_("")` and `COMPOUND_STRING()` remain.
- Convert text into UTF-8 Godot resources. First pass done for generated map-script labels and global text labels as UTF-8 `display_text`.
- Preserve control codes and placeholders. First pass done as generated text encoding metadata: source bytes/hex, terminator presence, control codes, placeholders, status, and warnings. Runtime text-control parsing is also started for visible message cleanup and `text_controls` metadata covering color, shadow, font, pause, and pause-until-press controls.
- Expand runtime text placeholders. First pass done for source `StringExpandPlaceholders` ids `{PLAYER}` (`0x1`), `{STR_VAR_1/2/3}` (`0x2`-`0x4`), `{KUN}` (`0x5`, empty in this Chinese source), and `{RIVAL}` (`0x6`, Emerald gender-derived `小遥`/`小悠`). Version, team, legendary, region, and other placeholder ids remain.
- Expand battle/message dynamic text placeholders. First pass started for `{B_PC_CREATOR_NAME}` (`B_TXT_PC_CREATOR_NAME = 0x27`), using `FLAG_SYS_PC_LANETTE` and Emerald `IS_FRLG = 0` behavior to choose the PC creator text. Broader battle text tokens remain.
- Preserve source braille text. First pass done for `.braille` labels with `brailleformat` headers, source-derived braille bytes, and the `ScrCmd_braillemessage` 6-byte pointer skip.
- Resolve text preprocessor branches. First pass done for `#if IS_FRLG/#else/#endif` in `data/text/pc_transfer.inc`, using the Emerald `IS_FRLG = false` branch traced to `include/constants/global.h`.
- Add runtime access. First pass done through `DataRegistry.get_text_data`, `get_text_record`, and `get_text_display_text`; `ScriptVM` and `EventManager` now resolve message text from local map-script labels first, then global text labels through `DataRegistry`.

## Milestone 6 - Pokemon Data Slice

- Export species, moves, abilities, items, wild encounters, trainers, level-up learnsets, natures, and evolutions. First pass done for species data from `src/data/pokemon/species_info.h`, move data from `src/data/moves_info.h`, ability data from `src/data/abilities.h`, item data from `src/data/items.h` plus `src/data/pokemon/item_effects.h`, wild encounter data from `src/data/wild_encounters.json`, trainer data from `src/data/trainers.party`, active `GEN_9` learnsets from `src/data/pokemon/level_up_learnsets/gen_9.h`, natures from `src/pokemon.c:gNaturesInfo`, and `SpeciesInfo.evolutions` entries from `src/data/pokemon/species_info.h`/included family files.
- Build `DataRegistry` accessors. First pass done for generated species, move, ability, item, trainer, nature, level-up learnset, and evolution data by category, symbol, short symbol, numeric id, or learnset label where applicable; wild encounters have category, label, and map-symbol lookup accessors, and evolutions also expose reverse pre-evolution lookup by target species.
- Add validation for cross-references. First pass done for generated species stats, Bulbasaur/Egg/Unown registry lookup, generated move stats, Pound/Fire Punch/Thunder move lookup, additional-effect field coverage, generated ability stats, C default field handling, active-config ability flag evaluation, generated item stats, item effect byte arrays, TM/HM item aliases, Pokeball secondary ids, berry held effects, item lookup by id/symbol, wild encounter stats, Route101/Route119 sample slots, Altering Cave special tables, encounter slot probability tables, trainer stats, trainer id/short-symbol lookup, AI masks, double-battle flags, held items, explicit move lists, source default level/IV behavior, mugshot metadata, generated learnset stats, Geodude/Torchic sample learnsets, generated nature stats, Adamant/Modest stat modifiers, trainer default move assignment from learnsets, generated evolution stats, Bulbasaur/Tyrogue/Eevee/Nincada evolution records, and Shedinja split-evolution/pre-evolution lookup; broader graphics, form, item behavior, ability behavior, encounter runtime behavior, trainer battle behavior, actual evolution execution/evolution-scene presentation, and full battle-data cross-reference validation remains.

## Milestone 7 - Battle Prototype

- Implement simple single battle. First pass started with a UI-independent `BattleEngine` autoload and `create_single_battle_state`.
- Add type chart, damage formula, move PP, HP, fainting, nature stat modifiers, and battle messages. First pass done for ordinary deterministic damaging moves: source type chart, source base damage formula, generated `gNaturesInfo` stat modifiers, 85-100 damage-roll metadata, STAB, PP decrement, HP/fainting, and structured first-pass battle message events. Accuracy, critical hits, weather, burn/frostbite, protection, abilities, held items, screens, multi-target modifiers, move-specific effects, and final battle text/presentation remain.
- Keep battle rules separate from UI. First pass done: `BattleEngine` returns dictionaries for rules results and does not depend on battle scenes.
- Construct generated trainer parties for battle. First pass done for explicit-move trainer Pokemon and source default level-up trainer moves using generated learnsets; broader party pools, dynamic trainer ids/difficulty, AI, rewards, rematches, and battle presentation remain future work.

## Milestone 8 - Full Game Systems

- Party menu, bag, Pokemon summary, Pokedex, shops, healing, saving, and overworld effects.
- Expand event script support by unsupported-opcode reports.
- Add advanced expansion mechanics after the base loop is stable.

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
- `DataRegistry`: read-only access to generated Pokemon species, moves, abilities, items, natures, evolutions, maps, tilesets, scripts, text, trainers, learnsets, and encounters.
- `MapRuntime`: current map query service for bounds, collision, elevation, metatile ids, metatile behavior ids/names, and layer type.
- `MapLoader`: builds Godot map scenes from generated map data.
- `GridMover`: shared grid movement for player and NPCs.
- `EventManager`: dispatches map events, warps, signs, object interaction, and coordinate triggers.
- `ScriptVM`: interprets converted event scripts.
- `PartyRuntime`: source-backed Pokemon instance and six-slot party runtime shared by battle, evolution, menu, save, and future capture/storage systems.
- `BattleEngine`: deterministic battle rules separate from battle UI.
- `EvolutionEngine`: source-backed evolution target, condition, pre-evolution, and split-evolution rules separate from presentation and party mutation.
- `EncounterEngine`: source-backed wild encounter table, slot, level, and first-pass encounter-rate rules separate from field-step dispatch and battle presentation.
- `SaveService`: serializes runtime state.
- `ImportReport`: records missing assets, unsupported opcodes, broken links, and conversion warnings.

## First Vertical Slice

The first playable milestone should load `LittlerootTown`, render its layout, spawn the player and NPCs, support grid movement, run one simple NPC dialogue, and handle at least one warp placeholder.

This proves the import pipeline, map runtime, event dispatch, and basic presentation pipeline before the project expands into battle systems.

## Current Scaffold

- `GameState` stores current map id, player gender, player name, player grid position, player party, flags, and vars.
- `DataRegistry` stores first-slice constants for LittlerootTown, loads the generated import manifest, and resolves generated map, tileset, map script, shared script, global text, Pokemon species JSON, Pokemon move JSON, Pokemon ability JSON, Pokemon item JSON, Pokemon wild encounter JSON, Pokemon trainer JSON, Pokemon level-up learnset JSON, Pokemon nature JSON, and Pokemon evolution JSON.
- `MapRuntime` configures the current generated map and exposes simple passability and metatile queries, including source metatile behavior names.
- `MapRuntime` indexes generated door animation metadata by metatile id and can return the animation for a map cell.
- `MapRuntime` indexes generated object events, source numeric local-id aliases, BG/sign events, warp events, and coordinate events; visible object-event cells are occupied for first-pass movement.
- `MapRuntime` indexes generated coordinate events and resolves step-triggered coord event targets using source-style x/y/elevation plus var/flag trigger checks.
- `MapRuntime` can apply `ScriptVM` movement-effect results as source-trusted logical position changes for object events and the player, then rebuild object occupancy.
- `MapRuntime` can apply `ScriptVM` object-effect results for current object position, template position, movement type metadata, runtime visibility, add/remove, and hide flags, then rebuild object occupancy.
- `MapRuntime` can apply `ScriptVM` `setmetatile` field effects as in-memory current-map mutations, preserving source elevation bits while updating metatile id, collision, and raw map-grid data.
- `MapRuntime.get_interaction_target` resolves the player's faced object/sign target, or a generated warp event from the current/faced cell after x/y/elevation matching.
- `GridMover` provides tweened tile movement.
- `PlayerController` runs an optional field-input precheck before accept/movement input, reads directional input, tracks facing direction, moves one tile at a time after checking `MapRuntime.can_enter_cell`, emits interaction requests on `ui_accept`, and can be input-locked by transition presentation.
- `ScriptVM` executes the first synchronous event-script subset for generated dialogue, movement-effect, object-effect, field-effect, UI-effect, special-effect, audio-effect, transition-effect, and player-effect scripts and returns messages, movements, object effects, field effects, UI effects, special effects, audio effects, transition effects, player effects, effects, unsupported ops, trace entries, runtime string vars, and wait metadata.
- `PartyRuntime` is registered as a domain/runtime autoload. Its first slice creates source-shaped party Pokemon through `BattleEngine` stat/move initialization, preserves source-backed instance metadata, caps player parties at six, stores player party data through `GameState`, builds battle-party projections, and can pass party context into `EvolutionEngine` without depending on party UI or save scenes.
- `SaveService` is registered as a domain/runtime autoload. Its first slice builds source-traced Godot JSON save snapshots from `GameState` and current `MapRuntime`, writes and reads them under `user://`, restores player profile/location/flags/vars/party/current-map object-event state, records save status/counter metadata, and exposes source save-flow labels without depending on save menu presentation.
- `BattleEngine` is registered as a domain/rules autoload. Its first slice builds battle Pokemon and trainer parties from generated Pokemon data, including explicit trainer moves, source default level-up move assignment through generated learnsets, and source nature stat modifiers through generated natures; it calculates ordinary move damage from traced source formulas, applies STAB and type effectiveness, updates PP/HP/fainting, and returns structured first-pass battle message events without depending on presentation scenes.
- `EvolutionEngine` is registered as a domain/rules autoload. Its first slice reads generated evolution/species/item/move data through `DataRegistry`, evaluates source-ordered evolution targets for level/trade/item/battle/overworld/script-trigger modes, applies source additional-condition semantics, handles Everstone and item-check stop behavior, exposes reverse pre-evolution lookup, and reports Shedinja split-evolution candidate metadata without mutating party or bag state.
- `EncounterEngine` is registered as a domain/rules autoload. Its first slice reads generated wild encounter data through `DataRegistry`, selects the current map encounter record including the Altering Cave `VAR_ALTERING_CAVE_WILD_SET` table offset, resolves land/water/rock-smash/fishing area tables, chooses source-probability slots including rod groups, chooses first-pass levels, and returns source-traced encounter candidates plus encounter-rate check metadata without dispatching field steps or starting battles.
- `ScriptVM` resolves numeric `LOCALID_*` tokens from the current generated map object-event order, matching source `tools/mapjson/mapjson.cpp` where map object local-id constants are object index + 1, while preserving special constants such as `LOCALID_PLAYER`. Movement command targets follow source `VarGet` behavior and preserve both raw and resolved targets in result metadata.
- `ScriptVM` message results include generated text encoding metadata such as charmap status, source byte count, terminator presence, source file, and text kind when the source text record provides it.
- `EventManager` dispatches object, BG/sign, coordinate-event, and warp-event interactions through `ScriptVM` or generated event data when available, applies movement and object effects through `MapRuntime`, consumes generated explicit-position and warp-id transition effects, emits source-traced transition sequence data, then emits debug dialogue lines for the HUD.
- `EventManager` can run source map header scripts by type through generated `map_script_table` records. The current first pass supports automatic map-load lifecycle dispatch during initial load and transition load: `MAP_SCRIPT_ON_TRANSITION`, loading-time object template sync for affected `setobjectxyperm` targets, then `MAP_SCRIPT_ON_LOAD`. It also exposes a source-traced `MAP_SCRIPT_ON_FRAME_TABLE` evaluator for `map_script_2` tables, and `Main` dispatches it through the `PlayerController` field-input precheck before accept/movement input. The target scripts run through `ScriptVM` and supported runtime effects apply through `MapRuntime`.
- `ScriptVM` opcode behavior must continue to be derived from the source C implementation and referenced resources before being implemented in Godot.
- `DebugMapPlane` draws the first generated `block_ids` metatile grid from a palette-baked RGBA metatile atlas, with the old color blocks as fallback. It can also draw generated door animation frame overlays above the map grid.
- `ObjectEventSpawner` draws generated object events as simple placeholders until overworld sprite import is ready.
- `TransitionSequencePlayer` consumes source-traced transition sequence data for the current first-pass presentation: fade overlay, input lock, player visibility, scripted player steps, generated door animation frame overlays, deferred map load application, and final door-exit player position updates.
- `Main` connects the debug world, player, camera, HUD status label, debug dialogue panel, and first-pass transition overlay, delegates transition sequence playback to `TransitionSequencePlayer`, and shows whether map data came from generated JSON or fallback constants.

## Generated Map Runtime Contract

- First-slice generated map JSON is loaded through `DataRegistry`.
- First-slice generated tileset JSON is loaded through `DataRegistry`.
- `data/generated/import_manifest.json` is the registry index for generated maps, tilesets, scripts, and text datasets. Importers must merge entries by stable identity instead of replacing same-type manifest lists.
- `block_ids` contains unpacked 10-bit metatile ids for simple render previews.
- `map_grid.raw`, `map_grid.collision`, and `map_grid.elevation` preserve the original 16-bit map-grid data split into runtime-friendly layers.
- First-pass movement uses generated `map_grid.collision`: cells with collision `0` are enterable and nonzero or out-of-bounds cells are blocked.
- `MapRuntime` also indexes generated metatile attributes so later rules can inspect behavior id, behavior name, and layer type without reparsing tileset JSON in presentation scripts.
- Generated tileset JSON includes a `metatile_behaviors` table from `include/constants/metatile_behaviors.h`, and each metatile attribute includes `behavior_name` alongside the raw numeric behavior id.
- Generated tileset JSON includes a `metatile_labels` table from `include/constants/metatile_labels.h` so script commands can resolve source `METATILE_*` symbols without hardcoded Godot ids.
- Generated tileset JSON may include `door_animations` for used animated-door metatiles. These records are derived from `include/constants/metatile_labels.h`, `src/field_door.c`, and `graphics/door_anims/*.png`; they point to normal RGBA frame atlases and include source frame order, 60fps frame timing, and source sound-effect symbols.
- `MapRuntime` indexes generated door animation records by metatile id so transition code can ask the current map cell for a source-backed door animation without reparsing tileset JSON.
- Generated `events.object_events` are preserved in map JSON and indexed by `MapRuntime`; visible events block their current grid cell before event scripts or sprite imports are implemented.
- Runtime object-event positions may diverge from generated source positions after script movement effects are applied. `MapRuntime` updates `position`, `x`, `y`, optional `facing_direction`, and occupancy indexes in memory only.
- Runtime object-event template state may also diverge after object effects are applied. `setobjectxyperm` updates `template_position`/`template_x`/`template_y` without moving the active placeholder during normal script dispatch; `setobjectmovementtype` updates template metadata and the current placeholder metadata as a first-pass map-load approximation.
- Map-load lifecycle dispatch has one source-traced exception to that normal `setobjectxyperm` rule: after `MAP_SCRIPT_ON_TRANSITION`, `MapRuntime.sync_object_events_to_templates_for_map_load` projects only the affected template-position targets onto current runtime object events. This matches source timing where object templates are modified before object events become visible on the destination map.
- `hideobject` and `showobject` toggle in-memory runtime visibility. `removeobject` hides the runtime event and sets its source hide flag in `GameState` when available. `addobject` attempts to show the event at its template position but does not clear source hide flags.
- `setmetatile` field effects update only the current in-memory map state. The runtime writes the current metatile id/collision/elevation/raw layers back into its duplicated map data and emits `map_changed`; generated source files remain reproducible importer outputs.
- Generated `events.bg_events` and `events.warp_events` are preserved in map JSON and indexed by `MapRuntime` for interaction and first-pass map warp dispatch.
- Generated `events.coord_events` are preserved in map JSON and indexed by `MapRuntime`; first-pass step triggers match source x/y/elevation rules and compare generated `var`/`var_value` against `GameState`.
- Generated metatile atlases use metatile id as atlas index, so map `block_ids` can render directly during the first slice.
- Palette handling belongs to the import layer. Godot runtime should consume normal RGBA textures and metadata, not GBA palette slots.
- Real TileMapLayer rendering should later consume the generated atlas/metadata instead of the current debug Node2D renderer.

## Generated Script Runtime Contract

- First-slice generated map-script and shared-script JSON is loaded through `DataRegistry`.
- Generated script bundles can be map-scoped or shared-scoped. Shared bundles such as `shared_players_house` expose source labels from common include files so map scripts can call/branch into labels that were not physically inside the map's `scripts.inc`.
- `DataRegistry` exposes a global generated script-label namespace for script, movement, and script-local text records. `ScriptVM` resolves current-map records first, then falls back through this global generated namespace.
- Generated script JSON preserves map script labels, raw instruction streams, movement labels, local text labels, and importer statistics.
- Generated root map-script tables are represented as `kind = "map_script_table"` script records with `map_script` instructions. Runtime map-script lifecycle dispatch scans those records for the requested source type and, matching source `MapHeaderGetScriptTable`, runs the first matching label.
- Root `MAP_SCRIPT_ON_FRAME_TABLE` entries point to secondary `map_script_2` tables. `EventManager.try_run_on_frame_map_script(...)` scans those tables with source `MapHeaderCheckScriptTable`/`VarGet` comparison semantics and starts the first non-no-effect target script through `ScriptVM`; `dispatch_on_frame_map_script(...)` emits the runtime debug lines for real dispatch.
- The current OnFrame implementation has a first-pass automatic field-input hook: `Main` wires `PlayerController.configure_field_input_precheck(...)`, dispatches OnFrame before accept/movement input, and consumes that frame if a table entry starts a script. Brendan/May house intro paths now execute shared `PlayersHouse_1F` scripts and apply the first-pass source message, movement, gender, and state effects; exact source timing around the global script context, async waits, resume scripts, dive checks, and the full step/wild-encounter/warp ordering remains future traced runtime work.
- Numeric script values, map-script table comparisons, and movement command targets resolve `LOCALID_*` tokens from the current generated map object-event order, matching source generated constants from `tools/mapjson/mapjson.cpp`; GBA special ids such as `LOCALID_PLAYER`, `LOCALID_CAMERA`, and `LOCALID_FOLLOWING_POKEMON` stay explicit constants.
- Generated local text records keep UTF-8 `display_text` for Godot runtime/UI and nested `encoding` metadata for source compatibility checks: charmap status, source bytes/hex, byte count, terminator presence, control codes, placeholders, and warnings.
- `ScriptVM` resolves message text records from generated local map-script labels first, then from shared/global generated script text labels through `DataRegistry`, then from global generated text through `DataRegistry.get_text_record(label, "global")`. This follows source `ScrCmd_message`, which reads a text pointer and does not restrict it to map-local labels.
- `EventManager.get_script_preview` follows the same text lookup order for both VM-backed previews and the direct fallback path, and includes text source, kind, encoding status, source byte count, and terminator metadata in preview records.
- `EventManager.get_script_preview` now delegates to `ScriptVM` when available and falls back to the older direct `msgbox`/`message` preview only when the VM is unavailable.
- Source trace metadata in generated script JSON records the C/resources consulted for supported preview behavior, including `ScrCmd_message`, `ShowFieldMessage`, `gStdScripts`, and standard `msgbox` scripts.
- Current `ScriptVM` support covers a synchronous first slice: `msgbox`, `message`, `yesnobox`, `special`, `lock`, `lockall`, `release`, `releaseall`, `faceplayer`, `waitmessage`, `waitbuttonpress`, `closemessage`, `goto`, `call`, `return`, `end`, `*_if_set/unset/lt/eq/gt/le/ge/ne` branches, `setflag`, `clearflag`, `setvar`, `checkplayergender`, `applymovement`, `applymovementat`, `waitmovement`, `waitmovementat`, `setobjectxy`, `setobjectxyperm`, `setobjectmovementtype`, `addobject`, `addobjectat`, `removeobject`, `removeobjectat`, `showobject`, `showobjectat`, `hideobject`, `hideobjectat`, `delay`, `setmetatile`, `opendoor`, `closedoor`, `waitdooranim`, `waitstate`, `playse`, `playfanfare`, `waitfanfare`, `warp`, `warpsilent`, and `hideplayer`.
- `checkplayergender` reads `GameState.player_gender`, writes `VAR_RESULT` as source-compatible `MALE`/`FEMALE` values, and relies on existing conditional branch support for gendered scripts.
- `msgbox` modes `MSGBOX_NPC`, `MSGBOX_SIGN`, `MSGBOX_DEFAULT`, and `MSGBOX_YESNO` are expanded according to `data/scripts/std_msgbox.inc`.
- `MSGBOX_YESNO` expands to source `Std_MsgboxYesNo`: show the remembered message text, wait for the message, then run `yesnobox 20, 8`. Source `ScriptMenu_YesNo` currently ignores those script coordinates and uses the default YES/NO window at tilemap position `21,9`, size `5x4`, default cursor `YES`, `B` as `NO`, and about 5 frames of input delay.
- `yesnobox` records a `ui_effects` entry and sets `wait_ui`. Without an injected test/UI choice, it writes `VAR_RESULT = 0xFF`, returns `status = waiting_for_ui`, and stops execution instead of guessing a player selection. With context-provided `YES`/`NO`/`B`, it writes source-compatible `VAR_RESULT` values and lets branch instructions continue.
- First-pass `special` support is source-traced for the first-slice string placeholder functions `GetPlayerBigGuyGirlString` and `GetRivalSonDaughterString` from `src/field_specials.c`. These write `STR_VAR_1` according to `GameState.player_gender` and record `special_effects`; unknown specials still report unsupported behavior.
- `ScriptVM` message execution now preserves cleaned visible `text`, source `unexpanded_text`, `expanded_text` before control-token cleanup, and per-occurrence `placeholder_substitutions` with source placeholder ids, source function names, and value keys when available. Runtime placeholder expansion currently covers `{PLAYER}` from `GameState.player_name`, `{KUN}` as the current source's empty honorific placeholder, `{RIVAL}` as the Emerald gender-derived May/Brendan display name, `{B_PC_CREATOR_NAME}` from the source battle-message PC creator branch, and `{STR_VAR_1}`, `{STR_VAR_2}`, and `{STR_VAR_3}` from VM string vars. Version, team, legendary, region, and broader battle text placeholders remain future traced text/runtime work.
- First-pass runtime text-control parsing covers source `EXT_CTRL_CODE_COLOR`, `EXT_CTRL_CODE_SHADOW`, `EXT_CTRL_CODE_FONT`, `EXT_CTRL_CODE_PAUSE`, and `EXT_CTRL_CODE_PAUSE_UNTIL_PRESS` tokens represented in generated UTF-8 display text as `{COLOR ...}`, `{SHADOW ...}`, `{FONT_NORMAL}`, `{FONT_MALE}`, `{FONT_FEMALE}`, `{PAUSE n}`, and `{PAUSE_UNTIL_PRESS}`. The visible message `text` omits these non-glyph controls, while `text_controls` records source code ids, source lengths from `GetExtCtrlCodeLength`, values, offsets, frame counts, and button-press wait intent for the future dialogue renderer.
- `GameState.player_name` is currently a profile/debug field with fallback `"玩家"` and source length constant `PLAYER_NAME_LENGTH = 7`; the real source naming flow, random/default preset names, and naming-screen constraints still need a separate traced implementation before this is final save-profile behavior.
- `waitmessage`, `waitbuttonpress`, lock, release, and faceplayer currently produce execution effects and metadata for the debug dialogue path; real asynchronous blocking, UI input continuation, object freezing, and facing animation remain future runtime work.
- `applymovement` currently looks up generated movement labels and expands movement instructions into result entries with raw target, resolved target local id, movement label, structured steps, net tile delta, final facing, and unsupported-step reporting. `waitmovement 0` resolves to the current/last moving target, matching source command state.
- `waitmovement 0` follows the source command convention by waiting on the current/last moving NPC target rather than meaning "all movement"; the VM records the raw target and resolved target for later animation-task integration.
- Movement execution is currently a fast-forward runtime effect after real dispatch: `MapRuntime` applies net tile deltas to generated object-event local ids, `GameState.player_grid_position` for `LOCALID_PLAYER`, and emits signals so placeholders/player nodes refresh.
- Object-effect execution is also a fast-forward runtime effect after real dispatch: `MapRuntime` mutates generated object-event dictionaries in memory, updates occupancy, and emits refresh signals for placeholder respawn/visibility.
- Field-effect execution is currently recorded by `ScriptVM`: `delay` stores frame counts, `setmetatile` resolves source metatile labels and records source map-grid/collision semantics, `opendoor`/`closedoor` store resolved script coordinates, and `waitdooranim` records the source wait point. `EventManager` applies `setmetatile` through `MapRuntime` during real dispatch; door transition presentation applies the generated map door animation slice through transition sequence data. Standalone script-driven door animation, broader async timing, and real audio playback remain future Godot presentation/runtime work.
- Audio and player-effect execution is currently recorded but not applied to presentation: `playse`, `playfanfare`, and `waitfanfare` populate `audio_effects`; `hideplayer` populates `player_effects`. Transition effects are partially applied when generated destination maps exist: `warp`/`warpsilent` explicit coordinates and generated warp-id destinations can reload map/tileset/script data, move the player, swap script data, and run first-pass destination map-load scripts in source order (`MAP_SCRIPT_ON_TRANSITION`, affected template sync, `MAP_SCRIPT_ON_LOAD`). Real sound playback, fanfare tasks, fades, save callbacks, other lifecycle hooks, and player node visibility remain future Godot systems.
- Explicit-position and generated warp-id transition effects are now applied when generated destination data exists: `EventManager` uses `DataRegistry` to load destination map/tileset/script data and either applies the transition immediately for headless/domain usage or queues it for deferred presentation playback. Deferred playback applies the map change at the sequence `load_map` step, updates `GameState.current_map_id`, and moves the player either to the explicit destination coordinate or to `events.warp_events[warp_id]` in the destination map.
- Transition sequence data currently records a `60fps` frame basis and source references for `DoWarp`, `DoDoorWarp`, `Task_DoDoorWarp`, `FieldCB_DefaultWarpExit`, `SetUpWarpExitTask`, metatile behavior helpers, door animation tables, and normal tile-walk timing. Door sequences include source-order lock/freeze, source-derived door sound intent, generated door animation metadata when available, 16-frame open, 16-frame player step up, hide player, 16-frame close, fade/load/fade, source-derived exit-task selection, conditional exit-door step down, and unlock steps. Normal/silent sequences record lock, fade/load/fade, source-derived exit-task selection, conditional exit-door step down, and unlock steps.
- `TransitionSequencePlayer` currently consumes transition sequences with a black overlay, input lock, player visibility toggles, scripted player movement, and generated door animation overlays through the configured map renderer. `Task_ExitDoor` playback now leaves the player one tile below the destination door, matching the source visible exit movement. Real audio playback, exact fade color selection, non-animated door/stair exit playback, save callbacks, other map-script lifecycle hooks, and full player visibility semantics remain future work.
- Coordinate-event execution is currently dispatched after player tile movement in `Main`, followed by first-pass generated map warp-event dispatch when no coordinate event matched. Blocked front-cell door warp dispatch only fires while facing north, matching source `TryDoorWarp`. Weather, wild encounter, step-count, and forced-movement script chaining remain future work.
- Movement dispatch does not yet run step-by-step animation, source collision checks, movement task timing, or object freeze/unfreeze behavior. Object-effect dispatch does not yet model the full source object lifecycle, object graphics reload, or save persistence beyond `GameState` flags. Audio and player effects are recorded, while transition sequences have only a placeholder overlay consumer. `EventManager.get_script_preview` must remain read-only and must not apply runtime effects.
- Unsupported opcodes should stay visible through reports and VM results rather than being silently approximated.

## Generated Pokemon Species Contract

- Pokemon species JSON is loaded through `DataRegistry` from the manifest `pokemon` entry with category `species`.
- `DataRegistry.get_pokemon_data("species")`, `get_species_data`, `get_species_record`, `get_species_record_by_symbol`, and `get_species_record_by_id` are read-only accessors for generated species records.
- Generated species records preserve source symbols, numeric species ids, source file/line references, raw initializer fields, source references for graphics/learnsets/evolutions/forms, and source-derived constant records for types, abilities, egg groups, growth rates, body colors, items, cries, and national dex ids.
- Struct initializers expose the first runtime-ready data slice: base stats, EV yields, catch and exp values, gender ratio, egg cycles, friendship, dimensions, display text, types, abilities, egg groups, growth rate, body color, dex number, held items, flags, and graphics/source-resource references where present.
- Macro-generated species initializers currently remain explicit `initializer_kind = "macro_call"` records with `evaluation_status = "partial"`, raw macro calls, arguments, source locations, and warnings. They must be expanded only after tracing the source macro definitions and referenced resources, not guessed from neighboring forms.
- Runtime systems should consume generated Godot-friendly species JSON and later generated textures/resources. Source palettes and packed graphics remain import concerns; gameplay and presentation should preserve source-visible Pokemon behavior and data outcomes without recreating GBA storage limits.

## Generated Pokemon Moves Contract

- Pokemon move JSON is loaded through `DataRegistry` from the manifest `pokemon` entry with category `moves`.
- `DataRegistry.get_pokemon_data("moves")`, `get_moves_data`, `get_move_record`, `get_move_record_by_symbol`, and `get_move_record_by_id` are read-only accessors for generated move records.
- Generated move records preserve source symbols, numeric move ids, source file/line references, raw initializer fields, source-facing move names/descriptions plus UTF-8 display text, core battle fields, flags, ban flags, arguments, additional effects, contest data, and battle animation script symbols.
- The move importer evaluates the active source configuration and constants from `src/data/moves_info.h`, `include/move.h`, move/battle/Pokemon/contest headers, and relevant `include/config/*` headers; generated JSON is the current source branch, not a union of inactive preprocessor branches.
- Battle move effects, additional effect semantics, animation scripts, targeting behavior, and contest behavior must still be implemented only after tracing the corresponding source C and referenced resources. The generated data records the source symbols needed for that later work; it does not by itself define Godot battle behavior.

## Generated Pokemon Abilities Contract

- Pokemon ability JSON is loaded through `DataRegistry` from the manifest `pokemon` entry with category `abilities`.
- `DataRegistry.get_pokemon_data("abilities")`, `get_abilities_data`, `get_ability_record`, `get_ability_record_by_symbol`, and `get_ability_record_by_id` are read-only accessors for generated ability records.
- Generated ability records preserve source symbols, numeric ability ids, source file/line references, raw initializer fields, source-facing ability names/descriptions plus UTF-8 display text, `ai_rating`, all `struct AbilityInfo` flags, raw flag expressions where present, and explicit C default markers for omitted zero/false fields.
- The ability importer evaluates the active source configuration from `src/data/abilities.h`, `include/pokemon.h`, `include/constants/abilities.h`, `include/config/general.h`, and `include/config/battle.h`, including `B_UPDATED_ABILITY_DATA` expressions that affect flags.
- Ability behavior is not inferred from names or data alone. Battle behavior, overworld ability effects, ability popups, summary/Pokedex UI, copying/swapping/suppressing/overwriting rules, AI use of `aiRating`, and any animation/audio/text presentation must still be implemented only after tracing the corresponding source C and referenced resources.

## Generated Pokemon Items Contract

- Pokemon item JSON is loaded through `DataRegistry` from the manifest `pokemon` entry with category `items`.
- `DataRegistry.get_pokemon_data("items")`, `get_items_data`, `get_item_record`, `get_item_record_by_symbol`, and `get_item_record_by_id` are read-only accessors for generated item records.
- Generated item records preserve source symbols, numeric item ids, source file/line references, raw `struct ItemInfo` fields, source-facing item names/descriptions plus UTF-8 display text, C-defaulted fields, sell prices from `ITEM_SELL_FACTOR`, pocket/sort/type/battle-usage/hold-effect constant records, secondary ids for Pokeballs/natures/types/mail/berries/mulch, field-use function symbols, icon symbols, and item effect references.
- Generated item effect records preserve `src/data/pokemon/item_effects.h` byte-array symbols, source locations, lengths, explicit designated entries, evaluated values, u8 byte values, and expanded friendship helper macros such as `VITAMIN_FRIENDSHIP_CHANGE`, `FEATHER_FRIENDSHIP_CHANGE`, and `EV_BERRY_FRIENDSHIP_CHANGE`.
- The item importer evaluates active item/source configuration from `src/data/items.h`, `src/data/pokemon/item_effects.h`, `include/item.h`, item/constants headers, `include/constants/tms_hms.h`, and relevant `include/config/*` headers. TM/HM item aliases such as `ITEM_TM_THUNDER` are resolved from the source `FOREACH_TM`/`FOREACH_HM` lists.
- Item behavior is not inferred from names or data alone. Bag UI, shops, field-use functions, berries, mail, Pokeballs, held-item effects, battle item execution, Enigma Berry save-data special cases, icons, audio, animations, and menu timing must still be implemented only after tracing the corresponding source C and referenced resources.

## Generated Wild Encounters Contract

- Pokemon wild encounter JSON is loaded through `DataRegistry` from the manifest `pokemon` entry with category `wild_encounters`.
- `DataRegistry.get_pokemon_data("wild_encounters")`, `get_wild_encounters_data`, `get_wild_encounter_record`, `get_wild_encounter_records_for_map`, and `get_wild_encounter_record_for_map` are read-only accessors for generated encounter records.
- Generated encounter records preserve source header labels, base labels, map symbols, reconstructed map group/number values, current time-of-day generation config, encounter rates, slot levels, source species symbols and ids, slot probability tables, and runtime reference files.
- Fishing encounter probabilities preserve source rod groups separately from the flat slot list because source selection uses Old/Good/Super Rod subranges.
- `MAP_ALTERING_CAVE` preserves the source special case where `VAR_ALTERING_CAVE_WILD_SET` offsets into 9 encounter tables when the value is below `NUM_ALTERING_CAVE_TABLES`.
- Wild encounter runtime behavior is not implemented by the generated data alone. Step timing, encounter-rate rolls, Repel, ability modifiers, surfing/fishing flags, Sweet Scent, DexNav, mass outbreaks, Feebas tiles, roamers, Battle Pike/Pyramid behavior, battle setup, audio, and presentation timing must still be implemented only after tracing the corresponding source C and referenced resources.
- `EncounterEngine` is the first runtime consumer for generated wild encounter data. It implements map-record lookup, Altering Cave table selection through `VAR_ALTERING_CAVE_WILD_SET`, land/water/rock-smash/fishing table lookup, source slot probability selection, fishing rod group selection, first-pass level selection, and `WildEncounterCheck`-style `encounterRate * 16` metadata.
- `EncounterEngine` does not yet own step dispatch, metatile behavior routing, Repel/lure/ability/flute/Cleanse Tag modifiers, roamer/mass-outbreak/double-battle branches, Battle Pike/Pyramid generation, Route 119 Feebas, Sweet Scent, fishing bite/minigame timing, Synchronize/gender/nature/personality/IV creation, enemy party creation, battle transitions, Safari Pokeblock behavior, DexNav hidden encounters, or Sootopolis legendary suppression. Those must remain visible as unsupported/future notes until traced runtime and presentation slices are implemented.

## Generated Pokemon Trainers Contract

- Pokemon trainer JSON is loaded through `DataRegistry` from the manifest `pokemon` entry with category `trainers`.
- `DataRegistry.get_pokemon_data("trainers")`, `get_trainers_data`, `get_trainer_record`, `get_trainer_record_by_symbol`, and `get_trainer_record_by_id` are read-only accessors for generated trainer records.
- Generated trainer records preserve source trainer symbols, numeric trainer ids, source file/line references, UTF-8 trainer names, trainer class/pic/back-pic/gender/music constants, AI flags and masks, item lists, battle type, difficulty, mugshot color, starting statuses, party size, and pool metadata.
- Generated party records preserve source Pokemon header data, source rewrite metadata, species, gender, held item, level, IV/EV macro values, ability, ball, friendship, nature, shiny state, Dynamax/Gigantamax/Tera fields, tags, explicit move lists, and whether source runtime will assign default level-up moves.
- The trainer importer follows `tools/trainerproc/main.c` behavior rather than guessing from the DSL comments: omitted Pokemon levels default to 100, omitted IVs default to all 31, omitted moves rely on `src/battle_main.c:CustomTrainerPartyAssignMoves`, and trainer/pokemon constants are resolved through the same source naming rules where practical.
- Trainer battle behavior is not implemented by the generated data alone. Enemy party construction, party pool selection, dynamic trainer ids/difficulty, AI decision behavior, item usage, trainer transition/mugshot presentation, battle music, send-out timing, ability/item/move behavior, and battle UI/audio/animation must still be implemented only after tracing the corresponding source C and referenced resources.

## Generated Pokemon Learnsets Contract

- Pokemon level-up learnset JSON is loaded through `DataRegistry` from the manifest `pokemon` entry with category `learnsets`.
- `DataRegistry.get_pokemon_data("learnsets")`, `get_learnsets_data`, `get_level_up_learnset_record`, and `get_level_up_learnset_for_species` are read-only accessors for generated learnset records.
- The learnset importer selects the active source generation from `P_LVL_UP_LEARNSETS`; the current source target uses `GEN_9` from `src/data/pokemon/level_up_learnsets/gen_9.h`.
- Generated learnset records preserve source labels, source file/line references, ordered move entries, move constants, numeric move ids, levels, and level-zero moves. Level-zero entries are preserved as data even when a runtime algorithm skips them.
- `BattleEngine` source default move assignment follows `src/pokemon.c:GiveBoxMonInitialMoveset` for the current first pass: iterate learnset entries in order, stop when an entry level exceeds the Pokemon level, skip level 0 entries, skip duplicate moves already selected, append up to four moves, then roll the four-slot window forward for later eligible moves. PP comes from generated move data as the Godot equivalent of `GetMovePP`.
- Learning new moves after level-up, relearning, evolution/form learnset changes, move tutor/TM/HM compatibility, party UI, and move-learning presentation remain future source-traced systems.

## Generated Pokemon Natures Contract

- Pokemon nature JSON is loaded through `DataRegistry` from the manifest `pokemon` entry with category `natures`.
- `DataRegistry.get_pokemon_data("natures")`, `get_natures_data`, `get_nature_record`, `get_nature_record_by_symbol`, and `get_nature_record_by_id` are read-only accessors for generated nature records.
- Generated nature records preserve source symbols, numeric nature ids, source file/line references, UTF-8 display names, `statUp`/`statDown` constants, neutral-nature status, Pokeblock animation constants, Battle Palace cumulative percent data, flavor text ids, smokescreen target preferences, and nature girl message symbols.
- `BattleEngine` consumes generated `stat_up`/`stat_down` fields for the source `ModifyStatByNature` rule: HP is never modified, neutral natures have no effect because `statUp == statDown`, increased stats use integer `stat * 110 / 100`, and decreased stats use integer `stat * 90 / 100`.
- Personality-derived nature selection, hidden nature modifiers, mints, Pokeblock feeding animation, Battle Palace move-choice behavior, summary UI colors, and presentation details remain future source-traced systems.

## Generated Pokemon Evolutions Contract

- Pokemon evolution JSON is loaded through `DataRegistry` from the manifest `pokemon` entry with category `evolutions`.
- `DataRegistry.get_pokemon_data("evolutions")`, `get_evolutions_data`, `get_evolution_record`, `get_evolution_record_by_species_symbol`, `get_evolution_record_by_species_id`, `get_evolutions_for_species`, `get_pre_evolution_records_for_species`, `get_pre_evolution_records_for_species_symbol`, and `get_pre_evolution_records_for_species_id` are read-only accessors for generated evolution records and reverse lookup records.
- Generated evolution records preserve source species symbols/ids, source file/line references, raw `EVOLUTION(...)`/`CONDITIONS(...)` macro text, source order, evolution methods, method params, target species, additional conditions, defaulted condition args, typed condition args for species/items/moves/types/gender/time/weather/nature/region/map/map-section/counts, runtime modes, and runtime reference notes.
- Source order matters: `src/pokemon.c:GetEvolutionTargetSpecies` scans each species' evolution records in order and returns the first valid target for the requested evolution mode, while extra condition checks are handled by `DoesMonMeetAdditionalConditions`.
- `EvolutionEngine` is the first Godot runtime consumer for this data. It implements source-order target evaluation, Everstone/item-check behavior, level/trade/item/battle/overworld/script-trigger mode filtering, broad `DoesMonMeetAdditionalConditions` checks, reverse pre-evolution lookup, and first-pass Shedinja split-evolution candidate reporting.
- Actual evolution execution, party/bag mutation, held/bag item consumption side effects, evolution-scene timing, cries, particles, UI, post-evolution move learning, and full GMax form exceptions remain future source-traced systems.

## Party Runtime Contract

- `PartyRuntime` is the first Godot-native domain boundary for carried Pokemon and should stay independent from party menu, summary UI, bag, save, capture, and storage presentation.
- Party Pokemon construction traces `src/pokemon.c:CreateMon`, `CreateBoxMon`, `CreateMonWithIVs`, `GiveBoxMonInitialMoveset`, `PokemonToBattleMon`, `GiveCapturedMonToPlayer`, and `CalculatePartyCount`, plus `include/constants/global.h` `PARTY_SIZE = 6` and `MAX_MON_MOVES = 4`.
- The first slice delegates stat and move initialization to `BattleEngine` so `CalculateMonStats`, generated natures, generated moves, and the rolling four-slot level-up move rule stay in one source-backed rules path.
- Runtime party records preserve personality, OT, nickname, language, friendship, held item, Pokeball, gender, ability slot, ability symbol, shiny status, met data, contest stats, HP/stat/move data, source trace, warnings, and unsupported notes as ordinary dictionaries until a fuller Godot Resource/save schema is designed.
- `GameState` currently stores the player party as a capped six-entry array. Party count follows the source contiguous-party rule by stopping at the first non-Pokemon or `SPECIES_NONE` entry.
- `PartyRuntime.build_battle_party` projects party records into battle-facing dictionaries for `BattleEngine`; `PartyRuntime.check_party_mon_evolution` passes party count, index, first live mon, and party data into `EvolutionEngine`.
- Random personality/IV generation, EXP growth, Pokerus, ribbons, PC storage, bag mutation, save serialization, party menu, Pokemon summary UI, capture flow, healing flow, and distinct source creation wrappers remain future source-traced work.

## Save Service Contract

- `SaveService` is the first Godot-native domain boundary for save snapshots and should stay independent from save menu UI, text windows, audio playback, and GBA flash-sector storage.
- Save behavior traces `data/scripts/std_msgbox.inc:Common_EventScript_SaveGame`, `data/text/save.inc` save message labels, `include/save.h` `SAVE_STATUS_*`/`SAVE_*`, `src/start_menu.c:SaveGame` and save callbacks, `src/save.c:TrySavingData`/`HandleSavingData`/`LoadGameSave`, and `src/load_save.c:CopyPartyAndObjectsToSave`/`CopyPartyAndObjectsFromSave`.
- The first slice writes normal JSON snapshots under `user://` with `schema`, `schema_version`, `save_status`, `save_counter`, `save_type`, `source_trace`, `save_flow`, and `unsupported` metadata rather than recreating GBA sector signatures, checksums, and rotating dual slots.
- Current snapshots cover `GameState` player name, gender, current map id, player grid position, flags, vars, player party, and party count. Loading applies those fields back through existing `GameState` setters where available.
- Current snapshots also cover `MapRuntime` current-map object-event runtime state through explicit MapRuntime export/apply APIs. Saved object state includes local ids, source local ids, active position, template position, movement type, facing, runtime hidden state, active state, and source hide-flag status; derived position/local-id indexes are rebuilt on import rather than serialized.
- Save-flow metadata preserves the source-visible message labels and defaults for confirm save, overwrite existing save, overwrite different save, saving, success, and error paths so later UI can reproduce source flow and timing without hardcoding labels again.
- Async save task timing, save window layout, text printer waits, YES/NO menu task, `SE_SAVE`/`SE_BOO`, cross-map object-event caches, bag/mail/options, Pokemon storage, special sectors, Hall of Fame, link save variants, save failure screen, and full continue-warp behavior remain future source-traced systems.

## Battle Runtime Contract

- `BattleEngine` is the first Godot-native domain boundary for battle rules and should stay independent from battle UI scenes.
- Battle Pokemon construction reads generated species, move, and nature records through `DataRegistry`, applies the source `CalculateMonStats` first-pass stat formula with IV/EV inputs, applies generated `gNaturesInfo` modifiers through the source `ModifyStatByNature` rule, and preserves unsupported notes for missing source-backed behavior.
- Trainer party construction reads generated trainer records through `DataRegistry` and follows the first-pass source shape of `CreateNPCTrainerPartyFromTrainer`: party order is preserved, explicit moves are assigned with `GetMovePP`-equivalent PP from generated move data, source default level-up moves use generated learnsets with the `GiveBoxMonInitialMoveset` rolling four-slot rule, and held item/ability/nature/friendship metadata is carried forward.
- Damage calculation currently covers ordinary damaging moves only. It follows the source base formula from `CalculateBaseDamage`, applies a deterministic caller-selected damage roll in the source 85-100 range, applies STAB and `gTypeEffectivenessTable` after the roll, keeps immunities at 0 damage, and clamps nonzero damaging results to at least 1.
- Battle turn execution currently decrements move PP, applies HP damage, marks fainting, and returns structured first-pass message events. Real source battle strings, text placeholders, animation scripts, sounds, move effects, accuracy, critical hits, abilities, items, status, weather, protection, AI, double battles, switching, rewards, and presentation timing remain future source-traced work.

## Generated Global Text Contract

- Global text JSON is loaded through `DataRegistry` from the manifest `texts` entry. The current generated category is `global`.
- `DataRegistry.get_text_data(category)`, `get_text_record(label, category)`, and `get_text_display_text(label, category)` are read-only accessors for generated text records.
- Generated global text records preserve the source label, source file, line, kind, part lines, raw text, UTF-8 `display_text`, and source encoding metadata.
- Normal `.string` records use the same charmap-backed encoding metadata as local map-script text: status, source bytes/hex, byte count, `$` terminator presence, control codes, placeholders, and warnings.
- `.braille` records preserve `brailleformat` values, `source_pointer_skip_bytes = 6`, source-derived braille bytes from `AsmFile::ReadBraille`, and combined source bytes containing the skipped header plus text bytes.
- Global text import currently evaluates the `IS_FRLG` branch in `data/text/pc_transfer.inc` as false for the Emerald target, traced to `include/constants/global.h`.
- Runtime systems resolve global text labels through this registry instead of reparsing source files. `ScriptVM` and `EventManager` use local text first, then registry-backed global text for message labels.

## Script Porting Rule

Event script, gameplay-system, and code-backed feature support should preserve the source game's visible behavior and rules as closely as practical while using Godot-native architecture.

For each script instruction/opcode, gameplay feature, source function, or code-backed system implemented in Godot:

- Trace the corresponding source implementation in the original repository, usually under `src/scrcmd.c`, `src/event_object_movement.c`, `src/field_control_avatar.c`, `src/fieldmap.c`, or adjacent field/event modules.
- Identify referenced resources and data tables before writing Godot behavior: text labels, movement labels, object graphics, flags, vars, sounds, fanfares, map layouts, metatile behaviors, door animations, warp targets, battle data, Pokemon data, item data, encounter data, and trainer data.
- Preserve presentation-facing interaction details, not only logical outcomes. This applies to every feature, script, and code path: waits, frame timing, movement pacing, UI/dialogue flow, animation order, audio cues, screen effects, and state changes should match source-visible behavior where practical while still using Godot-native animation/audio/state systems.
- Record unsupported or approximated behavior in importer/runtime reports instead of silently inventing semantics.
- Translate the behavior into Godot systems (`EventManager`, `ScriptVM`, `GameState`, `MapRuntime`, movement/presentation scenes) rather than copying C structure directly.
- Verify visible behavior against the source map/script context whenever possible.

GBA hardware-driven graphics and resource constraints are import details, not runtime design goals. Palette banks, 4bpp tile memory layout, metatile binary packing, map/block binary formats, images split into source `.bin` storage, and similar limitations should be decoded into normal Godot textures/data and should not force a runtime GBA graphics architecture unless a feature specifically needs that behavior. This same rule applies to every script command, gameplay feature, and code-backed system: match visible behavior, sequencing, timing, and rules, not platform storage or hardware workarounds.

# Decisions

## 2026-07-03 - Data-driven Godot rebuild

Decision: Treat `pokeemerald-expansion` as source data and behavioral reference, and rebuild runtime systems in Godot 4.7.

Reason: The source project is a GBA ROM hack base with C engine code, assembly, custom build tools, binary map/tile formats, and GBA-specific runtime assumptions. A direct compile-style port would couple Godot to the old platform model. A data-driven rebuild gives cleaner Godot architecture and allows incremental playable milestones.

## 2026-07-03 - Wiki and skill first

Decision: Establish a project wiki and Codex skill before implementing gameplay systems.

Reason: The port will span many sessions and many source formats. Durable project memory reduces rediscovery and lets future Q&A update the same shared facts, decisions, and roadmap.

## 2026-07-03 - Encoding-safe tooling and commits

Decision: Minimize PowerShell for script-like file processing and maintain the Godot project as a git repository with focused commits after completed changes.

Reason: The source project and future wiki/import outputs may contain Chinese text and custom encodings. Avoiding casual shell rewrites reduces encoding damage. Frequent commits make the port easier to review, bisect, and roll forward safely.

## 2026-07-03 - Preserve unpacked map-grid layers

Decision: Generated map JSON keeps both the original raw u16 map-grid values and unpacked metatile id, collision, and elevation grids.

Reason: The source `map.bin` does not store plain metatile ids. `include/global.fieldmap.h` defines each entry as 10 bits of metatile id, 2 bits of collision, and 4 bits of elevation. Keeping the raw and unpacked forms makes the first debug renderer simple while preserving data needed for later collision and movement behavior.

## 2026-07-03 - Bake palettes into generated images

Decision: Use GBA palette files only during import, then generate ordinary RGBA images for Godot runtime consumption.

Reason: Palette slots are a GBA hardware/runtime constraint. Godot does not need a runtime palette bank model for the first map renderer, and palette-baked textures are simpler to load, preview, export, and debug. The importer should still record enough source metadata to revisit special cases such as animated doors or layer splitting.

## 2026-07-03 - Use Porymap as a source-format reference

Decision: Treat Porymap as a reference for pokeemerald map, tileset, palette, and metatile editor semantics, not as an architecture model to copy into Godot.

Reason: Porymap is built to edit decomp project data in a Qt desktop workflow. The Godot port needs generated runtime assets and Godot-native systems, but Porymap's handling of source project context is useful for validating importer assumptions.

## 2026-07-04 - Centralize current-map queries in MapRuntime

Decision: Use a `MapRuntime` autoload as the first current-map query service for passability, bounds, collision, elevation, metatile ids, behavior, and layer type.

Reason: Player movement, NPC movement, event triggers, object interaction, warps, and future terrain effects all need the same map facts. Centralizing those queries keeps generated JSON parsing out of presentation scripts and lets richer movement rules grow without coupling them to `PlayerController`.

## 2026-07-04 - Use object-event placeholders before sprite import

Decision: Spawn generated `object_events` as lightweight placeholder nodes and use `MapRuntime` to make visible object-event cells block movement.

Reason: The first vertical slice needs map occupancy and event positions before the full overworld sprite pipeline is ready. Placeholders make source object data visible and testable without inventing final art or coupling movement to presentation nodes.

## 2026-07-04 - Add debug event dispatch before ScriptVM

Decision: Route `ui_accept` interaction through player facing direction, `MapRuntime.get_interaction_target`, and `EventManager` debug dialogue before implementing full event script parsing.

Reason: The vertical slice needs a testable object/sign/warp interaction path now, while real `.inc` script execution and text decoding require separate import work. A debug dispatcher keeps the boundary stable without pretending script semantics are already implemented.

## 2026-07-04 - Derive gameplay behavior from source C and resources

Decision: Implement Godot event script and gameplay behavior only after tracing the corresponding source C implementation and referenced resources. Treat GBA hardware graphics constraints as import-time decoding concerns instead of runtime architecture requirements.

Reason: Event scripts and gameplay systems encode behavior through engine commands, flags, vars, movement tables, text labels, object graphics, sounds, doors, field effects, warps, Pokemon data, item data, encounters, trainers, and battle rules. Guessing behavior from names would drift from the original project. Tracing source behavior first lets the Godot port remain modern internally while matching the source game's visible behavior and rules more closely. Palette banks, 4bpp tiles, binary metatiles, and packed map blocks exist because of GBA constraints and should be decoded into Godot-friendly assets/data rather than recreated as runtime limitations.

## 2026-07-04 - Generate script data before full ScriptVM

Decision: Convert map `scripts.inc` files into generated script JSON and use it for limited debug dialogue previews before implementing the full `ScriptVM`.

Reason: Script labels, text labels, movement labels, and instruction references are needed by interaction dispatch before complete opcode semantics exist. A generated data layer makes script references inspectable and testable while keeping real execution deferred until each command is traced to source C behavior and its referenced resources.

## 2026-07-04 - Start ScriptVM with the traced dialogue path

Decision: Introduce `ScriptVM` as an autoload and route object/BG dialogue interactions through it, starting with source-derived `msgbox` expansion and synchronous dialogue-result execution.

Reason: `msgbox` in the source is a macro that loads a text pointer and calls a standard script from `gStdScripts`. Implementing that path in the VM preserves the real script structure better than keeping ad hoc EventManager previews. The first implementation records wait/lock/facing effects instead of pretending object freezing, facing animation, and asynchronous UI continuation already exist.

## 2026-07-04 - Treat movement commands as VM effects before animation

Decision: Add first-pass `applymovement`/`waitmovement` support to `ScriptVM` as structured movement-effect results, not as immediate scene-node movement or map-state mutation.

Reason: Source `applymovement` starts an object movement script through `ScriptMovement_StartObjectMovementScript`, while `waitmovement` installs a native wait for the current moving object target. Godot does not yet have the equivalent object movement task queue, animation layer, or object freeze/unfreeze integration. Recording target local ids, movement labels, decoded steps, net deltas, final facing, and resolved wait targets preserves script semantics now and gives the future animation system a stable contract to consume.

## 2026-07-04 - Apply movement effects through MapRuntime

Decision: Consume `ScriptVM` movement-effect results in `EventManager.dispatch_interaction` by fast-forwarding object-event and player logical positions through `MapRuntime`, while keeping preview calls read-only.

Reason: The first script VM movement slice proved movement decoding but did not affect runtime state. Applying net deltas through `MapRuntime` gives the current vertical slice observable object/player position changes and keeps occupancy indexes consistent without coupling script interpretation to scene nodes. It remains a temporary runtime approximation: step timing, collision handling per movement action, object movement task queues, and freeze/unfreeze semantics still belong in a later animation/movement system.

## 2026-07-04 - Dispatch normal coord events after player movement

Decision: Index generated coordinate events in `MapRuntime`, resolve normal `var`/`var_value` triggers by x/y/elevation against `GameState`, and dispatch matched coord events through `EventManager` after the player completes a tile move.

Reason: Source `field_control_avatar.c` checks coordinate events first in the step-based script chain after a player step. The first Godot slice needs LittlerootTown's NeedPokemon trigger to fire from actual movement, not only from smoke-test injection. Keeping lookup in `MapRuntime` and execution in `EventManager` preserves the Godot-native boundary while leaving weather, immediate coord scripts, warps, wild encounters, step-count scripts, and forced-movement chaining for later traced implementations.

## 2026-07-04 - Apply object script effects through MapRuntime

Decision: Represent `setobjectxy`, `setobjectxyperm`, `setobjectmovementtype`, `showobject`, `hideobject`, `addobject`, and `removeobject` as `ScriptVM` object-effect results, then apply them through `MapRuntime` during real interaction dispatch while keeping script previews read-only.

Reason: The traced source commands mutate object event runtime state, object templates, and object visibility flags through field-event systems rather than through dialogue dispatch itself. Applying the effects in `MapRuntime` keeps object occupancy and local-id lookup consistent in the Godot runtime, while preserving a future path for real sprite reloads, object task queues, and save persistence.

## 2026-07-04 - Store player gender in GameState

Decision: Store player gender on `GameState` and implement `checkplayergender` in `ScriptVM` by copying that value into `VAR_RESULT` as source-compatible `MALE`/`FEMALE` constants.

Reason: Source `ScrCmd_checkplayergender` only copies `gSaveBlock2Ptr->playerGender` into `gSpecialVar_Result`, and `MALE`/`FEMALE` are defined as 0/1 in `include/constants/global.h`. Keeping gender in `GameState` matches the source save-profile boundary and lets existing VM branch handling drive gendered scripts without coupling the opcode to presentation or object graphics.

## 2026-07-04 - Keep GBA constraints out of gameplay runtime

Decision: Apply the import-time-only hardware constraint rule to gameplay features too: preserve source-visible behavior and rules, but do not recreate GBA palette banks, tile memory, binary map/metatile packing, or other platform storage workarounds in the Godot runtime unless a gameplay rule specifically depends on them.

Reason: The port should feel like the source game, not like a GBA emulator embedded in Godot. Original C and data remain authoritative for behavior, but Godot can represent the same behavior with normal textures, structured data, resources, scenes, and animation systems.

## 2026-07-04 - Record door and delay commands as field effects

Decision: Add `ScriptVM.field_effects` for `delay`, `opendoor`, `closedoor`, and `waitdooranim` before implementing real door animation or asynchronous frame waits.

Reason: Source `ScrCmd_delay` sets a frame pause, while `ScrCmd_opendoor`/`ScrCmd_closedoor` resolve coordinates and start field door animation tasks that `ScrCmd_waitdooranim` waits on. Godot does not yet have the door TileMap animation or timing layer. Recording the resolved frame counts and door coordinates preserves script intent and lets scripts continue while leaving real presentation behavior for a later traced implementation.

## 2026-07-04 - Record audio, warp, waitstate, and player visibility intent

Decision: Add structured `ScriptVM` result channels for audio effects, transition effects, player effects, `waitstate`, and audio waits before implementing real sound playback, map loading, fades, or player presentation visibility.

Reason: Source `playse`, `playfanfare`, `waitfanfare`, `warp`, `warpsilent`, `waitstate`, and `hideplayer` request engine-side effects through sound, fanfare, warp, script-context, and object visibility systems. Godot should expose the same visible intent to future audio, transition, and presentation systems without recreating GBA task/hardware structure inside the script interpreter.

## 2026-07-04 - Use the generated manifest as the map registry

Decision: Make `DataRegistry` load generated maps, tilesets, and scripts through `data/generated/import_manifest.json` and require importers to merge manifest entries instead of replacing each same-type list.

Reason: Real warps need more than one generated map. A manifest-backed registry lets the runtime resolve destination map ids to Godot-friendly JSON and atlases without hardcoding every map path in autoload code.

## 2026-07-04 - Apply explicit-position script transitions first

Decision: Let `EventManager` consume `ScriptVM.transition_effects` only when the destination map has generated data and the script provides an explicit destination position.

Reason: LittlerootTown's truck intro uses `warpsilent MAP_LITTLEROOT_TOWN_BRENDANS_HOUSE_1F, 8, 8` and the May equivalent, so explicit-position transitions unlock a concrete vertical slice. Warp-id-only resolution needs destination warp lookup and source transition edge cases, so it remains a later traced implementation.

## 2026-07-04 - Resolve generated map warps by destination warp id

Decision: Let `MapRuntime` resolve generated warp events by x/y/elevation and let `EventManager` apply map warp transitions by loading the generated destination map and placing the player at `events.warp_events[warp_id]` in that destination map.

Reason: Source `field_control_avatar.c` checks coordinate events before step warps, handles front-cell door warps through the player's facing tile, and source `overworld.c` places the player from the destination map's warp event when a warp id is supplied. Applying that rule gives the Godot slice visible source-consistent house entry/exit behavior while keeping map loading, fade timing, and door presentation in Godot-native systems.

## 2026-07-04 - Preserve transition presentation details

Decision: Treat source-visible transition sequencing as required behavior, not polish. Map transitions should eventually reproduce door animation, player step-in movement, fade/black-screen ordering, frame waits, audio cues, and reveal timing in addition to changing the logical map and player position.

Reason: The goal is to match the source game's in-game feel and interaction details. Godot does not need GBA palette or binary storage limitations, but it does need the same player-facing timing and presentation results when those details are part of the original interaction.

## 2026-07-04 - Preserve visible behavior for all features

Decision: Apply the same fidelity rule to every script command, gameplay feature, source function, and code-backed system: trace source code and referenced resources, then reproduce source-visible behavior, ordering, waits, animation/audio/screen effects, UI flow, and gameplay results in Godot-native systems.

Reason: The port should not become a loose logical approximation. Modern Godot architecture is for implementation clarity and better asset/runtime representation, not permission to drop original script behavior, source code behavior, or interaction details players can see or feel.

## 2026-07-04 - Represent transition presentation as structured sequences first

Decision: Have `EventManager` emit a source-traced transition sequence contract before generated map transitions are applied, and let presentation systems consume that contract incrementally.

Reason: Map transitions include visible timing and order from source `DoWarp`, `DoDoorWarp`, door animation tables, normal walk timing, fades, audio cues, and exit tasks. Recording the sequence as data lets smoke tests lock those requirements before the final Godot animation, audio, and TileMap presentation systems exist.

## 2026-07-04 - Preserve metatile behavior names in generated tilesets

Decision: Parse `include/constants/metatile_behaviors.h` during tileset export and store both numeric behavior ids and source `MB_*` names in generated tileset JSON.

Reason: Source gameplay code such as `SetUpWarpExitTask` branches through named metatile behavior helper functions, not through visually meaningful tile ids. Preserving names lets Godot runtime systems choose behavior from source-readable data while still consuming normal Godot-friendly generated maps and textures.

## 2026-07-04 - Resolve metatile labels through generated tilesets

Decision: Export source `METATILE_*` label ids into generated tileset JSON and let `ScriptVM` resolve `setmetatile` labels through that data, then apply the resulting current-map mutation through `MapRuntime`.

Reason: Source `ScrCmd_setmetatile` receives script arguments, resolves metatile ids and collision bits, adds source `MAP_OFFSET` internally, and updates the current map grid while preserving elevation bits. Godot should preserve that visible current-map behavior without hardcoding numeric metatile ids in scripts or mutating reproducible generated source data.

## 2026-07-04 - Defer transition map application during presentation

Decision: Let `Main` enable deferred transition application and let `TransitionSequencePlayer` apply the pending map change at the sequence `load_map` step.

Reason: Source door and warp transitions perform visible work before and after the actual map load, including player step-in, player hiding, fade order, and destination exit movement. Deferring the runtime map switch lets the Godot presentation layer preserve that order while keeping `EventManager` able to apply transitions immediately for headless/domain tests when no presenter is configured.

## 2026-07-04 - Bake door animation frames into Godot textures

Decision: Parse source door animation tables during tileset export, bake supported used door animation strips into normal RGBA frame atlases, and let transition presentation play those frames as map overlays.

Reason: The source `field_door.c` tables define visible behavior: metatile labels, animation graphics, palette slots, frame order, frame duration, and sound category. Godot should preserve that player-facing sequence, but the GBA palette/tile-memory representation is only an import concern. Baking the already-palette-resolved frames into ordinary textures keeps the runtime Godot-native while matching the source door open/close timing and ordering.

## 2026-07-04 - Keep display text UTF-8 with charmap source metadata

Decision: Generated text records should keep Godot-facing UTF-8 `display_text` while also storing source `charmap.txt` byte metadata, control codes, placeholders, terminator state, and warnings.

Reason: The source project's charmap is required to verify that script text still maps to the original byte stream, including Chinese characters and control codes. Godot does not need to render through the GBA text encoding at runtime. Splitting display text from source-byte metadata preserves source compatibility and debugging value without importing GBA text storage constraints into the runtime UI.

## 2026-07-04 - Export global text for the Emerald target branch

Decision: Export global `data/text/*.inc` labels for the Emerald target, evaluating the current `IS_FRLG` text branches as false, and preserve `.braille` labels with their source `brailleformat` header plus source-derived braille bytes.

Reason: The local source target defines `IS_FRLG 0` for Emerald in `include/constants/global.h`; including both branches would create text that the source build would never show. Braille text is also player-visible data, but source `ScrCmd_braillemessage` intentionally skips the first 6 `brailleformat` bytes before expanding the string, so Godot needs both the skipped header and the resulting text bytes as generated metadata.

## 2026-07-04 - Resolve script text from local then global records

Decision: `ScriptVM` and `EventManager` should resolve message text labels from local generated map-script records first, then from global generated text records through `DataRegistry`.

Reason: Source `ScrCmd_message` reads a text pointer and shows it with `ShowFieldMessage`; the pointer can reference map-local text or global labels such as `gText_ConfirmSave`. Keeping local records first preserves map override behavior, while the global fallback lets Godot scripts use the same label space without reparsing source files at runtime.

## 2026-07-04 - Record yes/no UI waits instead of guessing choices

Decision: Implement `MSGBOX_YESNO` and direct `yesnobox` as structured `ScriptVM.ui_effects` that can stop with `status = waiting_for_ui` unless a test/UI context explicitly supplies `YES`, `NO`, or `B`.

Reason: Source `Std_MsgboxYesNo` calls `message NULL`, `waitmessage`, then `yesnobox 20, 8`; `ScrCmd_yesnobox` calls `ScriptMenu_YesNo`, which stops the script context while the menu task waits for input. `ScriptMenu_YesNo` initializes `VAR_RESULT` to `0xFF`, uses the default YES/NO menu position, defaults to `YES`, and treats `B` as `NO`. Godot should preserve that visible wait and branch behavior rather than auto-selecting an answer inside the VM.

## 2026-07-04 - Expand string-var placeholders at message execution

Decision: Let `ScriptVM` message results expose the source-visible expanded text while also preserving `unexpanded_text`, per-placeholder substitution metadata, and current VM string vars.

Reason: Source field messages call `StringExpandPlaceholders` before drawing text, and first-slice scripts use `special` functions such as `GetPlayerBigGuyGirlString` and `GetRivalSonDaughterString` to populate `gStringVar1` immediately before showing dialogue. Godot UI should display the same expanded wording, but keeping the unexpanded source text and substitutions makes later placeholder coverage, debugging, and source-fidelity checks explicit.

## 2026-07-04 - Expand player placeholders from GameState

Decision: Store the current player name in `GameState` and let `ScriptVM` expand source `{PLAYER}` and `{KUN}` placeholders during message execution alongside string vars.

Reason: Source `StringExpandPlaceholders` maps `{PLAYER}` to `gSaveBlock2Ptr->playerName` and `{KUN}` to the gendered Kun/Chan text entries. In this Chinese source both Kun/Chan entries are empty, so Godot should preserve the empty visible result instead of inventing an honorific. The current `"玩家"` default is a temporary debug fallback until the real new-game naming flow and preset-name behavior are ported.

## 2026-07-04 - Derive Emerald rival placeholder from player gender

Decision: Expand `{RIVAL}` in `ScriptVM` as `小遥` for a male player and `小悠` for a female player for the current Emerald target.

Reason: Source `ExpandPlaceholder_RivalName` only reads a custom `gSaveBlock1Ptr->rivalName` inside the `IS_FRLG` branch. The current source defines `IS_FRLG = 0`, so Emerald falls back to `gText_ExpandedPlaceholder_May` or `gText_ExpandedPlaceholder_Brendan` based on `gSaveBlock2Ptr->playerGender`.

## 2026-07-04 - Represent runtime text controls as message metadata

Decision: Parse source text control tokens in `ScriptVM` after placeholder expansion, remove the non-glyph controls from visible message `text`, and preserve them as structured `text_controls` metadata for the dialogue renderer.

Reason: Source `src/text.c` treats `EXT_CTRL_CODE_COLOR`, `EXT_CTRL_CODE_SHADOW`, `EXT_CTRL_CODE_FONT`, `EXT_CTRL_CODE_PAUSE`, and `EXT_CTRL_CODE_PAUSE_UNTIL_PRESS` as renderer commands, not printable characters, while `src/string_util.c:GetExtCtrlCodeLength` defines their byte lengths for string traversal. Godot UI should display the same glyph text while keeping enough source-backed metadata to reproduce colors, font changes, pauses, and button waits later.

## 2026-07-04 - Preserve battle-message token provenance

Decision: Expand `{B_PC_CREATOR_NAME}` in runtime message text with explicit `BattleStringExpandPlaceholders` provenance and a `value_key` showing the chosen source branch.

Reason: `{B_PC_CREATOR_NAME}` is encoded as `B_TXT_PC_CREATOR_NAME = 0x27` in the battle-message placeholder table, not as a normal `StringExpandPlaceholders` id. Source `battle_message.c` selects Someone's, Lanette's, or Bill's PC creator text from `FLAG_SYS_PC_LANETTE` and the `IS_FRLG` branch. Recording that provenance keeps the Godot text path source-faithful while still letting the visible message text expand cleanly.

## 2026-07-04 - Dispatch map header scripts through EventManager

Decision: Centralize generated map header script lifecycle dispatch in `EventManager.run_map_script_type`, starting with automatic `MAP_SCRIPT_ON_LOAD` during initial and transition map loads.

Reason: Source `InitMap` loads the layout before calling `RunOnLoadMapScript`, and `RunOnLoadMapScript` delegates to `MapHeaderRunScriptType` to run the first matching map-script table entry immediately. Keeping that lifecycle in `EventManager` lets Godot reuse the same `ScriptVM` and `MapRuntime` effect application path for startup, immediate transitions, and deferred presentation loads without coupling map rendering or transition animation code to script interpretation.

## 2026-07-04 - Run OnTransition before OnLoad during map loads

Decision: Add `EventManager.run_map_load_scripts` as the source-ordered map-load lifecycle wrapper: run `MAP_SCRIPT_ON_TRANSITION`, sync only the affected object-template positions into current runtime object events, then run `MAP_SCRIPT_ON_LOAD`.

Reason: Source `LoadMapFromWarp` and `LoadMapFromCameraTransition` load map data and object templates, call `RunOnTransitionMapScript`, and only then call `InitMap`, which runs `RunOnLoadMapScript`. Commands such as `setobjectxyperm` should not generally teleport an active object during normal dispatch, but during map load they change templates before objects become visible. A targeted loading-time sync preserves that source-visible behavior without changing the normal script-command semantics.

## 2026-07-04 - Evaluate OnFrame map-script tables separately

Decision: Model `MAP_SCRIPT_ON_FRAME_TABLE` as a separate `EventManager.try_run_on_frame_map_script` table evaluator instead of treating it like a direct map-header script entry.

Reason: Source `MAP_SCRIPT_ON_FRAME_TABLE` points to a `map_script_2` table scanned by `MapHeaderCheckScriptTable`: each row compares two `VarGet` values and starts the first non-no-effect script through the global script context. Direct lifecycle scripts use `MapHeaderRunScriptType` and run immediately. Keeping OnFrame as a table evaluator preserves the source behavior while leaving automatic field-input-loop dispatch, async waits, resume scripts, and dive/step/warp ordering for a later traced runtime pass.

## 2026-07-04 - Dispatch OnFrame before player input

Decision: Wire `MAP_SCRIPT_ON_FRAME_TABLE` dispatch into the Godot field-input path through a `PlayerController` precheck installed by `Main`, and consume that frame when a table entry starts a script.

Reason: Source `ProcessPlayerFieldInput` calls `TryRunOnFrameMapScript()` before later field-input actions such as dive checks, step-based scripts, wild encounters, and player stepping. Returning true locks field controls for that frame. Godot should preserve that visible ordering for scripts like the Brendan/May moving-in intro instead of waiting for explicit interaction or running OnFrame after movement.

## 2026-07-04 - Export shared script bundles by label namespace

Decision: Export common include files such as `data/scripts/movement.inc` and `data/scripts/players_house.inc` as named shared script bundles, and let `ScriptVM` resolve script, movement, and script-local text labels from the current map first, then from the global generated script namespace.

Reason: Source `data/event_scripts.s` includes many shared script files into one assembler-visible label space, so map-local script JSON alone cannot execute branches such as Brendan/May house intro into `PlayersHouse_1F_EventScript_EnterHouseMovingIn`. A shared bundle keeps generated data reproducible and avoids duplicating common labels into every map while preserving source-style label visibility.

## 2026-07-04 - Resolve movement targets through source VarGet semantics

Decision: Treat `applymovement` and `waitmovement` target operands as source `VarGet` inputs, preserving raw targets and resolved local ids in VM results.

Reason: Source `ScrCmd_applymovement` and `ScrCmd_waitmovement` read a halfword and pass it through `VarGet`. That means object local-id constants become numeric source ids, `VAR_*` operands can point at a runtime object id, `LOCALID_PLAYER` stays the player target, and `waitmovement 0` waits on the current moving target. Matching this prevents scripts like the shared PlayersHouse intro from moving the wrong object in Godot.

## 2026-07-04 - Export traceable species data before expanding dense macros

Decision: Add a first Pokemon species importer that fully structures explicit species initializers, but preserves dense macro-generated initializers as partial records with warnings until their macro definitions and referenced resources are traced.

Reason: `src/data/pokemon/species_info.h` mixes ordinary struct initializers with C macros that generate many related form records. The Godot data layer should expose all active species ids now, but it should not invent values for macro-expanded forms before the source macro semantics are understood. Partial records keep coverage visible and unblock registry access while preserving a clear next step for source-faithful macro expansion.

## 2026-07-04 - Export move definitions as source-traceable data

Decision: Add a first move importer that structures `src/data/moves_info.h` into generated move records while preserving source symbols for effects, arguments, additional effects, contest data, and battle animation scripts.

Reason: Battle move behavior is spread across data tables, constants, battle scripts, animation resources, and C command/effect implementations. The Godot runtime needs move ids and core data now, but it should not guess effect semantics from names. Generated move JSON gives later battle, contest, UI, and animation systems a source-backed contract while keeping those systems responsible for tracing and reproducing source-visible behavior before implementation.

## 2026-07-04 - Export ability definitions as source-traceable data

Decision: Add a first ability importer that structures `src/data/abilities.h` into generated ability records while preserving `struct AbilityInfo` fields, active config expressions, source text, AI ratings, and ability flags.

Reason: Ability behavior is shared by battle AI, copying/swapping/suppressing/overwriting rules, summary/Pokedex UI, ability popups, overworld effects, and future battle systems. The Godot runtime needs stable ability ids and data now, but it should not infer behavior from names. Generated ability JSON gives later systems a source-backed contract while keeping actual ability behavior responsible for tracing the matching source C and referenced resources first.

## 2026-07-04 - Export item definitions as source-traceable data

Decision: Add a first item importer that structures `src/data/items.h` and `src/data/pokemon/item_effects.h` into generated item records and item effect byte-array records while preserving `struct ItemInfo` fields, source text, active config expressions, TM/HM aliases, source constants, defaulted fields, and behavior reference files.

Reason: Item behavior spans bag menus, shops, field-use functions, berries, mail, Pokeballs, held-item effects, battle items, icons, audio, and source special cases such as Enigma Berry save data. The Godot runtime needs stable item ids and inspectable data now, but it should not infer behavior from item names or categories. Generated item JSON gives later systems a source-backed contract while keeping actual item behavior responsible for tracing the matching source C and referenced resources first.

## 2026-07-04 - Export wild encounters as source-traceable data

Decision: Add a first wild encounter importer that structures `src/data/wild_encounters.json` into generated encounter records while preserving generated-header semantics, active time-of-day config, reconstructed map group/number values, source species ids, slot probability tables, fishing rod groups, and the Altering Cave table-selection special case.

Reason: Wild encounter runtime behavior spans field input ordering, metatile behavior, encounter-rate rolls, Repel, abilities, surfing/fishing state, Sweet Scent, DexNav, outbreaks, Feebas, roamers, Battle Pike/Pyramid, and battle setup. The Godot runtime needs stable encounter tables now, but it should not infer overworld encounter behavior from data alone. Generated encounter JSON gives later systems a source-backed contract while keeping actual encounter execution responsible for tracing the matching source C and referenced resources first.

## 2026-07-04 - Start battles as a domain-only rules engine

Decision: Introduce `BattleEngine` as a Godot autoload for battle rules before building battle UI, starting with generated Pokemon/trainer party construction, source formula ordinary damage, type effectiveness, PP/HP/fainting, and structured first-pass battle messages.

Reason: Battle behavior will eventually touch UI, animations, sounds, text placeholders, AI, abilities, items, weather, status, trainer rewards, and many move effects. A domain-only rules layer lets those rules be smoke-tested against generated source data without coupling the first implementation to presentation scenes or guessing unsupported source behavior.

## 2026-07-04 - Export level-up learnsets for source default trainer moves

Decision: Add generated Pokemon level-up learnset data and use it in `BattleEngine` to assign omitted trainer Pokemon moves with the source `GiveBoxMonInitialMoveset` four-slot selection rule.

Reason: Source trainer party data often omits explicit moves and relies on `CustomTrainerPartyAssignMoves` calling Pokemon default moveset logic. Reproducing that behavior requires the active generation learnset table, not a guessed fallback. Keeping learnsets as generated data also prepares later move-learning, evolution, relearning, UI, and compatibility systems while preserving source-visible trainer battles.

## 2026-07-04 - Export natures before expanding battle stats

Decision: Add generated Pokemon nature data from `src/pokemon.c:gNaturesInfo` and make `BattleEngine` consume it for source `ModifyStatByNature` stat modifiers.

Reason: The first battle prototype previously treated non-neutral natures as unsupported because the source `gNaturesInfo` table was not generated yet. Exporting natures keeps the stat formula source-backed, preserves future Pokeblock/Battle Palace/UI fields, and avoids guessing stat modifiers from hardcoded nature names.

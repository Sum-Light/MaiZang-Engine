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

Decision: Apply the same fidelity rule to every script command, gameplay feature, and code-backed system: trace source code and referenced resources, then reproduce source-visible behavior, ordering, waits, animation/audio/screen effects, UI flow, and gameplay results in Godot-native systems.

Reason: The port should not become a loose logical approximation. Modern Godot architecture is for implementation clarity and better asset/runtime representation, not permission to drop the original interaction details players can see or feel.

## 2026-07-04 - Represent transition presentation as structured sequences first

Decision: Have `EventManager` emit a source-traced transition sequence contract before generated map transitions are applied, and let presentation systems consume that contract incrementally.

Reason: Map transitions include visible timing and order from source `DoWarp`, `DoDoorWarp`, door animation tables, normal walk timing, fades, audio cues, and exit tasks. Recording the sequence as data lets smoke tests lock those requirements before the final Godot animation, audio, and TileMap presentation systems exist.

## 2026-07-04 - Preserve metatile behavior names in generated tilesets

Decision: Parse `include/constants/metatile_behaviors.h` during tileset export and store both numeric behavior ids and source `MB_*` names in generated tileset JSON.

Reason: Source gameplay code such as `SetUpWarpExitTask` branches through named metatile behavior helper functions, not through visually meaningful tile ids. Preserving names lets Godot runtime systems choose behavior from source-readable data while still consuming normal Godot-friendly generated maps and textures.

## 2026-07-04 - Defer transition map application during presentation

Decision: Let `Main` enable deferred transition application and let `TransitionSequencePlayer` apply the pending map change at the sequence `load_map` step.

Reason: Source door and warp transitions perform visible work before and after the actual map load, including player step-in, player hiding, fade order, and destination exit movement. Deferring the runtime map switch lets the Godot presentation layer preserve that order while keeping `EventManager` able to apply transitions immediately for headless/domain tests when no presenter is configured.

## 2026-07-04 - Bake door animation frames into Godot textures

Decision: Parse source door animation tables during tileset export, bake supported used door animation strips into normal RGBA frame atlases, and let transition presentation play those frames as map overlays.

Reason: The source `field_door.c` tables define visible behavior: metatile labels, animation graphics, palette slots, frame order, frame duration, and sound category. Godot should preserve that player-facing sequence, but the GBA palette/tile-memory representation is only an import concern. Baking the already-palette-resolved frames into ordinary textures keeps the runtime Godot-native while matching the source door open/close timing and ordering.

## 2026-07-04 - Keep display text UTF-8 with charmap source metadata

Decision: Generated text records should keep Godot-facing UTF-8 `display_text` while also storing source `charmap.txt` byte metadata, control codes, placeholders, terminator state, and warnings.

Reason: The source project's charmap is required to verify that script text still maps to the original byte stream, including Chinese characters and control codes. Godot does not need to render through the GBA text encoding at runtime. Splitting display text from source-byte metadata preserves source compatibility and debugging value without importing GBA text storage constraints into the runtime UI.

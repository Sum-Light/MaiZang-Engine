# Overworld Parity Todo

Goal: reproduce the source `pokeemerald-expansion` map/overworld experience in Godot with source-equivalent logic, timing, visible layering, object-event animation, map mutations, and generated assets. Any approximation must remain explicit in generated data, runtime summaries, or smoke-test metadata.

## Current Snapshot

- `DebugMapPlane` still renders a flattened generated metatile atlas. Real source BG layer ordering and player/object interleaving are not source-equivalent yet.
- `MapRuntime` exposes generated metatile id, collision, elevation, behavior, layer type, object/BG/warp/coord events, door-animation metadata, and first-pass `setmetatile` mutation.
- `MapRuntime.can_enter_cell` is still a first-pass rule: bounds, object occupancy, and `collision == 0`. Source elevation, direction-specific metatile behavior, forced movement, bridge/surf/bike/stair rules, and player-avatar state are pending.
- Door transitions use source-ordered sequence metadata and generated door atlases, but `TransitionSequencePlayer` draws overlay frames rather than mutating the active rendered metatile/layers like `field_door.c`.
- Player Brendan/May normal walk and turn-in-place now use source-traced frame timing. Running, fast walk, bike, surf, underwater, fishing, watering, field move, spin, slide, current, and other avatar states are pending.
- Object events currently spawn as static source-backed sprites for the first small set of imported graphics. Full movement type callbacks, held movement actions, per-frame animation, freezing, collision, subpriority, shadows, reflections, and camera spawn/despawn behavior are pending.
- `ScriptVM` can emit first-pass movement, field, object, transition, and audio effect records. `applymovement`, `waitmovement`, `delay`, `waitdooranim`, and related waits are not true async source tasks yet.
- Tileset import bakes palette RGBA output and door atlases for used doors. Source tileset animation callbacks, per-layer tiles, and complete door graphics tables are pending.

## Source Files Audited

- Map loading, callbacks, and transition setup: `src/overworld.c`
- Field input and player-step event order: `src/field_control_avatar.c`
- Backup map, border, connection, map-grid, collision/elevation/layer access: `src/fieldmap.c`, `include/global.fieldmap.h`, `include/fieldmap.h`
- Metatile behavior groups and constants: `src/metatile_behavior.c`, `include/constants/metatile_behaviors.h`
- Player avatar states, collision, forced movement, walk/run/bike/surf states: `src/field_player_avatar.c`
- Object-event lifecycle, movement callbacks, movement actions, timing, spawn/despawn, freezing: `src/event_object_movement.c`, `src/script_movement.c`, `src/event_object_lock.c`, `src/data/object_events/*.h`
- Door animation task, frame tables, graphics/palette tables, sounds: `src/field_door.c`
- Tileset animation callbacks and frame-copy timing: `src/tileset_anims.c`, `include/tileset_anims.h`, `src/data/tilesets/headers.h`
- Script opcodes affecting overworld presentation and map state: `src/scrcmd.c`

## Detailed Todo List

Use these as executable checkboxes. A task is not complete until the source path is traced, unsupported behavior is explicit, generated/runtime data is reproducible, and a focused smoke or import report covers the new behavior.

### 0. Parity Control

- [x] Create `data/generated/overworld/parity_matrix.json` or an equivalent wiki table mapping source functions/tables to Godot owners.
- [x] Add matrix columns for source path, source symbol, Godot importer, Godot runtime owner, Godot presentation owner, status, test/report, and notes.
- [x] Use status values only from `ported`, `first_pass`, `metadata_only`, `unsupported`, and `untraced`.
- [x] Add a stable unsupported-code naming scheme such as `layer_split_pending`, `door_overlay_not_source_equivalent`, and `object_movement_task_pending`.
- [x] Add a generated overworld import summary that counts maps, layouts, tilesets, scripts, door anims, tileset anims, object graphics, movement actions, warnings, and unsupported entries.
- [x] Add a runtime debug dump for the current map: map id, layout id, tileset pair, map type, weather, music, active scripts, object count, warp count, coord event count, and unsupported runtime features.
- [x] Keep `wiki/overworld-parity-todo.md` as the top-level checklist and append session-log entries after each completed slice.

### 1. Source Audit Baseline

- [x] Trace `src/overworld.c` map load entry points: `LoadMapFromWarp`, `LoadMapFromCameraTransition`, `InitMap`, `RunOnTransitionMapScript`, `RunOnLoadMapScript`, and field callback setup.
- [x] Trace `src/fieldmap.c` map-grid access: backup map layout, `MAP_OFFSET`, borders, connections, `MapGridGet*`, `MapGridSetMetatileIdAt`, save/load map view, and camera movement.
- [x] Trace `include/global.fieldmap.h` layer constants and confirm exact layer assignment rules for normal, covered, and split metatiles.
- [x] Trace `src/field_control_avatar.c` field-input ordering, interaction ordering, step-script ordering, door warp checks, arrow warps, and metatile-script interactions.
- [x] Trace `src/field_player_avatar.c` player avatar state machine, collision checks, bike/surf/underwater states, forced movement, and avatar graphics transitions.
- [x] Trace `src/event_object_movement.c` object-event initialization, spawn/despawn, movement type callbacks, movement actions, animation timing, collision, elevation, subpriority, shadows, and reflection hooks.
- [ ] Trace `src/script_movement.c` applymovement task behavior, waitmovement behavior, simultaneous movements, and target resolution.
- [ ] Trace `src/event_object_lock.c` object freezing, selected-object locking, player/object facing, and lock release behavior.
- [ ] Trace `src/field_door.c` door graphics tables, palette tables, frame tables, metatile mutation, sounds, task timing, and multi-door cases.
- [ ] Trace `src/tileset_anims.c`, `include/tileset_anims.h`, and `src/data/tilesets/headers.h` for callback binding, counters, copy regions, and map-load initialization.
- [ ] Trace `src/metatile_behavior.c` and `include/constants/metatile_behaviors.h` for every `MetatileBehavior_Is*` group needed by movement, encounters, interaction, terrain effects, and transitions.
- [ ] Trace `src/scrcmd.c` overworld-affecting commands, especially waits, doors, map mutation, warps, weather, fades, audio, field effects, object commands, and trainer flow.

### 2. Full Map Import

- [ ] Extend the map import entry point to batch over all source `data/maps/*/map.json` records.
- [ ] Export every layout referenced by `data/layouts/layouts.json`.
- [ ] Export every `map.bin` raw u16 grid, metatile id grid, collision grid, elevation grid, width, height, and source layout symbol.
- [ ] Export every `border.bin` and preserve `GetBorderBlockAt` fallback metadata.
- [ ] Export map connections with direction, offset, target map id, target map section, and source map-group/map-num metadata.
- [ ] Export map header metadata: map type, layout id, music, weather, map section, battle type, allow cycling, allow escaping, allow running, show map name, floor number, and cave/flash flags.
- [ ] Export object events with local id, graphics id, movement type, movement range, trainer metadata, flag id, script label, coordinate, elevation, and generated source-order index.
- [ ] Export warp events with source x/y/elevation, destination map, destination warp id, and source-order index.
- [ ] Export coord events with trigger var, trigger value, elevation, script label, and source-order index.
- [ ] Export BG/sign events with kind, coordinates, elevation, script/item/hidden-item metadata, and source-order index.
- [ ] Validate every exported script label against generated script bundles and report missing labels.
- [ ] Validate every warp destination map and warp id and report invalid or not-yet-generated targets.
- [ ] Validate every connection target map and offset and report missing targets.
- [ ] Validate duplicate object local ids per map and source numeric local-id aliases.
- [ ] Add an import smoke that asserts all source maps either export cleanly or emit deliberate unsupported records.

### 3. Script And Text Import For Overworld

- [ ] Batch-export all map `scripts.inc` files, not only the first-slice maps.
- [ ] Preserve source labels, instruction order, macro-expanded op names, raw operands, source line numbers where available, and shared-script references.
- [ ] Export all movement labels referenced by map scripts and shared scripts.
- [ ] Export all local text labels with charmap metadata, control codes, placeholders, byte counts, and terminators.
- [ ] Resolve shared script includes used by maps, including player house, rival graphics, movement, and common event scripts.
- [ ] Report orphan instructions, unknown macros, unresolved labels, missing text labels, and unsupported directives per script file.
- [ ] Add a script import coverage report by map id with script count, movement count, text count, unsupported opcode count, and missing reference count.

### 4. Tileset And Metatile Asset Import

- [ ] Export every primary and secondary tileset header from `src/data/tilesets/headers.h`.
- [ ] Export tileset image provenance for `tiles.png`, `metatiles.bin`, `metatile_attributes.bin`, palettes, animation images, and callback symbols.
- [ ] Preserve global palette-slot mapping as import metadata while baking runtime RGBA assets.
- [ ] Decode every 8x8 tile entry inside each metatile: tile id, palette, hflip, vflip, source tileset, and source layer slot.
- [ ] Export metatile attributes: behavior id, behavior name, collision, elevation, terrain type if source exposes it, encounter affordances, and layer type.
- [ ] Export `METATILE_*` labels and reverse lookup tables per tileset pair.
- [ ] Detect and report metatile ids referenced by maps but absent from the tileset pair.
- [ ] Detect and report tile ids referenced by metatiles but absent from source tileset images.
- [ ] Keep the current flattened atlas as a temporary debug artifact only, with metadata marking it non-equivalent for runtime layering.

### 5. Layer-Aware Map Rendering

- [ ] Design a Godot map-rendering owner to replace or wrap `DebugMapPlane` for source layer parity.
- [ ] Export or build separate render data for bottom, middle, and top layer tiles.
- [ ] Implement `METATILE_LAYER_TYPE_NORMAL`: source bottom/middle/top placement according to `global.fieldmap.h` comments and source tile slots.
- [ ] Implement `METATILE_LAYER_TYPE_COVERED`.
- [ ] Implement `METATILE_LAYER_TYPE_SPLIT`.
- [ ] Render player and object sprites at the correct visual depth between map layers.
- [ ] Implement y-sort or source subpriority rules so objects behind/under top tiles draw correctly.
- [ ] Add a layer debug view that can show bottom/middle/top separately without mutating gameplay data.
- [ ] Make `setmetatile` update all affected layer data and renderer caches.
- [ ] Make map connection and border rendering use the same layer-aware path as in-bounds cells.
- [ ] Keep source collision/elevation queries independent from presentation-only layer toggles.
- [ ] Add screenshot or pixel checks for roofs, signs, grass cover, bridge-like metatiles, and indoor objects drawn under top layer.

### 6. Dynamic Metatile And Tileset Animations

- [ ] Parse each tileset callback symbol from the source tileset headers.
- [ ] Export callback-to-map metadata for primary and secondary tilesets.
- [ ] Trace General callback frames and copy regions.
- [ ] Trace Petalburg callback frames and copy regions.
- [ ] Trace remaining primary tileset callbacks.
- [ ] Trace remaining secondary tileset callbacks.
- [ ] Export animation image sources and generated RGBA frame strips.
- [ ] Export source frame durations, frame counters, wrap behavior, DMA/copy target tile ranges, and affected metatile/tile ids.
- [ ] Implement a runtime `TilesetAnimationPlayer` that initializes on map load.
- [ ] Support independent primary and secondary animation counters.
- [ ] Support pausing/resetting animations across map transitions according to source callbacks.
- [ ] Update renderer tile sources or atlas regions without rebuilding the full map every frame.
- [ ] Add tests for animated water, flowers, currents, lava, falls, sand/water edges, and any first-slice General/Petalburg animations.
- [ ] Add unsupported metadata for callbacks not yet rendered even if their source tilesets import successfully.

### 7. Door Animation And Door State

- [ ] Expand door resource parsing to every entry in `sDoorAnimGraphicsTable`.
- [ ] Export small door, big door, FRLG door, sliding door, arena door, and any expansion-specific variants.
- [ ] Export door size, metatile id, frame dimensions, palette ids, source graphics file, sound effect, open frame sequence, close frame sequence, and frame durations.
- [ ] Support size 1 and size 2 door graphics.
- [ ] Support missing/unused door resources as explicit skipped entries.
- [ ] Implement runtime door state storage by map cell and metatile id.
- [ ] Implement `FieldSetDoorOpened` by updating the actual rendered map state.
- [ ] Implement `FieldSetDoorClosed` by restoring the source closed door tiles.
- [ ] Implement `FieldAnimateDoorOpen` as a task/coroutine with source frame timing.
- [ ] Implement `FieldAnimateDoorClose` as a task/coroutine with source frame timing.
- [ ] Implement `FieldIsDoorAnimationRunning`.
- [ ] Route `ScriptVM` `opendoor`, `closedoor`, and `waitdooranim` into real door tasks instead of field-effect metadata only.
- [ ] Replace transition door overlay playback with door frame application in the layer-aware renderer.
- [ ] Preserve source door sound symbols and add real audio playback later when audio runtime exists.
- [ ] Handle non-animated doors, stairs, ladders, escalators, arrow warps, and multi-corridor door special cases separately from animated doors.
- [ ] Add tests for Littleroot house door, Birch lab door, door-open script command, door-close script command, `waitdooranim`, and door warp entry/exit order.

### 8. Map Grid, Connections, And Camera

- [ ] Model the source backup map buffer shape with `MAP_OFFSET`, border area, and visible camera area.
- [ ] Implement `SaveMapView` and `LoadSavedMapView` equivalents in Godot-native data.
- [ ] Implement `MoveMapViewToBackup` semantics for edge scrolling and connected-map streaming.
- [ ] Implement `CanCameraMoveInDirection` using source border/connection rules.
- [ ] Load connected map strips into the backup-map representation instead of final-position-only map swapping.
- [ ] Preserve source connection offsets for north/south/east/west maps.
- [ ] Spawn/despawn object events after camera updates, not only after full map load.
- [ ] Carry object-event state across connection seams when the source keeps them active.
- [ ] Update map music/weather/map popup behavior on connection transitions according to source.
- [ ] Add tests for Littleroot north Route101 connection, border fallback, edge step timing, and object spawn refresh after camera move.

### 9. Movement And Collision Rules

- [ ] Replace `MapRuntime.can_enter_cell` with a source-shaped collision service.
- [ ] Implement static metatile collision from collision bits.
- [ ] Implement elevation compatibility between player/object and target cell.
- [ ] Implement occupied object-event collision with source local-id exemptions.
- [ ] Implement player/object swap or ignore rules for special object states.
- [ ] Implement directional impassable metatiles.
- [ ] Implement ledge jump checks and blocked-direction behavior.
- [ ] Implement stairs and stair movement constraints.
- [ ] Implement bridge over/under behavior and elevation changes.
- [ ] Implement surfable water checks, underwater checks, waterfall, dive, and water-current movement.
- [ ] Implement no-running metatile behavior.
- [ ] Implement bike-specific collision and Acro/Mach exceptions.
- [ ] Implement forced movement tiles: ice, currents, spin tiles, slide tiles, muddy slope, secret-base mats, and arrows.
- [ ] Implement encounter-area classification from metatile behavior without duplicating EncounterEngine logic.
- [ ] Generate `MetatileBehavior_Is*` helper groups from source constants or maintain a traced Godot table with source references.
- [ ] Add tests for collision, elevation, object occupancy, ledges, surf/water, bridge, no-running, and forced movement.

### 10. Terrain And Field Effects

- [ ] Trace and import terrain effect entry points from source field-effect files.
- [ ] Implement tall grass visual cover and rustle timing.
- [ ] Implement long grass behavior.
- [ ] Implement water ripples, surf wake, puddles, and reflection triggers.
- [ ] Implement sand, ash, snow, and footprint effects where source maps use them.
- [ ] Implement bridge visibility/priority effects.
- [ ] Implement cracked floors and collapse/fragile tile state.
- [ ] Implement hot springs, muddy slopes, secret-base mats, and other special terrain effects.
- [ ] Route terrain effects through presentation contracts rather than embedding them in collision logic.
- [ ] Add tests that a completed player step emits the correct terrain effect request before/after source-ordered step scripts as appropriate.

### 11. Player Avatar Runtime

- [ ] Preserve normal on-foot walk and turn-in-place support as the current baseline.
- [ ] Add normal fast-walk and continuous fast-walk actions.
- [ ] Add running state, running input gate, no-running tiles, and running animation timing.
- [ ] Add Mach Bike avatar state and movement speed.
- [ ] Add Acro Bike avatar state, hop/wheelie behavior, and collision exceptions.
- [ ] Add surf avatar state and surfboard/water movement animation.
- [ ] Add underwater avatar state.
- [ ] Add fishing avatar state and rod animation hooks.
- [ ] Add watering avatar state.
- [ ] Add field-move avatar states and temporary graphics transitions.
- [ ] Add forced-movement player controller states for slide, current, spin, jump, fall, and stair movement.
- [ ] Preserve `gPlayerAvatar` flags, running state, tile transition state, prevent-step flag, gender-dependent graphics, and controller callback state.
- [ ] Keep OnFrame precheck before accept/movement input.
- [ ] Keep source first-press turn-in-place behavior across all valid movement states.
- [ ] Add tests for each player state transition and visible frame timing before marking it source-equivalent.

### 12. Object Event Asset Import

- [ ] Export all object-event graphics records from `src/data/object_events/object_event_graphics_info.h`.
- [ ] Export all pic tables from `object_event_pic_tables.h`.
- [ ] Export all graphics asset paths from `object_event_graphics.h`.
- [ ] Export all animation tables from `object_event_anims.h`.
- [ ] Export all movement type function table symbols from `movement_type_func_tables.h`.
- [ ] Export all movement action function table symbols from `movement_action_func_tables.h`.
- [ ] Decode palettes and make palette-index-0 transparency explicit for every sprite sheet.
- [ ] Export frame size, frame count, animation names, frame indices, frame durations, flip flags, and affine metadata.
- [ ] Export shadow size/type, reflection flags, track footprint flags, inanimate flags, and subsprite tables.
- [ ] Support variable graphics ids such as `OBJ_EVENT_GFX_VAR_0` through runtime var resolution.
- [ ] Report graphics entries that need special renderer handling, decompression, or source-only callbacks.
- [ ] Add an import smoke that counts all object graphics and verifies first-slice records still match Brendan/May/Boy1/Mom/Rival/Truck metadata.

### 13. Object Event Runtime

- [ ] Replace static `ObjectEventPlaceholder` nodes with an `ObjectEventRuntime` data model and a presentation node.
- [ ] Preserve source object event fields: active, local id, map id, current coords, previous coords, initial coords, range, movement type, trainer type/range, elevation, facing, graphics id, visibility flag, and movement/action state.
- [ ] Implement object-event spawn/despawn based on camera range and map view updates.
- [ ] Implement sprite animation playback from generated animation tables.
- [ ] Implement facing changes as visible animation updates.
- [ ] Implement movement type callbacks: none, look around, wander, face direction, rotate, walk sequence, copy player, invisible, berry tree, disguise, in-place walk/jog/run, follower, and other source table entries.
- [ ] Implement movement delay tables and random delay behavior.
- [ ] Implement held movement actions and per-action state machines.
- [ ] Implement `NpcTakeStep` timing and speed classes.
- [ ] Implement object event collision with player, map, and other objects.
- [ ] Implement object elevation, bridge behavior, subpriority, and y-sort.
- [ ] Implement object shadows and reflections as presentation effects.
- [ ] Implement freeze, unfreeze, lock selected object, release, faceplayer, and turnobject behavior.
- [ ] Make `setobjectxy`, `setobjectxyperm`, `setobjectmovementtype`, add/remove/show/hide mutate source-shaped object runtime state.
- [ ] Preserve current-map object state in `SaveService` and plan cross-map object caches.
- [ ] Add tests for static facing, random movement, scripted movement, freeze/lock, object collision, save/restore, and camera spawn/despawn.

### 14. Applymovement And Movement Scripts

- [ ] Replace movement-effect net-delta fast-forwarding with queued movement task execution.
- [ ] Resolve movement targets through source `VarGet` and local-id rules.
- [ ] Support `LOCALID_PLAYER`, `LOCALID_CAMERA`, `LOCALID_FOLLOWING_POKEMON`, and `LOCALID_NONE` semantics.
- [ ] Support simultaneous object movement tasks.
- [ ] Support player-targeted `applymovement` through the player avatar movement queue.
- [ ] Support camera-targeted movement where source scripts use it.
- [ ] Implement movement action opcodes for facing, walking, sliding, jumping, delays, lock/unlock animation, disable/restore animation, emotes, visibility, and affine actions.
- [ ] Implement `waitmovement` for a specific target.
- [ ] Implement `waitmovement 0` last-target semantics.
- [ ] Keep unsupported movement actions explicit in script VM results.
- [ ] Add tests using existing Littleroot/house movement labels and at least one shared movement script.

### 15. ScriptVM Async Execution

- [ ] Introduce resumable script context objects instead of one synchronous `run_script` result for live dispatch.
- [ ] Keep `get_script_preview` read-only and synchronous.
- [ ] Add a scheduler for script waits, movement waits, door waits, field-effect waits, UI waits, and audio waits.
- [ ] Implement `delay` as frame-based wait.
- [ ] Implement message wait and button wait with source text-printer integration later.
- [ ] Implement `yesnobox` wait/resume and `VAR_RESULT` mutation through real UI callbacks.
- [ ] Implement `waitstate` as source `ScriptContext_Enable` continuation behavior.
- [ ] Implement `waitfanfare` and `waitse` equivalents once audio runtime exists.
- [ ] Implement lock/release semantics through player/object-event runtime, not just effect records.
- [ ] Add tests for scripts that suspend and resume across movement, door, delay, yes/no, and message waits.

### 16. Overworld Script Opcode Coverage

- [ ] Implement `setdooropen`.
- [ ] Implement `setdoorclosed`.
- [ ] Implement `fadescreen` and related fade commands.
- [ ] Implement weather-related script commands.
- [ ] Implement `setstepcallback`.
- [ ] Implement `setmaplayoutindex`.
- [ ] Implement rotating tile object commands.
- [ ] Implement `dofieldeffect`, `waitfieldeffect`, and source field-effect ids used by early maps.
- [ ] Implement additional warp variants: `warpdoor`, `warphole`, `warpteleport`, `warpmossdeepgym`, `warpspinenter`, `warpwhitefade`, and expansion variants.
- [ ] Implement trainer script flow commands enough to start, finish, and resume trainer battles from source scripts.
- [ ] Implement item-giving and item-check commands when overworld scripts require them, through `BagRuntime`.
- [ ] Keep opcode coverage report sorted by source opcode table order.

### 17. Field Input And Step Pipeline

- [ ] Preserve OnFrame script dispatch before accept/movement input.
- [ ] Preserve completed-step pipeline: coord event, current-cell warp, misc walking scripts, step-count scripts, Repel/Lure, DexNav, standard wild encounter.
- [ ] Implement misc walking scripts beyond metadata-only summaries.
- [ ] Implement step-count scripts and side effects.
- [ ] Implement DexNav step behavior or explicit source-traced unsupported records.
- [ ] Implement arrow warp handling after standard wild encounter according to `ProcessPlayerFieldInput`.
- [ ] Implement object/background/metatile interaction ordering.
- [ ] Implement walk-into-signpost behavior.
- [ ] Implement blocked front-cell door warp with source-facing-direction constraints.
- [ ] Implement PC, signs, bookshelves, counters, cable boxes, television, marts, secret-base objects, water interactions, and other metatile scripts through source behavior groups.
- [ ] Add tests that field-input ordering matches the source when multiple triggers are possible.

### 18. Map Transitions And Lifecycle

- [ ] Implement normal warp lifecycle with source fade ordering and map-load callbacks.
- [ ] Implement silent warp lifecycle.
- [ ] Implement door warp lifecycle with real door tasks.
- [ ] Implement connection transition lifecycle with camera movement and backup-map streaming.
- [ ] Implement non-animated door exit.
- [ ] Implement stairs, ladders, escalators, holes, teleport, spin, and white-fade exits.
- [ ] Implement destination exit task selection from destination metatile behavior.
- [ ] Implement `FieldCB_DefaultWarpExit`, `FieldCB_ContinueScriptHandleMusic`, dive/return/resume callbacks, and other source field callbacks as needed.
- [ ] Implement map popup timing and visibility.
- [ ] Implement object-event freeze/unfreeze around transitions.
- [ ] Implement map-load script lifecycle: OnTransition, object-template sync, OnLoad, OnFrame, OnResume, OnReturn, and dive hooks.
- [ ] Add tests for every transition presentation used by generated first-slice maps.

### 19. Weather, Lighting, Palette, And Screen Effects

- [ ] Trace `field_weather.c`, `field_weather_effect.c`, and related palette/screen-effect files.
- [ ] Export map weather metadata and weather transition rules.
- [ ] Implement weather runtime state on map load and connection transitions.
- [ ] Implement rain, ash, sandstorm, fog, underwater, flash darkness, and route-specific effects as presentation contracts.
- [ ] Implement palette fade color selection and timing from source fade functions.
- [ ] Implement screen shake/blend/flash effects used by overworld scripts.
- [ ] Keep weather/palette unsupported metadata visible until presentation is source-equivalent.

### 20. Audio Intent And Later Playback

- [ ] Preserve source sound effect symbols for doors, ledges, bumps, water, menu/message, field effects, and battle-start transitions.
- [ ] Preserve map music ids and music-change rules on map load, connection, battle start, and return.
- [ ] Preserve fanfare symbols and wait intent in script runtime.
- [ ] Add an audio runtime owner later that maps source ids to imported audio assets.
- [ ] Keep audio metadata-only status explicit until real playback is implemented.

### 21. Save And Persistence For Overworld

- [ ] Preserve player map id, grid position, facing direction, avatar state, and transition state in save data.
- [ ] Preserve current-map object-event runtime state.
- [ ] Design cross-map object-event persistence for source save blocks and temporary local changes.
- [ ] Persist `setmetatile` mutations when source behavior expects map changes to survive within the right scope.
- [ ] Persist door open/closed state only when source behavior actually persists it.
- [ ] Persist flags, vars, game stats, Repel/Lure counters, and field-step state already used by overworld.
- [ ] Add tests for save/load during current map, after object movement, after object hide/show, and after map mutation.

### 22. Presentation Layer

- [ ] Replace debug dialogue panel with source-shaped message window presentation.
- [ ] Implement source text printer timing and control-code waits.
- [ ] Implement yes/no menu visual placement from source window templates.
- [ ] Implement object event emotes and field-effect sprites.
- [ ] Implement shadows and reflections.
- [ ] Implement camera movement, input locking, player hide/show, and fade overlays with source timing.
- [ ] Keep debug overlays opt-in and never mutate source map data.
- [ ] Add Playwright or Godot screenshot checks for first viewport, player/object alignment, no grid by default, door playback, and layer ordering.

### 23. Debug Overworld Toolkit

- [ ] Add a Godot-only debug input action such as `debug_overworld_toggle`, with a documented default key like `F10`.
- [ ] Make the debug key open/close a compact overworld debug panel instead of scattering one-off hidden hotkeys.
- [ ] Keep the debug panel disabled in release/export builds unless an explicit debug flag enables it.
- [ ] Mark all debug-triggered state changes as `debug_only` in runtime summaries so they are never mistaken for source-equivalent behavior.
- [ ] Ensure debug actions do not mutate generated source map data, source overlays, or import artifacts.
- [ ] Add a quick player avatar state selector/cycler for normal, running, Mach Bike, Acro Bike, surf, underwater, fishing, watering, field-move, and forced-movement preview states.
- [ ] Route avatar switching through the same future player-avatar runtime APIs used by source gameplay, not by directly swapping textures in presentation nodes.
- [ ] Show unsupported avatar states explicitly when the source-backed runtime for that state is not implemented yet.
- [ ] Add a quick teleport/map picker sourced from `DataRegistry` and the generated manifest.
- [ ] Support teleport by map id plus warp id.
- [ ] Support teleport by map id plus explicit x/y/elevation coordinates.
- [ ] Support a toggle for debug instant-load versus source lifecycle load, where source lifecycle still runs OnTransition/OnLoad hooks.
- [ ] Preserve a clear distinction between debug teleport and source warp/connection/door transitions in logs and smoke tests.
- [ ] Add a current-map weather selector using source weather ids from generated map/header metadata.
- [ ] Add a reset-weather-to-map-default command.
- [ ] Ensure debug weather overrides do not persist into saves unless a future explicit test mode asks for that.
- [ ] Add optional debug toggles for collision, elevation, metatile id, metatile behavior name, layer type, connection target, object local id, door state, and tileset animation state overlays.
- [ ] Add optional debug controls to pause/resume tileset animations and step one animation frame for visual verification.
- [ ] Add optional debug controls to open/close the current door cell through the real door runtime once door state exists.
- [ ] Add optional debug controls to freeze/unfreeze object events and inspect active movement tasks once object-event runtime exists.
- [ ] Add `overworld_debug_tools_smoke` covering key binding registration, panel toggle, avatar state request, teleport request, weather override/reset, and non-persistence of debug-only changes.
- [ ] Add a screenshot check that the debug panel can be shown without hiding the player/map state needed for visual inspection.

### 24. Verification And Regression

- [ ] Add `overworld_import_coverage_smoke` for map/layout/tileset/script/object-event/door/animation import counts.
- [ ] Add `layer_renderer_smoke` for layer assignment and draw ordering.
- [ ] Add `tileset_animation_smoke` for frame counters and pixel changes.
- [ ] Add `door_animation_smoke` for open/close frame order, map-layer mutation, and wait completion.
- [ ] Add `movement_collision_smoke` for collision, elevation, object occupancy, ledges, water, bridge, and forced movement.
- [ ] Add `object_event_runtime_smoke` for spawn/despawn, movement type, held movement, facing, freeze, and save/restore.
- [ ] Add `script_async_smoke` for delay, waitmovement, waitdooranim, waitstate, yes/no wait, and message wait.
- [ ] Add `transition_lifecycle_smoke` for normal, silent, door, connection, stairs, ladder, and exit tasks.
- [ ] Add screenshot checks for Littleroot, Route101, Brendan house, May house, tall grass, doors, and animated water/flowers.
- [ ] Add a CI-friendly command list or script that runs the targeted overworld regression set.
- [ ] Keep `git diff --check` clean for every implementation slice.

### 25. First Vertical Slice Definition

- [ ] Complete the parity matrix rows for the existing maps: `LittlerootTown`, `Route101`, `LittlerootTown_BrendansHouse_1F`, and `LittlerootTown_MaysHouse_1F`.
- [ ] Implement layer-aware rendering for those maps.
- [ ] Implement General/Petalburg dynamic tileset animations visible on those maps.
- [ ] Implement real door frame application for the current Littleroot and house doors.
- [ ] Implement object-event runtime enough for static facing, source idle animation, and scripted movement queue.
- [ ] Implement async `applymovement`/`waitmovement` for the first house intro and Littleroot blocking scripts.
- [ ] Replace simplified player/object collision with source-shaped collision for first-slice terrain.
- [ ] Preserve all current smoke tests and add focused tests for the new runtime owners.
- [ ] Only after this slice is stable, broaden import coverage to all maps and all object graphics.

## Suggested Implementation Order

1. Build the source trace matrix and unsupported coverage report for overworld.
2. Add the Godot-only overworld debug toolkit early enough to inspect avatar state, map teleport, weather overrides, metatile/layer data, and door/tile animation work without polluting source-equivalent paths.
3. Replace flattened `DebugMapPlane` rendering with layer-aware metatile import/rendering for the existing Littleroot/Route101/house slice.
4. Port General and Petalburg tileset animations for the first maps.
5. Replace door overlay playback with real layer/metatile door frame application for the current door slice.
6. Implement object-event movement/action queues for static-facing NPCs, `applymovement`, and `waitmovement`.
7. Expand player/object collision and metatile behavior rules, then add richer player avatar states.

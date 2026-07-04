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

## Backlog

### 1. Source Trace Matrix

- Create a matrix mapping each source file/function/table to the Godot importer/runtime/presentation owner.
- Track status as `ported`, `first_pass`, `metadata_only`, `unsupported`, or `untraced`.
- Keep source-visible timing, side effects, and presentation notes next to each entry.
- Add generated import reports for missing maps, tilesets, door animations, tileset animations, object-event graphics, movement actions, and unsupported script opcodes.

### 2. Full Map And Layout Import

- Batch-import all source maps, layouts, border grids, connections, events, scripts, map metadata, weather, music, map type, battle type, cycling flags, escape warp, and map section data.
- Validate all warp ids, connection offsets, coord events, BG events, object local ids, and referenced scripts.
- Keep source repo read-only and make generated data reproducible from import scripts.

### 3. Layer-Aware Metatile Rendering

- Stop treating each metatile as one flattened image at runtime.
- Export bottom, middle, and top layer tile data from the 8 source tile entries per metatile.
- Apply `METATILE_LAYER_TYPE_NORMAL`, `METATILE_LAYER_TYPE_COVERED`, and `METATILE_LAYER_TYPE_SPLIT` exactly as described in `include/global.fieldmap.h`.
- Render with Godot `TileMapLayer` resources or an equivalent renderer that allows player/object sprites to appear between source layers.
- Preserve tile flips, transparency, palette-baked colors, metatile behavior, collision, elevation, and layer metadata per cell.

### 4. Dynamic Tileset Animations

- Parse primary and secondary tileset `.callback` entries from `src/data/tilesets/headers.h`.
- Port `InitTilesetAnimations`, `InitSecondaryTilesetAnimation`, `UpdateTilesetAnimations`, and callback frame counters from `src/tileset_anims.c`.
- Export animation source frames and copy-region metadata for General, Petalburg, and then all remaining tilesets.
- Update rendered tile regions at source frame cadence, including independent primary/secondary counters and map-load reset behavior.
- Add screenshot or pixel tests for water, flowers, currents, and other animated metatiles.

### 5. Door Animation Parity

- Expand the importer to cover the complete `sDoorAnimGraphicsTable`, including size 1 and size 2 doors, FRLG variants, palette arrays, sounds, open/close frame tables, and unsupported reports.
- Replace overlay-only door playback with map-layer/metatile frame application matching `DrawDoor`, `DrawCurrentDoorAnimFrame`, and `DrawClosedDoorTiles`.
- Implement `FieldAnimateDoorOpen`, `FieldAnimateDoorClose`, `FieldSetDoorOpened`, `FieldSetDoorClosed`, `FieldIsDoorAnimationRunning`, and script-driven `opendoor`/`closedoor`/`waitdooranim` timing.
- Preserve `Task_DoDoorWarp`, `Task_ExitDoor`, non-animated doors, stairs, ladders, escalators, arrow warps, and destination exit-task selection.

### 6. Source Movement And Collision

- Replace `can_enter_cell` with source-shaped player/object collision checks.
- Implement elevation checks, dynamic object collision, directional impassable metatiles, ledges, stairs, bridges, surf/waterfall/dive/rock-climb style behaviors, no-running tiles, bike exceptions, forced movement tiles, currents, ice, spin, muddy slopes, and secret-base mats.
- Generate or hand-port `MetatileBehavior_Is*` helpers from source constants so runtime logic does not rely on ad hoc string matching.
- Preserve terrain side effects after movement: tall grass cover, long grass, sand/ash footprints, puddles, ripples, bridge visibility, cracked floors, and related field effects.

### 7. Player Avatar Runtime

- Extend from normal walk/turn to full source avatar states: walk fast/faster, run, Mach Bike, Acro Bike, surf, underwater, field move, fishing, watering, spin, slide, forced movement, and stair movement.
- Preserve `gPlayerAvatar`-style flags, tile transition state, running state, prevent-step state, controller gating, and first-press turn-in-place behavior.
- Reproduce `ProcessPlayerFieldInput` order: OnFrame scripts, completed-step scripts, standard wild encounter, arrow warp, interaction, door warp, and blocked-front-cell checks.
- Integrate camera movement and map connections through source backup-map semantics instead of final-position-only switching.

### 8. Object Event Runtime

- Import all object-event graphics, palettes, animation tables, subsprite tables, shadows, reflections, and sprite metadata.
- Implement `sMovementTypeCallbacks`, random/wander/look/rotate/walk-sequence/copy-player/follower/berry/disguise/invisible movement types, and exact delay tables.
- Implement held movement/action queues from `script_movement.c`, including `ObjectEventSetHeldMovement`, `ObjectEventExecHeldMovementAction`, `NpcTakeStep`, and `sStepTimes`.
- Make `applymovement` and `waitmovement` drive real visible task queues instead of fast-forwarding net deltas.
- Preserve object event freezing/unfreezing, locking, facing, collision, elevation, subpriority, camera spawn/despawn, local-id lookup, save state, and trainer sight/approach.

### 9. Async Script And Event Flow

- Convert the first-pass synchronous `ScriptVM` path into resumable script contexts for waits and presentation completion.
- Implement true `delay`, `waitmovement`, `waitdooranim`, `waitstate`, message waits, yes/no UI waits, fanfare waits, and field-effect waits.
- Fill overworld-affecting opcodes still missing or metadata-only: `setdooropen`, `setdoorclosed`, `fadescreen`, weather commands, `setstepcallback`, `setmaplayoutindex`, rotating tile commands, additional warp variants, field effects, and trainer battle flow commands.
- Keep script preview read-only and separate from live execution.

### 10. Transitions, Camera, Weather, And Presentation

- Reproduce source transition task order, fade colors, fade timing, callback lifecycle, map popup, flash/weather palette effects, and player hide/show timing.
- Implement `SaveMapView`, `LoadSavedMapView`, `MoveMapViewToBackup`, connection edge scrolling, object-event carryover, and spawn after camera updates.
- Keep audio metadata now, but preserve source sound symbols and timings for later real playback.
- Later presentation work must add real dialogue windows/text printer, field effects, weather particles, shadows/reflections, and map audio.

### 11. Verification

- Add focused smoke tests per feature slice.
- Add import coverage reports for all maps, tilesets, object-event sprites, door animations, and tileset animations.
- Add pixel/screenshot checks for layer ordering, tall grass cover, bridge over/under behavior, door animation frames, animated water/flowers, object-event walk cycles, and player avatar states.
- Keep unsupported counts visible so first-pass behavior is not mistaken for 1:1 parity.

## Suggested Implementation Order

1. Build the source trace matrix and unsupported coverage report for overworld.
2. Replace flattened `DebugMapPlane` rendering with layer-aware metatile import/rendering for the existing Littleroot/Route101/house slice.
3. Port General and Petalburg tileset animations for the first maps.
4. Replace door overlay playback with real layer/metatile door frame application for the current door slice.
5. Implement object-event movement/action queues for static-facing NPCs, `applymovement`, and `waitmovement`.
6. Expand player/object collision and metatile behavior rules, then add richer player avatar states.

# Overworld Parity Todo

Goal: reproduce the source `pokeemerald-expansion` map/overworld experience in Godot with source-equivalent logic, timing, visible layering, object-event animation, map mutations, and generated assets. Any approximation must remain explicit in generated data, runtime summaries, or smoke-test metadata.

## Front-Loaded Constraints

- Do not recreate the GBA palette-bank/runtime graphics limit model in Godot. Source palette files, palette slots, VRAM/OAM details, binary tiles, and packed map/metatile formats are import provenance or bake inputs; runtime map, sprite, weather, transition, and screen effects should consume Godot-friendly RGBA textures/data plus Shader/Material/Animation/resource parameters.
- Palette-changing effects, fades, flashes, tint/cycle effects, sprite scaling, rotation, and affine-like presentation must preserve the source frame timing, ordering, rhythm, and visible result as closely as practical in Godot-native systems; every approximation or deviation stays explicit in unsupported/deviation metadata.
- Audio playback is not part of the current overworld implementation scope. Preserve source sound/music/cry/fanfare symbols, cue ordering, and wait intent in metadata, reports, and runtime summaries, but mark playback as `metadata_only`/`unsupported`.

## Current Snapshot

- `DebugMapPlane` still renders a flattened generated metatile atlas. Generated tileset metadata now marks these atlases as temporary debug-only artifacts and non-equivalent for source runtime layering; real source BG layer ordering and player/object interleaving are not source-equivalent yet.
- `MapRuntime` exposes generated metatile id, collision, elevation, behavior, layer type, object/BG/warp/coord events, door-animation metadata, and first-pass `setmetatile` mutation.
- `MapRuntime.can_enter_cell` is still a first-pass rule: bounds, object occupancy, and `collision == 0`. Source elevation, direction-specific metatile behavior, forced movement, bridge/surf/bike/stair rules, and player-avatar state are pending.
- Door transitions use source-ordered sequence metadata and generated door atlases, but `TransitionSequencePlayer` draws overlay frames rather than mutating the active rendered metatile/layers like `field_door.c`.
- Player Brendan/May normal walk and turn-in-place now use source-traced frame timing. Running, fast walk, bike, surf, underwater, fishing, watering, field move, spin, slide, current, and other avatar states are pending.
- Object events currently spawn as static source-backed sprites for the first small set of imported graphics. Full movement type callbacks, held movement actions, per-frame animation, freezing, collision, subpriority, shadows, reflections, and camera spawn/despawn behavior are pending.
- `ScriptVM` can emit first-pass movement, field, object, transition, and audio effect records. `applymovement`, `waitmovement`, `delay`, `waitdooranim`, and related waits are not true async source tasks yet.
- Tileset import bakes palette RGBA output and door atlases for used doors. Source tileset header asset provenance now covers base images, metatile binaries, metatile attribute binaries, palette source files, source palette-slot/global BG load rules, callback source bindings, callback-to-map metadata for primary/secondary tileset usage, animation frame image candidates, generated RGBA tileset-animation frame strips, compact per-8x8 metatile tile-entry decode metadata, compact metatile attribute decode metadata, source `METATILE_*` labels, and per-layout tileset-pair reverse lookup tables. Palette slots remain import metadata only: runtime map/sprite/weather/screen presentation must use Godot-friendly RGBA textures plus Shader/Material/Animation parameters. Runtime tileset animation playback, per-layer rendering, and complete door graphics tables are pending.
- Metatile behavior constants, bit attributes, helper groups, call sites, and the external Seafoam helper are now traced in `data/generated/overworld/metatile_behavior_trace.json`: 240 `MB_*` constants, 129 explicit bit-attribute rows, 15 encounter-flag behaviors, 18 surfable behaviors, 194 `src/metatile_behavior.c` helper definitions, 1 external helper in `src/overworld.c`, and 24 call-site files. Runtime collision, forced movement, bridge/elevation, terrain effects, and interaction helper consumption remain pending.
- Overworld script command coverage is now traced in `data/generated/overworld/scrcmd_trace.json`: 231 source table entries through opcode `0xe6`, 225 unique table handlers, 239 `ScrCmd_*` functions, 385 event macros, 20 native wait handlers, 98 hardware-effect handlers, 66 save-effect handlers, and current `ScriptVM` coverage of 63 generated op names / 43 direct source-table commands. Weather, fade/palette presentation, field effects, broad warp variants, script-driven trainer/wild battles, full async waits, and audio playback remain pending or metadata-only.

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
- [x] Trace `src/script_movement.c` applymovement task behavior, waitmovement behavior, simultaneous movements, and target resolution.
- [x] Trace `src/event_object_lock.c` object freezing, selected-object locking, player/object facing, and lock release behavior.
- [x] Trace `src/field_door.c` door graphics tables, palette tables, frame tables, metatile mutation, sounds, task timing, and multi-door cases.
- [x] Trace `src/tileset_anims.c`, `include/tileset_anims.h`, and `src/data/tilesets/headers.h` for callback binding, counters, copy regions, and map-load initialization.
- [x] Trace `src/metatile_behavior.c` and `include/constants/metatile_behaviors.h` for every `MetatileBehavior_Is*` group needed by movement, encounters, interaction, terrain effects, and transitions.
- [x] Trace `src/scrcmd.c` overworld-affecting commands, especially waits, doors, map mutation, warps, weather, fades, audio, field effects, object commands, and trainer flow.

### 2. Full Map Import

- [x] Extend the map import entry point to batch over all source `data/maps/*/map.json` records.
- [x] Export every layout referenced by `data/layouts/layouts.json`.
- [x] Export every `map.bin` raw u16 grid, metatile id grid, collision grid, elevation grid, width, height, and source layout symbol.
- [x] Export every `border.bin` and preserve `GetBorderBlockAt` fallback metadata.
- [x] Export map connections with direction, offset, target map id, target map section, and source map-group/map-num metadata.
- [x] Export map header metadata: map type, layout id, music, weather, map section, battle type, allow cycling, allow escaping, allow running, show map name, floor number, and cave/flash flags.
- [x] Export object events with local id, graphics id, movement type, movement range, trainer metadata, flag id, script label, coordinate, elevation, and generated source-order index.
- [x] Export warp events with source x/y/elevation, destination map, destination warp id, and source-order index.
- [x] Export coord events with trigger var, trigger value, elevation, script label, and source-order index.
- [x] Export BG/sign events with kind, coordinates, elevation, script/item/hidden-item metadata, and source-order index.
- [x] Validate every exported script label against generated script bundles and report missing labels.
- [x] Validate every warp destination map and warp id and report invalid or not-yet-generated targets.
- [x] Validate every connection target map and offset and report missing targets.
- [x] Validate duplicate object local ids per map and source numeric local-id aliases.
- [x] Add an import smoke that asserts all source maps either export cleanly or emit deliberate unsupported records.

Snapshot: `tools/importer/export_map.py --all` now exports 939/939 source maps and 785/785 source layouts with 0 map/layout failures, writing map JSON under `data/generated/maps/`, standalone layout JSON under `data/generated/layouts/`, and `data/generated/overworld/map_batch_report.json`. Layout coverage is 711 map-referenced layouts plus 74 standalone layouts; 20 standalone/unused source layouts carry explicit `layout_blockdata_size_mismatch` warnings because their declared width/height is one cell smaller than `map.bin`. Current exported event totals are 266 connections, 4426 object events, 2607 warp events, 603 coord events, and 1422 BG events. Batch validation currently checks 5984 event script references against 6 generated script bundles/207 script labels, resolves 50 references, and reports 5934 missing references across 3795 unique not-yet-exported labels. Static warp validation reports 2543/2543 valid static destinations plus 64 dynamic/secret-base warp destinations marked as special, with 0 invalid or not-yet-generated static targets. Connection validation reports 266/266 valid targets/offsets, including 14 dive/emerge links, and object local-id validation reports 4426/4426 source numeric aliases with 0 duplicates or alias mismatches.

### 3. Script And Text Import For Overworld

- [x] Batch-export all map `scripts.inc` files, not only the first-slice maps.
- [x] Preserve source labels, instruction order, macro-expanded op names, raw operands, source line numbers where available, and shared-script references.
- [x] Export all movement labels referenced by map scripts and shared scripts.
- [x] Export all local text labels with charmap metadata, control codes, placeholders, byte counts, and terminators.
- [x] Resolve shared script includes used by maps, including player house, rival graphics, movement, and common event scripts.
- [x] Report orphan instructions, unknown macros, unresolved labels, missing text labels, and unsupported directives per script file.
- [x] Add a script import coverage report by map id with script count, movement count, text count, unsupported opcode count, and missing reference count.

Snapshot: `tools/importer/export_event_scripts.py --all-maps` exports 887/887 source map `scripts.inc` files into `data/generated/scripts/`, reports the 52 maps without source script files, and writes `data/generated/overworld/script_batch_report.json`. Current map-script batch metrics are 18,984 labels, 10,293 scripts, 1,280 movement labels, 7,411 local text labels, 413,452 source text bytes, 0 charmap warnings, 44 orphan instructions, and 35,865 runtime-preview unsupported op occurrences. `tools/importer/export_event_scripts.py --all-shared` exports 82 additional shared/common bundles from `data/scripts/*.inc` plus direct top-level labels from `data/event_scripts.s`, skipping the 3 already-grouped first-slice shared source files; shared batch metrics are 3,572 labels, 2,649 scripts, 136 movement labels, 787 local text labels, 39,281 source text bytes, 0 charmap warnings, 15 orphan instructions, and 8,850 runtime-preview unsupported op occurrences. Combined with the existing grouped shared bundles, `data/generated/import_manifest.json` now indexes 971 script bundles, including 84 shared bundles, and 13,000 generated script labels; map event script validation resolves 5,314/5,314 real event script references and reports 0 missing references across 0 unique labels. `data/generated/overworld/script_reference_report.json` validates 21,389 checked script/movement/text references, including 2,776 `applymovement`/`applymovementat` movement-label references, and reports 0 missing references; its per-map coverage rows include script count, movement count, text count, unsupported opcode count, and missing reference count. The same report now includes 972 per-source-file diagnostics covering 59 orphan instructions across 30 files, 2 true unknown macro parses across 1 file, 1,908 unsupported assembler/preprocessor directives across 904 files, 0 unresolved script/movement labels, and 0 missing text labels. `0x0` null script pointers remain excluded from map event missing-label counts, and dynamic/null text operands such as `gStringVar4`/`NULL` are counted as excluded rather than missing text labels.

### 4. Tileset And Metatile Asset Import

- [x] Export every primary and secondary tileset header from `src/data/tilesets/headers.h`.
- [x] Export tileset image provenance for `tiles.png`, `metatiles.bin`, `metatile_attributes.bin`, palettes, animation images, and callback symbols.
- [x] Preserve global palette-slot mapping as import metadata while baking runtime RGBA assets.
- [x] Decode every 8x8 tile entry inside each metatile: tile id, palette, hflip, vflip, source tileset, and source layer slot.
- [x] Export metatile attributes: behavior id, behavior name, collision, elevation, terrain type if source exposes it, encounter affordances, and layer type.
- [x] Export `METATILE_*` labels and reverse lookup tables per tileset pair.
- [x] Detect and report metatile ids referenced by maps but absent from the tileset pair.
- [x] Detect and report tile ids referenced by metatiles but absent from source tileset images.
- [x] Keep the current flattened atlas as a temporary debug artifact only, with metadata marking it non-equivalent for runtime layering.

Snapshot: `tools/importer/export_overworld_tileset_headers.py` exports all 139 `struct Tileset` rows from `src/data/tilesets/headers.h` into `data/generated/overworld/tileset_header_report.json`, indexes the report in the manifest as `overworld_tileset_header_report`, and preserves the active Emerald split: 75 active headers, including 3 active primary and 72 active secondary headers, plus 64 FRLG metadata-only headers. The report records `isCompressed`, `isSecondary`, tiles/palettes/metatiles/metatile-attribute symbols, source declaration lines, source `INCBIN` paths, editable source candidates such as `tiles.png`, `metatiles.bin`, `metatile_attributes.bin`, and `palettes/*.pal`, plus 31/31 callback source bindings in `src/tileset_anims.c` and callback-to-map metadata for 785/785 layouts, 939/939 map source records, 137/137 layout tileset pairs, 136 referenced tilesets, and 31/31 callback symbols. It records source palette-slot rules traced from `include/fieldmap.h` and `src/fieldmap.c`: Emerald loads primary local palette slots 0-5 into global BG slots 0-5 and secondary local slots 6-12 into global BG slots 6-12; FRLG loads primary local slots 0-6 and starts secondary at slot 7. Generated palette-slot provenance covers 2224 declared slots, 1200 active Emerald slots, 522 active Emerald loaded-by-source-copy slots, 1024 FRLG metadata-only slots, 386 FRLG loaded-by-rule slots, 2224/2224 editable `.pal` candidates, and 0 missing palette source candidates; source `.gbapal` build-output paths are preserved as missing/non-required provenance. The report also decodes every source `metatiles.bin` u16 tile entry using `include/fieldmap.h`, `include/global.fieldmap.h`, and `src/field_camera.c` rules: 139 header decodes, 134 unique metatile binaries, 27,593 unique metatiles, 220,744 unique tile entries, 0 out-of-range tile ids, plus source bottom/top slot and normal/covered/split draw-rule metadata. It decodes every source `metatile_attributes.bin` record using `include/global.fieldmap.h`, `src/fieldmap.c`, and `src/metatile_behavior.c`: 139 header decodes, 134 unique attribute binaries, 27,593 unique attribute records, 0 missing behavior names, 14,623 normal layer records, 14,556 covered layer records, 34 split layer records, 2,023 encounter-affordance records, and 1,013 surfable-affordance records. It now also exports 924/924 source `METATILE_*` labels from 77 source groups, attaches 924 compact label rows to 77 tileset headers, records 270 out-of-range header labels as explicit diagnostics, and builds reverse lookup tables for 137/137 source layout tileset pairs across 785 layouts. Pair lookup includes FRLG suffix aliases such as `METATILE_GeneralFrlg_* -> gTileset_General_Frlg`, RS compatibility aliases such as `METATILE_RSCave_* -> gTileset_Cave`, and one explicit missing secondary-header pair diagnostic for `gTileset_General+0`. The same report now includes `metatile_map_reference_report`, which checks 785/785 source layouts, 564,213/564,213 source blockdata cells, and 137/137 tileset pairs against pair-local metatile ranges; it reports 1,607 absent map-grid metatile references across 5 layouts and 3 pairs, with 1,508 `secondary_header_missing` cells from `gTileset_General+0`/`LAYOUT_UNUSED_OUTDOOR_AREA` and 99 `secondary_metatile_absent` cells across the FRLG Safari Zone pairs. Emerald active attributes expose behavior and layer type while collision/elevation are explicitly sourced from layout map-grid block bits; FRLG metadata-only records expose terrain and encounter type fields through the source `u32` attribute cast. It also exports 174 tileset animation frame declarations, 182 source `.4bpp` frame references, 182 existing editable PNG frame candidates, 174 generated RGBA frame-strip PNGs under `assets/generated/tileset_anims/`, 26 headers with animation image provenance, and one orphan animation asset base (`data/tilesets/secondary/silph_co_frlg`) that has frame images but no matching header row. Runtime palette/color effects remain import metadata plus Godot-native Shader/Material/Animation presentation work, audio remains `metadata_only`/`unsupported`, and tileset animation playback remains pending. `data/generated/overworld/import_summary.json` now reports 139/139 tileset header coverage, 31/31 callback-map symbol coverage, 939/939 callback-map source-record coverage, 137/137 callback-map layout-pair coverage, 182/182 tileset animation source image coverage, 174/174 tileset animation RGBA frame-strip coverage, 2224/2224 tileset palette source coverage, 220,744/220,744 source metatile tile-entry coverage, 27,593/27,593 source metatile attribute-record coverage, 924/924 source metatile-label coverage, 137/137 layout tileset-pair lookup coverage, and 785/785 layout plus 564,213/564,213 cell map-reference coverage.

Tile-image reference update: `metatile_tile_image_reference_report` decodes 139/139 header `tiles.png` bindings, covers 138/138 unique source tile images and 39,376/39,376 source 8x8 tile slots, reports 44 header-own absent tile-entry refs across 3 headers, and reports 3,782 pair-context absent tile-entry refs across 30 tileset pairs. `data/generated/overworld/import_summary.json` now reports 138/138 source tile-image coverage, 39,376/39,376 source tile-slot coverage, 139/139 tile-image header binding coverage, and 137/137 metatile tile-image pair coverage.

Flattened atlas debug-artifact update: `tools/importer/export_tilesets.py` now writes `runtime_layering_policy` and atlas metadata declaring the first-slice flattened RGBA metatile atlases `debug_only`, `source_equivalent_for_runtime_layering = false`, and `runtime_layering_status = not_source_equivalent` with unsupported code `flattened_debug_atlas_not_source_equivalent`. `data/generated/overworld/import_summary.json` reports 4/4 generated tileset atlases as flattened debug artifacts, 4/4 non-equivalent for runtime layering, 0 source-equivalent runtime-layering atlases, and 0 missing atlas runtime-layering metadata. Section 4 is now complete; Section 5 should replace or wrap `DebugMapPlane` with a source layer-aware renderer.

### 5. Layer-Aware Map Rendering

- [x] Design a Godot map-rendering owner to replace or wrap `DebugMapPlane` for source layer parity.
- [x] Export or build separate render data for bottom, middle, and top layer tiles.
- [x] Implement `METATILE_LAYER_TYPE_NORMAL`: source bottom/middle/top placement according to `global.fieldmap.h` comments and source tile slots.
- [x] Implement `METATILE_LAYER_TYPE_COVERED`.
- [x] Implement `METATILE_LAYER_TYPE_SPLIT`.
- [x] Render player and object sprites at the correct visual depth between map layers.
- [x] Implement y-sort or source subpriority rules so objects behind/under top tiles draw correctly.
- [x] Add a layer debug view that can show bottom/middle/top separately without mutating gameplay data.
- [x] Make `setmetatile` update all affected layer data and renderer caches.
- [x] Make map connection and border rendering use the same layer-aware path as in-bounds cells.
- [x] Keep source collision/elevation queries independent from presentation-only layer toggles.
- [x] Add screenshot or pixel checks for roofs, signs, grass cover, bridge-like metatiles, and indoor objects drawn under top layer.

Layer-aware renderer owner design update: `scripts/overworld/layer_aware_map_renderer.gd` now defines the presentation owner contract for replacing or wrapping `DebugMapPlane`. The owner keeps the existing `Main`/`TransitionSequencePlayer` renderer API stable, delegates to `DebugMapPlane` as a debug fallback, and exposes the required source-traced inputs, bottom/middle/top/object-depth roles, normal/covered/split layer-rule contract, and explicit unsupported codes. It remains `owner_contract_only` and `source_equivalent_for_runtime_layering = false` until the next Section 5 items build separate render data and consume it for real layer drawing. `tools/godot_smoke/layer_aware_map_renderer_smoke.gd` verifies the contract, fallback delegation, door overlay compatibility, and absence of runtime palette/source-color keys.

Layer render data export update: `tools/importer/export_tilesets.py` now writes `layer_rendering` metadata and bottom/middle/top RGBA layer atlases for all four first-slice generated tilesets. `metatile_entries[].render_layers` maps normal/covered/split source tile slots to BG3/BG2/BG1 roles, keeps the normal-layer BG3 fill tile `0x3014` explicit, and leaves runtime consumption pending. `data/generated/overworld/import_summary.json` now reports 4/4 layer-rendering tilesets, 12/12 layer atlases, 2728/2728 generated metatile layer records, 0 missing layer images, and 0 missing layer records. `tools/importer/export_tilesets_layer_rendering_smoke.py` verifies layer-role records, layer-rule slot assignment, atlas image dimensions, and absence of runtime palette/source-color keys in the `layer_rendering` contract.

Normal layer runtime update: `LayerAwareMapRenderer` now loads exported bottom/middle/top layer atlas textures and uses them for `METATILE_LAYER_TYPE_NORMAL` cells. Runtime status is `normal_layer_rendering_first_pass`; `get_layer_draw_records_for_cell` exposes the same normal-layer draw records used by `_draw()`, with BG3/BG2/BG1 roles and atlas source rects matching generated `metatile_entries[].render_layers`. Covered and split layer types still use flattened fallback or pending paths, and object-depth interleave remains explicitly unsupported. `tools/godot_smoke/layer_aware_map_renderer_smoke.gd` now verifies the normal runtime path, 369 Littleroot normal metatiles, loaded bottom/middle/top roles, generated rect parity, fallback delegation, and absence of runtime palette/source-color keys.

Covered layer runtime update: `LayerAwareMapRenderer` now also consumes the exported layer atlases for `METATILE_LAYER_TYPE_COVERED` cells. Runtime status is `normal_covered_layer_rendering_first_pass`; covered draw records map source bottom slots to BG3/bottom, source top slots to BG2/middle, and BG1/top to the generated clear layer, matching `src/field_camera.c:DrawMetatile`. `tools/godot_smoke/layer_aware_map_renderer_smoke.gd` verifies 277 Littleroot covered metatiles, 646 total normal+covered implemented metatiles, generated rect parity for both layer types, and the existing fallback/delegation/no-runtime-palette checks. Split rendering, object-depth interleave, door forced-covered redraws, and per-cell redraw caches remain pending.

Split layer runtime update: `LayerAwareMapRenderer` now consumes exported bottom/middle/top layer atlases for all first-slice metatile layer types. Runtime status is `normal_covered_split_layer_rendering_first_pass`; split draw records map source bottom slots to BG3/bottom, BG2/middle to the generated clear layer, and source top slots to BG1/top, matching `src/field_camera.c:DrawMetatile`. `tools/godot_smoke/layer_aware_map_renderer_smoke.gd` verifies 10 Littleroot split metatiles, 656/656 total Littleroot normal+covered+split implemented metatiles, generated draw-rect parity for all three layer types, fallback delegation, and absence of runtime palette/source-color keys. Object-depth interleave, door forced-covered redraws, and per-cell redraw caches remain pending.

Sprite depth and source-subpriority runtime update: `LayerAwareMapRenderer` now splits its draw path so the parent pass draws bottom/middle layer roles and a `TopLayerOverlay` child draws the BG1/top role above the default sprite band. `scripts/overworld/overworld_depth.gd` preserves the source `src/overworld.c:sOverworldBgTemplates` BG priorities plus `src/event_object_movement.c:sElevationToPriority`, `sElevationToSubpriority`, and `SetObjectSubpriorityByElevation`; `PlayerController` and `ObjectEventPlaceholder` set Godot z-index records from the source pixel-y subpriority formula, putting default first-slice elevation-3 sprites between BG2/middle and BG1/top while lower screen sprites draw above upper screen sprites. Player depth refreshes during tweened movement, object placeholders use their actual frame height for source center-to-corner math, and runtime status is `normal_covered_split_source_subpriority_first_pass`. `layer_aware_map_renderer_smoke`, `object_event_sprite_smoke`, `player_turn_input_smoke`, and `main_debug_battle_smoke` verify top-overlay z order, source subpriority y-sort, default object/player z-index records, and main-scene integration. Bridge subsprites, shadows, reflections, fixed-priority object events, movement-task priority side effects, door forced-covered redraws, and per-cell redraw caches remain pending.

Layer debug view update: `LayerAwareMapRenderer` now exposes `set_layer_debug_view`, `cycle_layer_debug_view`, and `get_layer_debug_view_status` for `all`, `bottom`, `middle`, and `top` presentation-only modes. `Main` binds L to cycle the mode and reports the current value in the status label; the older F8 binding is removed because it can exit/stop the running preview in the current Godot environment. The debug status explicitly reports no gameplay, map-data, collision, or elevation mutation; smoke coverage verifies that source map block ids and tileset metatile entries remain unchanged while top-layer visibility toggles.

Setmetatile layer-cache update: `MapRuntime.apply_script_field_effects` now records source-traced `runtime_layer_updates` metadata for every applied `setmetatile`, including affected cell, previous/current metatile id, collision, preserved elevation, previous/current layer type, and source trace through `ScrCmd_setmetatile`, `MapGridSetMetatileIdAt`, and `CurrentMapDrawMetatileAt`. `LayerAwareMapRenderer.configure_from_map_data` consumes those runtime-only updates into a renderer-local per-cell layer redraw cache and exposes `get_layer_redraw_cache_status` plus `get_layer_redraw_record_for_cell`; generated JSON files remain untouched. Smoke coverage verifies Brendan house moving-box updates in `map_runtime_smoke`, the renderer redraw cache in `layer_aware_map_renderer_smoke`, and the L-only debug key in `main_debug_battle_smoke`. Section 5 progress is now 9/12 complete; total overworld checklist progress is 65/296.

Border/connection layer update: `LayerAwareMapRenderer` now traces the source backup-map shape from `include/fieldmap.h:MAP_OFFSET`, `src/fieldmap.c:GetBorderBlockAt`, and `InitBackupMapLayoutConnections` for presentation lookup. Its layer draw path covers the source-shaped `[-7..width+7] x [-7..height+6]` backup margin without moving local map coordinates: in-bounds cells use current map `block_ids`, connection cells resolve through generated connected map strips such as Littleroot north -> Route101, and remaining edge cells resolve through the generated 2x2 Emerald border grid. `get_border_connection_layer_status` exposes the source margin, connection count, border presence, mutation flags, and trace metadata, while `get_layer_draw_records_for_cell` reports whether a cell came from local, connection, or border data. Smoke coverage verifies a Route101 north connection cell and a 2x2 border cell both use bottom/middle/top layer atlas draw records and match `DebugMapPlane` block lookup. Section 5 progress is now 10/12 complete; total overworld checklist progress is 66/296.

Map-grid query independence update: `MapRuntime` now exposes `get_map_grid_query_contract`, tracing source `GetMapGridBlockAt`, `GetBorderBlockAt`, `MapGridGetMetatileIdAt`, `MapGridGetCollisionAt`, `MapGridGetElevationAt`, and `MapGridGetMetatileLayerTypeAt`. Runtime metatile/collision/elevation/behavior/layer/passability queries read the duplicated current-map grid plus generated connection/border data and do not read `LayerAwareMapRenderer` layer-debug state or layer atlases. Border fallback collision remains source-impassable, and border fallback elevation now matches the source packed border block value of `0`. `map_runtime_smoke.gd` cycles the layer-aware renderer through bottom/middle/top/all for local, Route101-connection, and border cells and verifies the map-grid query snapshots stay unchanged. Section 5 progress is now 11/12 complete; total overworld checklist progress is 67/296.

Layer pixel verification update: `tools/godot_smoke/layer_aware_map_pixel_smoke.gd` adds a headless CI-friendly pixel-composition smoke for the source `DrawMetatile` BG3/BG2/BG1 ordering. It samples generated bottom/middle/top layer atlases for a Littleroot roof/top cell, Littleroot BG sign event cell, Route101 `MB_TALL_GRASS` cell, a source-backed split/bridge-like metatile representative, and a Brendan house indoor top-object cell, then composes a magenta probe sprite between middle and top to verify normal/split/top pixels cover sprites while sign/grass middle pixels stay below sprites. It also verifies the renderer top-overlay z band. Tall grass terrain-effect cover/rustle remains Section 9 work; this test only prevents grass metatiles from being promoted into the top layer. Section 5 is now complete at 12/12; total overworld checklist progress is 68/296.

### 6. Dynamic Metatile And Tileset Animations

- [x] Parse each tileset callback symbol from the source tileset headers.
- [x] Export callback-to-map metadata for primary and secondary tilesets.
- [x] Trace General callback frames and copy regions.
- [x] Trace Petalburg callback frames and copy regions.
- [x] Trace remaining primary tileset callbacks.
- [x] Trace remaining secondary tileset callbacks.
- [x] Export animation image sources and generated RGBA frame strips.
- [x] Export source frame durations, frame counters, wrap behavior, DMA/copy target tile ranges, and affected metatile/tile ids.
- [x] Implement a runtime `TilesetAnimationPlayer` that initializes on map load.
- [x] Support independent primary and secondary animation counters.
- [x] Support pausing/resetting animations across map transitions according to source callbacks.
- [x] Update renderer tile sources or atlas regions without rebuilding the full map every frame.
- [ ] Add tests for animated water, flowers, currents, lava, falls, sand/water edges, and any first-slice General/Petalburg animations.
- [ ] Add unsupported metadata for callbacks not yet rendered even if their source tilesets import successfully.

RGBA frame-strip update: `tileset_header_report.json` now includes `tileset_animation_frame_strips`, converting all 174 animation frame declarations and all 182 editable source PNG frame refs into normal RGBA8 PNG strips under `assets/generated/tileset_anims/`. Single-source frames export as one frame image, while multi-source frames such as Sootopolis stormy water preserve each source image as a horizontal strip segment with `source_rect` and `strip_rect` metadata. Representative generated assets include `gTilesetAnims_General_Flower_Frame0` as 16x16 RGBA and `gTilesetAnims_Sootopolis_StormyWater_Frame0` as a 128x48 two-source RGBA strip. Missing and invalid source image counts are both 0. Section 6 progress is now 7/14 complete; total overworld checklist progress is 70/296.

Schedule/copy-target metadata update: `tileset_header_report.json` now includes `tileset_animation_schedule_trace`, decoded from `src/tileset_anims.c` without introducing a runtime GBA palette system. The trace exports 31 init functions, 25 active init functions, 27 callback functions, 59 scheduled source events, 57 tile-copy events, 2 Battle Dome source-color/palette blend events marked `metadata_only`, 38 queue functions, 41 tile-copy append records, 35 direct tile-offset copies, 6 VDest-array copies, and source counter/wrap metadata such as `InitTilesetAnim_General` primary counter max 256 and secondary callbacks that inherit the primary max. Each tile-copy append records source frame symbols, duration cadence, byte/tile count, destination tile ranges, affected tile ids, affected metatile ids, and samples from active Emerald headers; all 41 tile-copy appends resolve affected metatiles, totaling 58,376 affected metatile references with a maximum of 3,715 unique metatiles for one append. Representative rows include General flower copying 4 tiles to tile ids 508-511 and General water copying 30 tiles to tile ids 432-461. `gTileset_General` now carries 5 schedule events through `TilesetAnim_General`, `gTileset_Petalburg` is correctly init-only with a NULL tile-animation callback, and `gTileset_Mauville` carries 8 flower events. `data/generated/overworld/import_summary.json` and `data/generated/import_manifest.json` expose the schedule counts. Runtime `TilesetAnimationPlayer` playback is still pending. Section 6 progress is now 8/14 complete; total overworld checklist progress is 71/296.

Runtime initialization update: `scripts/overworld/tileset_animation_player.gd` now owns the Godot-side map-load initialization slice traced from `src/overworld.c:InitMapView`, `src/tileset_anims.c:InitTilesetAnimations`, and `src/tileset_anims.c:InitTilesetAnim_*`. `Main` installs it before `MapRuntime.configure_from_data`, and it also listens to `MapRuntime.map_changed` for later transitions. The runtime loads `overworld_tileset_header_report` through `DataRegistry`, creates primary/secondary role states, records init callback, event callback, counter seed/max/wrap metadata, source schedule events, frame-strip resolution counts, compact tile-copy target summaries, and unsupported markers for transition reset/renderer tile updates. On `MAP_LITTLEROOT_TOWN`, the snapshot initializes 2 roles: `gTileset_General` is active with 5 events and 5 copy targets, while `gTileset_Petalburg` is init-only with `NULL` event callback. The initializer does not mutate map data, atlases, or renderer state; source palette/color data remains import metadata and is not represented in runtime logic. `tools/godot_smoke/tileset_animation_player_smoke.gd` verifies the Littleroot General/Petalburg initialization, source phases, flower and water copy ranges, frame-strip resolution, and pending unsupported markers. Section 6 progress is now 9/14 complete; total overworld checklist progress is 72/296.

Runtime counter update: `TilesetAnimationPlayer` now advances source-order independent primary and secondary counters in metadata-only playback: reset buffer intent, increment primary, increment secondary, call primary callback, then call secondary callback. Secondary init functions that reference `sPrimaryTilesetAnimCounter` or `sPrimaryTilesetAnimCounterMax` now resolve from the primary runtime counter seed/max on map load, while literal secondary counters such as `InitTilesetAnim_Underwater` keep their own max. Same-map `MapRuntime.map_changed` emissions preserve counters instead of reinitializing, so field `setmetatile`-style updates do not accidentally reset animation cadence. Runtime frame snapshots emit metadata-only tile-copy requests with selected source-frame indexes and keep `mutates_renderer = false`; transition pause/reset rules and actual renderer tile updates remain pending. Smoke coverage verifies Littleroot `General`/`Petalburg`, Mauville primary+secondary callback ordering, Underwater secondary 128-frame wrap behavior, same-map counter preservation, `map_runtime_smoke.gd`, and 0 runtime `palette`/`source_color`/`source_palette` references under `scripts/` and `scenes/`. Section 6 progress is now 10/14 complete; total overworld checklist progress is 73/296.

Transition pause/reset update: `TransitionSequencePlayer` now exposes source-load lifecycle signals for map transitions: `sequence_map_load_started` fires before the generated `load_map` step applies `EventManager.apply_deferred_transition`, and `sequence_map_loaded` fires after the new map data has been configured. `Main` connects those signals to `TilesetAnimationPlayer.pause_for_transition` and `resume_after_transition`, matching the traced source boundary where `Task_WarpAndLoadMap`/door tasks still run under `OverworldBasic`, then `CB2_LoadMap`/`CB2_DoChangeMap` stop calling `UpdateTilesetAnimations` until `CB2_LoadMap2` finishes map-load steps and returns to `CB2_Overworld`. New-map `MapRuntime.map_changed` reinitializes/reset counters while the pause is active, while same-map updates still preserve counters. Battle-start sequences do not pause map tileset animations because they do not contain a map `load_map` step. Smoke coverage verifies paused frames do not advance counters, map-load reset happens while paused, resume clears the pause, three transition presentation map loads emit paired pause/resume events, `map_runtime_smoke.gd`, focused diff checks, and 0 runtime `palette`/`source_color`/`source_palette` references under `scripts/` and `scenes/`. Section 6 progress is now 11/14 complete; total overworld checklist progress is 74/296.

Renderer atlas update: `LayerAwareMapRenderer` now owns the first-pass tileset-animation tile-copy rendering path by loading bottom/middle/top layer atlases as mutable RGBA `Image`/`ImageTexture` pairs and applying `TilesetAnimationPlayer` frame updates into affected 8x8 atlas slots. The path follows `src/tileset_anims.c:AppendTilesetAnimToBuffer`/`TransferTilesetAnimsBuffer` timing, consumes generated `tileset_animation_frame_strips` plus tile-copy schedule metadata, handles VDest-array current destination ranges such as Mauville flower events, updates changed layer textures through `ImageTexture.update`, and records `rebuilds_full_map=false`, `mutates_generated_files=false`, `mutates_map_data=false`, and `mutates_collision_or_elevation=false`. Smoke coverage verifies first-frame General water updates one tile-copy request, 30 tile ids, affected metatile atlas records, renderer redraw records, and 0 runtime `palette`/`source_color`/`source_palette` references under `scripts/` and `scenes/`. Section 6 progress is now 12/14 complete; total overworld checklist progress is 75/296.

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
- [x] Generate `MetatileBehavior_Is*` helper groups from source constants or maintain a traced Godot table with source references.
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

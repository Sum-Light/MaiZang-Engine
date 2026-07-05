# Port Control Panel

This page is the short operational view for the port. Use it before opening the larger context and architecture notes.

## Current Mainline

Build the LittlerootTown-first vertical slice into a source-faithful Godot runtime.

Current focus:

- Keep generated source data inspectable and reproducible.
- Expand `ScriptVM` only after tracing source C behavior and referenced resources.
- Keep domain systems UI-independent first, then attach presentation.
- Split work into low-coupling module tracks; cross-module behavior should flow through explicit request/result contracts.
- Preserve source-visible timing, sequence, audio intent, UI flow, and state changes where practical.
- Ignore GBA hardware/storage constraints at runtime; importers should bake or normalize assets into Godot-friendly data.
- Do not expose GBA palette systems to gameplay or presentation runtime. Source color files/slots are import-only provenance; shiny, alternate, gender/form, and multi-color-source variants must be distinct RGBA assets, while source-visible color changes, fades, flashes, tints, cycling, scaling, rotation, and affine effects use Godot Shader/Material/Animation/resource parameters with source timing and visible rhythm matched as closely as practical.
- Do not implement audio playback in the current scope. Preserve source sound/music/cry/fanfare symbols, cue ordering, and wait intent as `metadata_only`/`unsupported` until the user explicitly reopens audio.

Next active module:

- Map and overworld parity TODO, currently executing `wiki/overworld-parity-todo.md` section 6 dynamic metatile and tileset animations.

Reason:

- The user asked to execute the map recreation TODO list step by step until complete and report quantified progress after each answer.
- Section 5 is now 12/12 complete: layer-aware normal/covered/split rendering, top overlay drawing, source subpriority depth ordering, presentation-only layer debug views, first-pass `setmetatile` layer redraw cache updates, first-pass border/connection layer rendering, source map-grid query independence, and layer pixel smoke coverage are implemented for the first-slice maps.
- Next executable task: export callback-to-map metadata for primary and secondary tilesets.

## Module Tracks

Use these tracks to keep implementation work independent unless a traced source behavior needs a contract between them.

### Map And Overworld

Owns:

- Map import, map loading, metatile attributes, collision, object events, warps, coordinate events, field steps, field transitions, and overworld-facing script dispatch.

Must not own:

- Battle damage rules, battle parties, battle AI, battle UI, or Pokemon stat/move calculations.

Cross-module contract:

- When field movement reaches a wild or trainer battle, map/overworld code should emit a battle-start request with source context such as map id, metatile behavior, transition hint, trainer id or wild candidate, and player party reference. Battle code consumes that request and returns battle state/results.

### Battle

Owns:

- Pokemon battle state, trainer/wild opponent construction, move execution, type chart, stat calculation, AI, rewards, and battle result summaries.

Must not own:

- Map cell lookup, object-event state, warp routing, step timing, or overworld transition playback.

Cross-module contract:

- Battle receives generated data and a small setup context. If it needs map-derived facts, those facts must be passed in as plain data, not pulled from `MapRuntime`.

### Script And Event Flow

Owns:

- Converted event-script execution, source opcode semantics, branch state such as `VAR_RESULT`, and request/effect records for other modules.

Must not own:

- Domain internals such as bag slot layout, battle damage math, map-grid mutation details, or presentation node animation.

Cross-module contract:

- Script commands call narrow domain APIs or emit structured effects. Commands that affect immediate branching, such as `giveitem`, must receive the real domain result before continuing.

### Inventory And Items

Owns:

- Bag pockets, item quantities, item lookup, item grant/remove/check behavior, and later field/battle item-use contracts.

Must not own:

- Map event dispatch, battle turn control, menu scene layout, or save-file writing.

Cross-module contract:

- Scripts, shops, field moves, battle, evolution, and save talk to inventory through `BagRuntime`/`GameState` APIs and receive plain result dictionaries.

### Data And Import

Owns:

- Source parsing, generated JSON/resources/textures, manifests, source metadata, and unsupported-feature reports.

Must not own:

- Runtime mutation, presentation timing, or gameplay decisions that belong to source-traced runtime systems.

Cross-module contract:

- Runtime modules read generated data through `DataRegistry` and do not parse source files during gameplay.

### Presentation

Owns:

- Godot scenes, animation, audio, windows, menus, fades, sprites, cameras, and input locking.

Must not own:

- Source gameplay rules or persistent state rules.

Cross-module contract:

- Presentation consumes structured runtime sequences and state snapshots, then reports completion or user choices back through explicit callbacks/results.

## Work Lanes

Use these lanes to keep tasks from mixing together.

1. Source trace
   - Identify the source C functions, macros, constants, text, audio, movement, map, and data resources.
   - Record visible behavior, waits, timing, branching, and side effects.

2. Import/generated data
   - Convert source data into stable Godot-friendly JSON, resources, and textures.
   - Preserve source metadata and unsupported notes.

3. Domain runtime
   - Add UI-independent services such as map, script, party, bag, save, encounter, battle, and evolution rules.
   - Mutate `GameState` only through clear APIs.

4. Presentation
   - Play visible sequences, movement, UI, audio, fades, and animation from structured runtime contracts.
   - Do not hide missing presentation behind logical-only behavior when source-visible timing matters.

5. Verification
   - Add or extend smoke tests for each slice.
   - Prefer narrow tests that lock source-traced behavior.

6. Knowledge and git
   - Update wiki and project skill after substantive work.
   - Create a focused commit and push to GitHub after each completed change.

## Definition Of Done

A module slice is done only when:

- Source behavior and referenced resources were traced directly.
- The Godot implementation follows project architecture boundaries.
- Unsupported or approximated behavior is reported explicitly.
- Smoke tests cover the new behavior and important edge cases.
- Wiki and skill durable facts are updated.
- Git status is reviewed, unrelated dirty files are left alone, and a focused commit is pushed.

## Subagent Policy

Use subagents for independent read-only investigation or validation when a task spans separate source domains.

Good subagent tasks:

- Trace source C behavior for a script command or gameplay feature.
- Validate a source-order sequence after the main agent has an implementation plan.
- Inspect a generated-data domain for missing references.

Main-agent responsibilities:

- Read the project skill and required wiki/source files directly.
- Choose the architecture boundary.
- Implement and verify integration.
- Update wiki/skill and create the focused commit.

## Active Backlog

Near-term:

- Continue `wiki/battle-parity-execution-plan.md` B8.2: broaden `RenderText` control-code pixel side effects beyond the first-pass clear/scroll slice, add full link/recorded battle context, and compare action/message/move windows against source captures.
- Continue `wiki/overworld-parity-todo.md` section 6: export callback-to-map metadata for primary and secondary tilesets.
- Current overworld Section 5 status: 12/12 complete; `LayerAwareMapRenderer` now has headless layer pixel smoke coverage for roof/top, BG sign, Route101 tall grass, split/bridge-like, and indoor top-object representatives. The legacy F8 binding is removed because it can conflict with the Godot/editor/window shortcut path and exit the running preview; the presentation-only layer debug cycle is on L.
- Keep the generated battle parity workbench current: `tools/report_battle_parity.py`, `data/generated/reports/battle_parity_report.json`, `data/generated/battle/source_index.json`, `data/generated/battle/event_log_schema.json`, and `tools/godot_smoke/battle_parity_report_smoke.gd`.
- Current B13 status: F6 now launches a developer-only random species/random level wild battle fixture, and F7 opens a trainer id/symbol selector that launches through the trainer battle state contract.
- Current B1/B2 status: battle strings, battle scripts, opcode/macro metadata, move effects, and move-to-script links are generated and available through `DataRegistry`; script/effect execution remains `pending_vm`.
- Current B7.1-B7.7 status: Pokemon battle sprites, trainer battle sprites, battle environment/background metadata, battle transition textures/tilemap composites, battle asset image-quality smoke checks, Pokemon battle asset coverage, and trainer battle asset coverage are generated as Godot-friendly PNG assets plus source metadata. The B7 checklist is now 7/7 complete. Current asset reports still expose runtime and asset gaps: 2664 pending distinct Pokemon color-variant RGBA images, 2 trainer-party `SPECIES_CASTFORM` alias gaps, trainer slide/mugshot/Magma/Aqua playback pending, double battle runtime pending, text/reward flow pending, shader/material color effects pending, affine effects pending, transition/background playback pending, and audio metadata-only.
- Current B8.2 status: battle interface export now preserves 14 source font metric records from `src/text.c:sFontInfos`, 12 Latin width tables from `src/fonts.c`, 11 source font atlas RGBA images from `graphics/fonts/*.png`, 11 generated font role-mask PNGs under `assets/generated/battle_fonts/roles/`, 16 RenderText material color entries from `graphics/battle_interface/textbox.png`, 317 single-byte charmap entries, and 12 font-to-atlas/role-mask bindings; battle text encoding preserves 752 generated glyph spans, including 580 multi-byte spans. Runtime `BattleTextPrinter` groups source-byte visible events by generated spans, applies first-pass RenderText color controls, exposes source charmap glyph indices such as `F -> 0xC0`, records per-glyph role color slots, and now records first-pass source window pixel effects for `ClearTextSpan`, `FillWindowPixelBuffer`, and `ScrollWindow`. `BattleWindowRenderer` composes `render_text_role_colored_preview` bitmap text layers from source role masks/material colors and exposes pixel-effect summaries. Smoke coverage verifies one RenderText color control, the `F` glyph crop rect `[0,192,16,16]`, 12 role-mask bindings, `action_menu_text_pixels=2250`, and source-backed 240x160 action/message/move signatures `E1635039`/`D256DE44`/`43C20F69`.
- Latest audit note: `scripts/` and `scenes/` still have 0 runtime `palette`/`source_color`/`source_palette` references. `BattleScene` reads its first-pass action prompt/menu/PP/type labels from generated B1 battle text records instead of hardcoded text, while generated asset JSON still has legacy import-only `palette` field names that should be normalized to source-color terminology in a future importer cleanup.
- Next executable battle task: continue B8.2 into source-capture screenshot comparison for the new Godot-side action/message/move signatures, full link/recorded battle context, and broader `RenderText` control-code pixel side effects beyond the first-pass clear/scroll slice.
- Next executable overworld task: export callback-to-map metadata for primary and secondary tilesets.

Mid-term:

- Continue overworld 1:1 parity through Section 6 dynamic metatile and tileset animations for the first-slice maps.
- Bag runtime and `giveitem` script support after the current overworld slice is stabilized.
- Broader item script commands such as `takeitem`, `checkitem`, and item-space checks after source tracing.
- Overworld sprite import expansion and movement animation queues.
- Real dialogue/window presentation with source text-control metadata.
- Battle scene presentation and broader move/ability/item effects.
- Party menu, summary, capture, healing, PC storage, and shops.

Long-term:

- Full map import coverage.
- Full trainer battles and AI.
- Complete save/profile/new-game flow.
- Audio, field effects, and polished transitions.

## Mess Control Rule

When the work starts to feel scattered, stop expanding code and update this page first:

- Name one active module.
- Name the next source trace.
- Name the runtime owner.
- Name the cross-module contract, if any.
- Name the test that proves the slice.
- Leave everything else in backlog.

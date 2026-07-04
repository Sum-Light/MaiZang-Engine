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

- Battle 1:1 parity execution planning and the first battle workbench/report slice.

Reason:

- The user redirected the current focus to source-equivalent battle experience, including logic, assets, HUD, interaction animation, sprites, move animation sprites, all moves, all abilities, all trainers, Pokemon battle data/assets, and source battle mechanisms.
- Current Godot battle is still explicitly first-slice and not source-equivalent: it has `BattleEngine` setup/basic damage plus a source-shaped `BattleScene` controller flow, but lacks source battle scripts, full mechanics, source-backed HUD/windows, sprites, move animations, transitions, post-battle flow, and audio playback.
- The broad audit lives in `wiki/battle-parity-todo.md`; the executable checklist lives in `wiki/battle-parity-execution-plan.md`.

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

- Keep the generated battle parity workbench current: `tools/report_battle_parity.py`, `data/generated/reports/battle_parity_report.json`, `data/generated/battle/source_index.json`, `data/generated/battle/event_log_schema.json`, and `tools/godot_smoke/battle_parity_report_smoke.gd`.
- Current B13 status: F6 now launches a developer-only random species/random level wild battle fixture, and F7 opens a trainer id/symbol selector that launches through the trainer battle state contract.
- Current B1/B2 status: battle strings, battle scripts, opcode/macro metadata, move effects, and move-to-script links are generated and available through `DataRegistry`; script/effect execution remains `pending_vm`.
- Current B7.1-B7.7 status: Pokemon battle sprites, trainer battle sprites, battle environment/background metadata, battle transition textures/tilemap composites, battle asset image-quality smoke checks, Pokemon battle asset coverage, and trainer battle asset coverage are generated as Godot-friendly PNG assets plus source metadata. The B7 checklist is now 7/7 complete. Current asset reports still expose runtime and asset gaps: 2664 pending distinct Pokemon color-variant RGBA images, 2 trainer-party `SPECIES_CASTFORM` alias gaps, trainer slide/mugshot/Magma/Aqua playback pending, double battle runtime pending, text/reward flow pending, shader/material color effects pending, affine effects pending, transition/background playback pending, and audio metadata-only.
- Latest audit note: `scripts/` and `scenes/` still have 0 runtime `palette`/`source_color`/`source_palette` references. `BattleScene` now reads its first-pass action prompt/menu/PP/type labels from generated B1 battle text records instead of hardcoded text, while generated asset JSON still has legacy import-only `palette` field names that should be normalized to source-color terminology in a future importer cleanup.
- Next executable task: start B8 battle interface/HUD assets for the Sawyer/Route101 fixture, or start B3 battle script VM only against the newly generated script/effect data; B13.4/B13.5 selector polish and scene-level action smoke remain as debug-lane follow-up.
- Import the remaining source-backed battle HUD/interface assets needed by the Sawyer/Route101 single-battle fixture.
- Replace the current placeholder `BattleScene` layout with source-backed static battle composition before broad move animation work.

Mid-term:

- Continue overworld 1:1 parity after the battle workbench and first battle visual slice are measurable.
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

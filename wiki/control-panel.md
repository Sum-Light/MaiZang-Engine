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

Next active module:

- Overworld 1:1 parity planning and the first map-rendering/runtime slice.

Reason:

- The user redirected the current focus to source-equivalent map/overworld behavior before more item/runtime expansion.
- Current Godot overworld is still first-pass in several player-visible areas: flattened metatile rendering, overlay-only door animation, static object events, partial player avatar states, and simplified collision.
- The durable checklist for this focus lives in `wiki/overworld-parity-todo.md`.

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

- Build the overworld source trace matrix and unsupported coverage report.
- Replace flattened debug metatile rendering with source layer-aware map rendering for the existing Littleroot/Route101/house slice.
- Port the first dynamic tileset animations and replace door overlay playback with real map-layer/metatile door frame application.
- Start real object-event movement/action queues for NPC animation and `applymovement`/`waitmovement`.

Mid-term:

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

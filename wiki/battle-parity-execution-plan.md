# Battle Parity Execution Plan

This page turns `battle-parity-todo.md` into an executable backlog for a map-decoupled, source-equivalent battle experience. It covers battle logic, all move/effect mechanics, sprites, HUD, transitions, interaction animation, move animation sprites, and generated assets. Nothing on this page should be checked off as parity-complete unless it can be traced to the original `pokeemerald-expansion` source.

## Completion Rules

- [ ] A task can only be marked complete after the source files and symbols are listed in generated metadata or wiki notes.
- [ ] Runtime behavior must consume generated source data where the source has tables or scripts. Do not replace source tables with hand-authored Godot approximations.
- [ ] Player-visible behavior needs a presentation task, not only a rules task.
- [ ] Every unsupported branch must appear in generated `unsupported` metadata, a smoke output, or a wiki note.
- [ ] Audio remains metadata-only until the audio scope opens. Preserve cue symbols and timing intent, but do not substitute approximate sounds.
- [ ] Battle code remains map-decoupled. Map and event runtime may request battle start and receive battle results, but battle logic/presentation must not query `MapRuntime`.

## First Vertical Slice Target

Use this slice to prove the full import -> logic -> presentation -> verification loop before expanding coverage.

- Scenario: one non-link single battle, launched from an existing `BattleEngine` state contract.
- Preferred trainer fixture: the current debug Sawyer trainer battle path, because generated trainer data and smoke coverage already exist.
- Backup fixture: one fixed Route101 wild encounter candidate, because wild battle startup metadata already exists.
- Required visible path: intro message, send-out state, action menu, move menu, source-backed move type/PP labels, one ordinary damage move, HP bar update, faint check, and battle result or explicit in-progress state.
- Required move set for the first proof: `MOVE_TACKLE`, `MOVE_EMBER`, `MOVE_WATER_GUN`, one stat move such as `MOVE_GROWL`, and one accuracy-affecting or failure path once the VM exists.
- Required proof: ordered event log, 240x160 screenshot or pixel smoke, generated coverage report, and explicit unsupported notes for everything outside the slice.

## Coverage Gates For All Moves And Mechanics

The answer to "does this include all skills and mechanisms?" is yes at the checklist level: all moves and source battle mechanisms must pass through coverage gates before battle parity can be claimed. Early milestones may implement only a tiny verified set, but the generated reports must track all records from the source.

- [ ] Every generated move record has a coverage row with `move_symbol`, `effect_symbol`, `battle_script_label`, `battle_anim_script`, `target`, `flags`, `additional_effects`, `logic_status`, `animation_status`, `asset_status`, `hud_status`, `audio_status`, `tests`, and `unsupported`.
- [ ] Every `EFFECT_*` in `src/data/battle_move_effects.h` has a runtime support row and links to the battle script label it uses.
- [ ] Every battle script command implemented in `src/battle_script_commands.c` has a VM support row with argument decoding, side effects, presentation events, and tests.
- [ ] Every battle animation command and visual task used by any move has an animation support row.
- [ ] Every animation sprite tag in `src/data/battle_anim.h:gBattleAnimTable` has an asset support row.
- [ ] Every battle interface asset used by healthboxes, windows, menus, bars, icons, indicators, popups, and party summaries has an import support row.
- [ ] Every source battle mode has a status row: single, double, trainer, wild, partner, multi, link/recorded, Safari, Wally tutorial, Frontier/Tent/Pike/Pyramid/Dome/Arena/Palace, legendary/special, and expansion gimmick modes.

## B0 - Workbench And Source Trace Index

- [ ] B0.1 Create `tools/report_battle_parity.py`.
  - Source: read generated Pokemon data plus original battle source files.
  - Output: `data/generated/reports/battle_parity_report.json`.
  - Validate: JSON includes counts for moves, effects, scripts, animation scripts, asset tags, interface assets, and unsupported records.

- [ ] B0.2 Create a battle source symbol index.
  - Source: `src/battle_setup.c`, `src/battle_main.c`, `src/battle_controller_*.c`, `src/battle_script_commands.c`, `src/battle_anim.c`, `src/battle_interface.c`, `src/battle_bg.c`, `src/battle_message.c`, `data/battle_scripts_*.s`, `data/battle_anim_scripts.s`, `src/data/battle_anim.h`, `src/data/battle_move_effects.h`.
  - Output: `data/generated/battle/source_index.json`.
  - Validate: every symbol referenced by later generated battle data has file and line metadata.

- [ ] B0.3 Add `tools/godot_smoke/battle_parity_report_smoke.gd`.
  - Source: generated report only.
  - Output: smoke verifies that coverage rows exist for every generated move.
  - Validate: fails if a generated move lacks effect, animation, or unsupported status metadata.

- [ ] B0.4 Add "unsupported cannot disappear silently" checks.
  - Target files: coverage report and battle smokes.
  - Validate: if a behavior changes from unsupported to supported, a smoke or fixture must name the new support path.

- [ ] B0.5 Define the event-log schema for parity checks.
  - Target file: `data/generated/battle/event_log_schema.json` or wiki-documented schema.
  - Fields: state, battler, action, source symbol, message id, animation id, HP/PP delta, waits, RNG roll metadata, unsupported flags.
  - Validate: current `BattleScene` smoke can emit or compare a minimal log.

## B1 - Generated Battle Strings And Text Printer Data

- [ ] B1.1 Export battle string ids.
  - Source: `include/constants/battle_string_ids.h`.
  - Target importer: `tools/importer/export_battle_strings.py`.
  - Output: `data/generated/battle/strings.json`.
  - Validate: `STRINGID_*` numeric ids, symbol names, and source locations round trip.

- [ ] B1.2 Export battle message text and placeholders.
  - Source: `src/battle_message.c`.
  - Output: placeholder token metadata for attacker, target, move, item, ability, stat, type, side, and Pokemon nicknames.
  - Validate: smoke expands `gText_WhatWillPkmnDo`, `gText_BattleMenu`, `gText_MoveInterfacePP`, and `gText_MoveInterfaceType`.

- [ ] B1.3 Preserve text control codes.
  - Source: battle message text macros and existing global text exporter patterns.
  - Output: structured text runs instead of lossy plain strings.
  - Validate: text printer smoke verifies line breaks, waits, color/control tokens, and unsupported tokens.

- [ ] B1.4 Add `DataRegistry` accessors.
  - Target file: `scripts/autoload/data_registry.gd`.
  - Methods: `get_battle_string_data`, `get_battle_string_record`, `get_battle_string_by_id`, `format_battle_message`.
  - Validate: `tools/godot_smoke/data_registry_battle_strings_smoke.gd`.

## B2 - Battle Scripts And Move Effects

- [ ] B2.1 Export battle script labels and instruction streams.
  - Source: `data/battle_scripts_1.s`, `data/battle_scripts_2.s`.
  - Output: `data/generated/battle/scripts.json`.
  - Validate: labels used by `gBattleMoveEffects` resolve to instruction arrays.

- [ ] B2.2 Export battle script command metadata.
  - Source: `src/battle_script_commands.c` and command tables/macros.
  - Output: opcode names, argument shapes, branch labels, wait behavior, and VM side-effect notes.
  - Validate: report lists implemented vs unsupported opcodes.

- [ ] B2.3 Export move effect routing.
  - Source: `src/data/battle_move_effects.h:gBattleMoveEffects`.
  - Output: `data/generated/battle/move_effects.json`.
  - Validate: every generated move effect symbol resolves to an effect record.

- [ ] B2.4 Extend generated move records with script links.
  - Source: existing `tools/importer/export_moves.py`.
  - Target output: `data/generated/pokemon/moves.json`.
  - Validate: each move has `battle_effect_script`, `battle_anim_script`, `target`, `flags`, `additional_effects`, and unsupported notes.

- [ ] B2.5 Add script import smoke tests.
  - Target files: `tools/godot_smoke/data_registry_battle_scripts_smoke.gd`, `tools/godot_smoke/data_registry_move_effects_smoke.gd`.
  - Validate: ordinary hit effect, status move effect, stat stage effect, and switch/force effect labels are discoverable.

## B3 - Battle Script VM First Slice

- [ ] B3.1 Add a UI-independent VM module.
  - Proposed target: `scripts/battle/battle_script_vm.gd`.
  - Inputs: battle state dictionary, generated script label, selected action, deterministic RNG object.
  - Outputs: state mutations plus ordered battle events.
  - Validate: no scene nodes or map nodes are referenced.

- [ ] B3.2 Implement ordinary damaging move path.
  - Source: `src/battle_script_commands.c`, `data/battle_scripts_*.s`, current `BattleEngine.execute_player_move_turn`.
  - Required flow: attack canceler, PP decrement, accuracy, damage calc, type calc, animation event, HP drain event, messages, faint check, move end.
  - Validate: `MOVE_TACKLE`, `MOVE_EMBER`, and `MOVE_WATER_GUN` use effect/script routing instead of hardcoded move names.

- [ ] B3.3 Move existing damage result code behind VM events.
  - Target file: `scripts/autoload/battle_engine.gd`.
  - Validate: old deterministic one-turn smoke still passes through the VM path.

- [ ] B3.4 Implement source-shaped script variables.
  - Fields: `gBattleScripting`, `gBattleCommunication`, `gBattleStruct`, active battler ids, side data, hit marker, move result flags, damage loc.
  - Validate: event log exposes the variables needed for message and animation routing.

- [ ] B3.5 Implement the first unsupported-op fallback.
  - Behavior: VM stops with structured unsupported event when an opcode is decoded but not implemented.
  - Validate: smoke intentionally routes one unsupported script and asserts the exact unsupported opcode.

## B4 - Core Battle State And RNG

- [ ] B4.1 Replace hardcoded type chart.
  - Source: `src/data/types_info.h` and source type-effectiveness data used by battle calc.
  - Target: generated type matchup data plus `BattleEngine` lookup.
  - Validate: immunities, double weaknesses, resistances, Stellar/Tera/expansion branches are reported or supported.

- [ ] B4.2 Build a source-shaped battle state model.
  - Target: `scripts/autoload/battle_engine.gd` and/or `scripts/battle/battle_state.gd`.
  - Fields: parties, active battlers, battle type flags, side statuses, field statuses, weather, terrain, rooms, turn count, move history, hit marker, stat stages, volatile statuses, item/ability state.
  - Validate: snapshot smoke can serialize and compare the state before and after one VM step.

- [ ] B4.3 Implement deterministic source RNG service for battle.
  - Source: source `Random()` call order for battle setup, action order, damage, accuracy, crit, effects, capture, AI.
  - Target: `scripts/battle/battle_rng.gd`.
  - Validate: test fixtures can force rolls and record call order.

- [ ] B4.4 Finish Pokemon creation for battle.
  - Source: `CreateMon`, `CreateWildMon`, `CreateNPCTrainerPartyFromTrainer`, begin-battle form changes.
  - Targets: `BattleEngine`, `PartyRuntime`.
  - Validate: wild personality, IVs, ability slot, gender, held item, friendship, Pokeball, and form metadata are either source-backed or explicitly unsupported.

- [ ] B4.5 Implement source action and turn order.
  - Source: `SetActionsAndBattlersTurnOrder`, `RunTurnActionsFunctions`.
  - Covers: priority, speed ties, switching, items, run, forced actions, recharge/loafing, Pursuit-like branches.
  - Validate: ordered action smoke for player fast/slow, priority move, switch before attack, item action, and run action.

## B5 - Damage, Accuracy, Status, And End-Turn Mechanics

- [ ] B5.1 Implement complete damage modifier stack.
  - Source: `CalculateBaseDamage`, `DoMoveDamageCalcVars`, type calc helpers, ability/item/config branches.
  - Covers: STAB, type, crit, burn/frostbite, screens, weather, spread target, multi-hit, parental-like modifiers, protection, immunities, fixed damage.
  - Validate: fixture matrix with expected HP deltas and message flags.

- [ ] B5.2 Implement accuracy/evasion and move failure checks.
  - Source: battle scripts and command handlers, not move-name special cases.
  - Covers: accuracy stages, evasion, OHKO rules, weather bypass, protect/detect, semi-invulnerable target rules, No Guard/Lock-On-like behavior.
  - Validate: miss, immunity, failed, protected, and hit fixture logs.

- [ ] B5.3 Implement stat stages.
  - Source: battle script commands and stat stage constants.
  - Covers: stage bounds, simple/contrary-like modifiers, message order, animation routing.
  - Validate: Growl/Tail Whip-style fixture plus blocked-at-min/max messages.

- [ ] B5.4 Implement non-volatile statuses.
  - Covers: sleep, poison, toxic, paralysis, burn, freeze/frostbite if active config uses it.
  - Validate: infliction, blocked, damage/end-turn, full paralysis/sleep turn, thaw/freeze branch metadata.

- [ ] B5.5 Implement common volatile statuses.
  - Covers: confusion, flinch, infatuation, bind/wrap, leech seed, curse, perish song, encore, taunt, torment, disable, heal block, substitute, recharge, charge turns, semi-invulnerable states.
  - Validate: one smoke per status family plus end-turn cleanup order.

- [ ] B5.6 Implement weather, terrain, rooms, and screens.
  - Covers: rain, sun, sand, hail/snow, fog if active, terrain, Trick Room, Wonder Room, Magic Room, Reflect, Light Screen, Safeguard, Mist, Tailwind, Lucky Chant/Aurora Veil if active.
  - Validate: start, duration decrement, end message, damage/stat modifier, and prevention effects.

- [ ] B5.7 Implement ability behavior in event hooks.
  - Source: generated abilities plus traced source C behavior.
  - Hooks: switch-in, before-move, accuracy, damage, immunity, contact, after-damage, status, end-turn, weather/terrain, item interaction, suppression/copy/swap/trace.
  - Validate: popup timing metadata and at least one smoke per hook family.

- [ ] B5.8 Implement held item behavior.
  - Source: generated item data plus battle item handlers.
  - Covers: berries, damage modifiers, choice/assault locks, plates/drives/memories, gems, focus sash/band, leftovers/black sludge, status cures, type resistance berries, item consumption messages.
  - Validate: consume/not-consume state, held item removal, messages, and ability interactions.

## B6 - AI, Multi-Battler, Capture, Rewards, And Battle Modes

- [ ] B6.1 Import trainer AI flags and scoring data.
  - Source: `src/battle_ai_*`, trainer generated data, AI constants.
  - Target: generated AI metadata and `scripts/battle/battle_ai.gd`.
  - Validate: Sawyer/simple trainer chooses from legal moves using source-shaped scoring.

- [ ] B6.2 Implement trainer item use and switching.
  - Source: trainer party/items/AI source.
  - Validate: item action order, switch choice, message events, and unsupported branches.

- [ ] B6.3 Implement double battle state.
  - Covers: four active battlers, target selection, spread damage, partner AI, faint replacement order, multi-target move scripts.
  - Validate: one static double fixture with two targets and a replacement.

- [ ] B6.4 Implement capture and ball shake logic.
  - Source: capture functions, ball modifiers, wild battle result handling.
  - Covers: throw, shake count, caught, break out, party/storage handoff, nickname prompt, send-to-box text.
  - Validate: forced roll fixtures for 0/1/2/3/caught shakes.

- [ ] B6.5 Implement run-away and wild flee behavior.
  - Covers: run chance, Smoke Ball/ability-like bypasses, trapping, Safari-like actions.
  - Validate: success, fail, blocked, and flee event logs.

- [ ] B6.6 Implement rewards and post-battle mutation.
  - Covers: EXP, EVs, money, item rewards, Pay Day, Pickup, friendship, level-up, move learning, evolution handoff, trainer defeated flag/rematch data, whiteout.
  - Validate: result contract can update party/save/event code without battle scene owning map logic.

- [ ] B6.7 Implement special battle modes as separate traced slices.
  - Covers: Safari, Wally tutorial, link/recorded, Battle Frontier/Pike/Pyramid/Dome/Arena/Palace/Tent, two-opponent, partner, multi, legendary/special, expansion gimmicks.
  - Validate: each mode has its own setup metadata, unsupported list, and smoke before UI handoff is allowed.

## B7 - Pokemon, Trainer, And Battle Environment Assets

- [ ] B7.1 Export Pokemon battle sprite metadata.
  - Source: `src/data/graphics/pokemon.h`, `graphics/pokemon`, `src/pokemon_animation.c`, species data.
  - Output: `data/generated/pokemon/battle_sprites.json`, textures under `assets/generated/pokemon_battle/`.
  - Covers: front pic, back pic, normal palette, shiny palette, gender/form variants, shadow/offset/scale, front animation, cry refs.
  - Validate: Torchic, Mudkip, Treecko, Geodude, and one form/gender variant resolve.

- [ ] B7.2 Export trainer battle sprite metadata.
  - Source: `src/data/graphics/trainers.h`, `graphics/trainers`, generated trainers.
  - Output: `data/generated/battle/trainer_sprites.json`, textures under `assets/generated/trainers/`.
  - Covers: trainer front pic, palette, class/pic linkage, mugshot/special refs, slide-in coordinates.
  - Validate: Sawyer trainer sprite resolves from trainer id to texture and palette.

- [ ] B7.3 Export battle backgrounds and environment metadata.
  - Source: `src/data/graphics/battle_environment.h`, `src/data/battle_environment.h`, `graphics/battle_environment`.
  - Output: `data/generated/battle/environments.json`, textures under `assets/generated/battle_environment/`.
  - Covers: grass/water/cave/underwater/frontier/pyramid/dome/special backgrounds, tiles, tilemaps, palettes.
  - Validate: wild Route101, surf/water, and trainer map-hinted backgrounds resolve.

- [ ] B7.4 Export battle transition assets.
  - Source: `graphics/battle_transitions`, transition tables, `src/battle_transition.c`.
  - Output: `data/generated/battle/transitions.json`, textures under `assets/generated/battle_transitions/`.
  - Validate: current concrete `B_TRANSITION_*` ids from `BattleEngine` can resolve to asset metadata or explicit unsupported.

- [ ] B7.5 Add asset alpha/palette smoke checks.
  - Validate: index 0 transparency, GBA palette conversion, frame rects, texture dimensions, and missing asset reports.

## B8 - Battle Interface, HUD, Menus, And Text Windows

- [ ] B8.1 Export battle interface graphics.
  - Source: `graphics/battle_interface`, `src/battle_interface.c`, `src/battle_bg.c`.
  - Output: `data/generated/battle/interface.json`, textures under `assets/generated/battle_interface/`.
  - Covers: textboxes, healthboxes, HP/EXP bars, numbers, status icons, party summary balls, ability popups, type/gimmick indicators, last-used-ball, move-info windows.
  - Validate: all `sBattlerHealthboxCoords` and window template ids resolve.

- [ ] B8.2 Implement source window layer renderer.
  - Target: `scripts/battle/battle_window_renderer.gd`.
  - Covers: BG0/BG1-style tilemap windows, font layout, borders, palette/text colors, text speed/waits.
  - Validate: screenshot smoke for action menu and move menu at 240x160.

- [ ] B8.3 Implement healthbox runtime.
  - Target: `scripts/battle/battle_healthbox.gd`.
  - Covers: creation, slide-in/out, HP bar 48-pixel source width, drain/restore timing, EXP bar, status icon, level/name/gender, party status, bounce, indicators.
  - Validate: HP drain event consumes VM HP delta and reaches exact final pixel width.

- [ ] B8.4 Implement action menu controller.
  - Source: `src/battle_controller_player.c:HandleInputChooseAction`.
  - Covers: Fight, Bag, Pokemon, Run, cursor movement, B/cancel, disabled action rules, menu sounds as metadata.
  - Validate: input smoke for each button and unsupported branches.

- [ ] B8.5 Implement move selection controller.
  - Source: move selection handlers and PP/type window updates.
  - Covers: four move slots, PP display, type display, target select, disabled/zero-PP rules, descriptions/effectiveness overlays if source-active, Z/Max/Tera/Gimmick triggers as metadata until supported.
  - Validate: current generated type label smoke moves from Godot controls to source-backed window rendering.

- [ ] B8.6 Implement party, bag, run, yes/no, and target-selection handoffs.
  - Contract: presentation returns user choice; battle rules consume it.
  - Validate: scene can enter and leave each prompt without mutating map runtime.

## B9 - Battle Scene Composition And Interaction Animation

- [ ] B9.1 Replace the current Godot control layout.
  - Target: `scenes/battle/battle_scene.tscn`, `scripts/battle/battle_scene.gd`.
  - New shape: 240x160 battle viewport using renderer components and generated textures.
  - Validate: no rectangle placeholder healthboxes/windows remain in the parity slice.

- [ ] B9.2 Implement battle renderer layer order.
  - Target: `scripts/battle/battle_renderer.gd`.
  - Layers: battle BG planes, trainer sprites, battler sprites, healthboxes, windows, text, animation sprites, blend/fade overlays, transition overlays.
  - Validate: screenshot smoke checks that each expected layer is nonblank and in source-backed coordinates.

- [ ] B9.3 Implement intro sequence.
  - Source: `src/battle_main.c:DoBattleIntro`, battle setup callbacks, player/trainer controllers.
  - Covers: background load, trainer slide, player throw, Pokemon send-out, messages, waits, healthbox creation.
  - Validate: ordered log matches source-shaped sequence with unsupported audio metadata.

- [ ] B9.4 Implement Pokemon and trainer interaction animation.
  - Covers: send-out, return-to-ball, switch-in, trainer slide, ball throw, faint, shiny intro, cry wait metadata, capture shake, victory/defeat exits.
  - Validate: animation-completion events unblock battle script waits.

- [ ] B9.5 Implement battle transitions.
  - Source: `src/battle_transition.c`, transition assets, transition ids already emitted by `BattleEngine`.
  - Covers: wild, trainer, mugshot, Magma/Aqua, legendary, Frontier, Pyramid, Dome, team and special transitions.
  - Validate: transition smoke selects the correct asset sequence from battle setup metadata.

- [ ] B9.6 Implement post-battle presentation.
  - Covers: faint/result messages, EXP, level-up, move learning, money, trainer defeat text, capture/nickname/storage text, whiteout, return-to-field callback.
  - Validate: battle result contract updates field/event modules only after presentation completes.

## B10 - Move Animation Scripts, Sprites, And Visual Tasks

- [ ] B10.1 Export battle animation scripts.
  - Source: `data/battle_anim_scripts.s`.
  - Output: `data/generated/battle/anim_scripts.json`.
  - Validate: every generated move `battleAnimScript` resolves or reports unsupported.

- [ ] B10.2 Export animation sprite tag metadata.
  - Source: `src/data/battle_anim.h:gBattleAnimTable`.
  - Output: `data/generated/battle/anim_assets.json`.
  - Covers: tag symbol, image table, palette table, frame table, affine anim table, OAM shape/size.
  - Validate: tags required by Tackle/Ember/Water Gun resolve.

- [ ] B10.3 Convert battle animation sprites.
  - Source: `graphics/battle_anims`.
  - Output: textures under `assets/generated/battle_anims/`.
  - Validate: frame rects, palette alpha, atlas coordinates, and tag-to-texture lookup.

- [ ] B10.4 Build battle animation interpreter.
  - Target: `scripts/battle/battle_animation_player.gd`.
  - Covers: load/unload sprite graphics, create sprite, create sprite on target, wait, delay, call/return/goto, battler invisibility, alpha/blend, BG effects, mon BG masks, split priorities, pan/sound metadata.
  - Validate: animation scripts produce deterministic event timelines.

- [ ] B10.5 Port visual tasks by coverage priority.
  - Source: `src/battle_anim*.c`.
  - First tasks: battler translation, shake, affine transform, blend/fade, projectile movement, background scroll, status overlay.
  - Validate: each task has start/end condition smoke and unsupported arg notes.

- [ ] B10.6 Implement first verified move animations.
  - Moves: Tackle, Ember, Water Gun, stat up/down, status infliction, faint, Pokeball throw.
  - Validate: VM attack-animation event waits until animation player reports complete.

- [ ] B10.7 Expand by tag/task coverage, not by taste.
  - Process: choose the next move batch by highest shared unsupported animation tags and visual tasks.
  - Validate: report shows decreasing unsupported count across all moves.

## B11 - Audio Metadata

- [ ] B11.1 Preserve battle audio cue symbols.
  - Source: battle setup, controller commands, animation scripts, UI input, healthbar, capture, level-up, victory.
  - Output: event logs include music/fanfare/SE/cry symbols and wait intent.
  - Validate: no cue is replaced by a guessed Godot sound.

- [ ] B11.2 Add audio coverage report rows.
  - Output: `audio_status = metadata_only`, `unsupported`, or future `playback_supported`.
  - Validate: coverage report remains honest while audio playback scope is closed.

## B12 - Verification And Regression Harness

- [ ] B12.1 Add importer compilation and schema tests.
  - Covers: battle strings, scripts, move effects, anim scripts, anim assets, interface assets, Pokemon sprites, trainer sprites, environments, transitions.
  - Validate: Python importers compile and generated JSON matches schema.

- [ ] B12.2 Add domain VM smoke fixtures.
  - Covers: ordinary hit, miss, crit, immunity, stat move, status move, faint, switch, item, run, capture, end-turn.
  - Validate: event logs compare exact ordered events and HP/PP/stat deltas.

- [ ] B12.3 Add presentation screenshot/pixel smokes.
  - Viewports: 240x160 native and scaled integer window.
  - Covers: intro, action menu, move menu, HP drain, move animation, faint, post-battle.
  - Validate: nonblank source-backed texture areas, no overlapping text, no placeholder rectangles in parity fixtures.

- [ ] B12.4 Add generated parity fixtures.
  - Suggested fixtures: Sawyer trainer, Route101 wild, water encounter, double battle, capture, level-up/evolution handoff.
  - Validate: each fixture records source path, seed/rolls, expected events, and unsupported set.

- [ ] B12.5 Add CI-friendly "battle parity smoke pack" command.
  - Target: existing smoke conventions under `tools/godot_smoke`.
  - Validate: one command can run the battle parity import/data/domain/presentation checks.

## Suggested Task Order

1. B0.1, B0.2, B0.3 - build the report so all later work is measurable.
2. B1.1 to B1.4 - battle strings and text ids.
3. B2.1 to B2.5 - battle scripts, move effects, and move links.
4. B7.1, B7.2, B7.3, B8.1 - Pokemon/trainer/background/HUD asset imports for the first fixture.
5. B9.1, B9.2 - source-backed static battle composition.
6. B3.1 to B3.5 - VM ordinary damage path.
7. B8.2 to B8.5 - text windows, healthbox, action menu, move menu.
8. B10.1 to B10.6 - first move animation interpreter slice.
9. B4 and B5 - expand logic mechanics through source hooks.
10. B6 - AI, rewards, capture, double battles, and special modes.
11. B9.3 to B9.6 - exact intro, transitions, interaction animation, and post-battle flow.
12. B12 - keep adding fixtures as each behavior moves from unsupported to supported.

## Parallel Work Lanes

- Import lane: B1, B2, B7, B8.1, B10.1 to B10.3, B11.
- Rules lane: B3, B4, B5, B6.
- Presentation lane: B8.2 to B8.6, B9, B10.4 to B10.7.
- Verification lane: B0.3 to B0.5, B12.

Each lane can move independently, but no user-visible battle feature is parity-complete until the import, rules, presentation, and verification rows for that feature are all complete.

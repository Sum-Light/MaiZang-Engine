# Battle Parity Execution Plan

This page turns `battle-parity-todo.md` into an executable backlog for a map-decoupled, source-equivalent battle experience. It covers battle logic, all move/effect mechanics, all abilities, all trainers, Pokemon battle data, sprites, HUD, transitions, interaction animation, move animation sprites, and generated assets. Nothing on this page should be checked off as parity-complete unless it can be traced to the original `pokeemerald-expansion` source.

## Completion Rules

- [ ] A task can only be marked complete after the source files and symbols are listed in generated metadata or wiki notes.
- [ ] Runtime behavior must consume generated source data where the source has tables or scripts. Do not replace source tables with hand-authored Godot approximations.
- [ ] Player-visible behavior needs a presentation task, not only a rules task.
- [ ] Every unsupported branch must appear in generated `unsupported` metadata, a smoke output, or a wiki note.
- [ ] Audio remains metadata-only until the audio scope opens. Preserve cue symbols and timing intent, but do not substitute approximate sounds.
- [ ] Godot runtime and gameplay/presentation code must not use GBA palette systems or palette metadata for rendering. Source `.pal` files and source color-slot numbers are import-only provenance; shiny, gender/form color variants, and source cases that reuse art with different colors must be exported as distinct RGBA image assets. Source palette fades/cycles/tints must become Godot Shader/Material/Animation effects with source-visible timing, not runtime palette swaps.
- [ ] Battle code remains map-decoupled. Map and event runtime may request battle start and receive battle results, but battle logic/presentation must not query `MapRuntime`.
- [ ] Debug battle launchers are developer tools only. They must call the same generated-data and battle setup paths as normal wild/trainer battles, and they must not be used as proof that a source battle path is parity-complete.

## First Vertical Slice Target

Use this slice to prove the full import -> logic -> presentation -> verification loop before expanding coverage.

- Scenario: one non-link single battle, launched from an existing `BattleEngine` state contract.
- Preferred trainer fixture: the current debug Sawyer trainer battle path, because generated trainer data and smoke coverage already exist.
- Backup fixture: one fixed Route101 wild encounter candidate, because wild battle startup metadata already exists.
- Required visible path: intro message, send-out state, action menu, move menu, source-backed move type/PP labels, one ordinary damage move, HP bar update, faint check, and battle result or explicit in-progress state.
- Required move set for the first proof: `MOVE_TACKLE`, `MOVE_EMBER`, `MOVE_WATER_GUN`, one stat move such as `MOVE_GROWL`, and one accuracy-affecting or failure path once the VM exists.
- Required debug entry: a map-decoupled quick wild battle entry and a trainer battle entry with trainer id/symbol selection, both routed through the same battle state contracts as normal startup.
- Required proof: ordered event log, 240x160 screenshot or pixel smoke, generated coverage report, and explicit unsupported notes for everything outside the slice.

## Coverage Gates For All Moves And Mechanics

The answer to "does this include all skills and mechanisms?" is yes at the checklist level: all moves and source battle mechanisms must pass through coverage gates before battle parity can be claimed. Early milestones may implement only a tiny verified set, but the generated reports must track all records from the source.

- [ ] Every generated move record has a coverage row with `move_symbol`, `effect_symbol`, `battle_script_label`, `battle_anim_script`, `target`, `flags`, `additional_effects`, `logic_status`, `animation_status`, `asset_status`, `hud_status`, `audio_status`, `tests`, and `unsupported`.
- [ ] Every generated ability record has a coverage row with `ability_symbol`, `flags`, `hook_families`, `runtime_status`, `popup_status`, `ai_status`, `tests`, and `unsupported`.
- [ ] Every generated trainer record has a coverage row with `trainer_symbol`, numeric id, class, party, held items, explicit/default moves, AI flags, trainer battle type, mugshot/special transition metadata, sprite status, reward/post-battle status, tests, and unsupported notes.
- [ ] Every trainer party Pokemon has a coverage row for species/form rewrite, level, IV/EV macro handling, held item, ability/nature/friendship defaults, explicit/default moves, and source party-construction behavior.
- [ ] Every generated Pokemon species/form has a battle data and asset row for base stats, typing, abilities, gender/form data, learnset availability, evolution/post-battle references, front sprite, back sprite, distinct normal/shiny/gender/form color-variant image assets, source color provenance, shadow/offset/scale, front animation, icon references where relevant, cry metadata, tests, and unsupported notes.
- [ ] Every battle-relevant generated item, nature, type, learnset, evolution, and wild encounter record has a battle coverage row or an explicit out-of-battle-only note.
- [ ] Every `EFFECT_*` in `src/data/battle_move_effects.h` has a runtime support row and links to the battle script label it uses.
- [ ] Every battle script command implemented in `src/battle_script_commands.c` has a VM support row with argument decoding, side effects, presentation events, and tests.
- [ ] Every battle animation command and visual task used by any move has an animation support row.
- [ ] Every animation sprite tag in `src/data/battle_anim.h:gBattleAnimTable` has an asset support row.
- [ ] Every battle interface asset used by healthboxes, windows, menus, bars, icons, indicators, popups, and party summaries has an import support row.
- [ ] Every source battle mode has a status row: single, double, trainer, wild, partner, multi, link/recorded, Safari, Wally tutorial, Frontier/Tent/Pike/Pyramid/Dome/Arena/Palace, legendary/special, and expansion gimmick modes.
- [ ] Every debug launcher path has a coverage row proving it is map-decoupled, developer-only, not persisted as source gameplay state, and routed through normal wild/trainer battle setup contracts.

## B0 - Workbench And Source Trace Index

- [x] B0.1 Create `tools/report_battle_parity.py`.
  - Source: read generated Pokemon data plus original battle source files.
  - Output: `data/generated/reports/battle_parity_report.json`.
  - Validate: JSON includes counts for species/forms, abilities, trainers, trainer party Pokemon, moves, effects, scripts, animation scripts, asset tags, interface assets, debug launchers, and unsupported records.

- [x] B0.2 Create a battle source symbol index.
  - Source: `src/battle_setup.c`, `src/battle_main.c`, `src/battle_controller_*.c`, `src/battle_script_commands.c`, `src/battle_anim.c`, `src/battle_interface.c`, `src/battle_bg.c`, `src/battle_message.c`, `data/battle_scripts_*.s`, `data/battle_anim_scripts.s`, `src/data/battle_anim.h`, `src/data/battle_move_effects.h`.
  - Output: `data/generated/battle/source_index.json`.
  - Validate: every symbol referenced by later generated battle data has file and line metadata.

- [x] B0.3 Add `tools/godot_smoke/battle_parity_report_smoke.gd`.
  - Source: generated report only.
  - Output: smoke verifies that coverage rows exist for every generated move.
  - Validate: fails if a generated move, ability, trainer, trainer party Pokemon, species/form, or debug launcher lacks required coverage metadata.

- [x] B0.4 Add "unsupported cannot disappear silently" checks.
  - Target files: coverage report and battle smokes.
  - Validate: if a behavior changes from unsupported to supported, a smoke or fixture must name the new support path.

- [x] B0.5 Define the event-log schema for parity checks.
  - Target file: `data/generated/battle/event_log_schema.json` or wiki-documented schema.
  - Fields: state, battler, action, source symbol, message id, animation id, HP/PP delta, waits, RNG roll metadata, unsupported flags.
  - Validate: current `BattleScene` smoke can emit or compare a minimal log.

- [x] B0.6 Add Pokemon/trainer/ability coverage dimensions to the report.
  - Source: generated species, moves, abilities, items, wild encounters, trainers, trainer party Pokemon, learnsets, natures, evolutions, types, Pokemon graphics tables, trainer graphics tables.
  - Output: report sections for `pokemon_data`, `pokemon_assets`, `abilities`, `trainers`, `trainer_party_mons`, `battle_items`, and `debug_launchers`.
  - Validate: current exported totals are represented or explicitly marked out-of-scope for battle: 1573 species, 935 moves, 311 abilities, 874 items, 399 wild encounter records, 855 trainers, 1825 trainer party Pokemon, 1104 learnsets, 25 natures, and 647 evolution entries.

B0 completion metrics: `battle_parity_report.json` currently has 8644 coverage rows with no missing expected coverage: 935 moves, 311 abilities, 855 trainers, 1825 trainer party Pokemon, 1573 Pokemon data rows, 874 battle item rows, 399 wild encounter rows, 35 battle environment rows, 38 battle transition rows, 1104 learnsets, 25 natures, 647 evolution entries, 21 types, and 2 debug launcher rows. `source_index.json` currently has 7783 indexed symbols and no missing fixed battle symbols.

## B1 - Generated Battle Strings And Text Printer Data

- [x] B1.1 Export battle string ids.
  - Source: `include/constants/battle_string_ids.h`.
  - Target importer: `tools/importer/export_battle_strings.py`.
  - Output: `data/generated/battle/strings.json`.
  - Validate: `STRINGID_*` numeric ids, symbol names, and source locations round trip.

- [x] B1.2 Export battle message text and placeholders.
  - Source: `src/battle_message.c`.
  - Output: placeholder token metadata for attacker, target, move, item, ability, stat, type, side, and Pokemon nicknames.
  - Validate: smoke expands `gText_WhatWillPkmnDo`, `gText_BattleMenu`, `gText_MoveInterfacePP`, and `gText_MoveInterfaceType`.

- [x] B1.3 Preserve text control codes.
  - Source: battle message text macros and existing global text exporter patterns.
  - Output: structured text runs instead of lossy plain strings.
  - Validate: text printer smoke verifies line breaks, waits, color/control tokens, and unsupported tokens.

- [x] B1.4 Add `DataRegistry` accessors.
  - Target file: `scripts/autoload/data_registry.gd`.
  - Methods: `get_battle_string_data`, `get_battle_string_record`, `get_battle_string_by_id`, `format_battle_message`.
  - Validate: `tools/godot_smoke/data_registry_battle_strings_smoke.gd`.

B1 completion metrics: `strings.json` currently has 697 `StringID` enum records, 688 `gBattleStringsTable` entries, 173 declared `gText_`/`sText_` battle texts, 19 tracked battle UI text labels, 936 placeholder records, 1682 text-control records, 12 traced `B_BUFF_*` runtime placeholder families, 17 audio cue records marked `metadata_only`, 0 unsupported table entries, and 0 unsupported text tokens. `DataRegistry` exposes id/symbol/text-label lookups and first-pass context substitution while leaving full source `BattleStringExpandPlaceholders`/`ExpandBattleTextBuffPlaceholders` runtime behavior for the battle VM.

## B2 - Battle Scripts And Move Effects

- [x] B2.1 Export battle script labels and instruction streams.
  - Source: `data/battle_scripts_1.s`, `data/battle_scripts_2.s`.
  - Output: `data/generated/battle/scripts.json`.
  - Validate: labels used by `gBattleMoveEffects` resolve to instruction arrays.

- [x] B2.2 Export battle script command metadata.
  - Source: `src/battle_script_commands.c` and command tables/macros.
  - Output: opcode names, argument shapes, branch labels, wait behavior, and VM side-effect notes.
  - Validate: report lists implemented vs unsupported opcodes.

- [x] B2.3 Export move effect routing.
  - Source: `src/data/battle_move_effects.h:gBattleMoveEffects`.
  - Output: `data/generated/battle/move_effects.json`.
  - Validate: every generated move effect symbol resolves to an effect record.

- [x] B2.4 Extend generated move records with script links.
  - Source: existing `tools/importer/export_moves.py`.
  - Target output: `data/generated/pokemon/moves.json`.
  - Validate: each move has `battle_effect_script`, `battle_anim_script`, `target`, `flags`, `additional_effects`, and unsupported notes.

- [x] B2.5 Add script import smoke tests.
  - Target files: `tools/godot_smoke/data_registry_battle_scripts_smoke.gd`, `tools/godot_smoke/data_registry_move_effects_smoke.gd`.
  - Validate: ordinary hit effect, status move effect, stat stage effect, and switch/force effect labels are discoverable.

B2 completion metrics: `scripts.json` currently has 1393 battle script labels, 6309 source instructions, 5217 command instructions, 1092 directive/data instructions, 479 explicit fallthrough label links, 256 opcode records, 256 command handler links, 431 script macros, 10 audio macros marked `metadata_only`, and 0 unresolved battle script label references. `move_effects.json` has 332 `EFFECT_*` records, 332 `gBattleMoveEffects` table entries, 217 unique battle script labels, 332/332 resolved battle script links, 0 missing table entries, and 0 missing battle script labels. `moves.json` now links all 935 moves to `battle_effect_script` with 0 missing links. Runtime script/effect behavior remains `pending_vm`; this milestone imports and links source data only.

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

- [ ] B4.6 Complete Pokemon battle data runtime coverage.
  - Source: generated species, forms, abilities, learnsets, natures, items, evolutions, and source Pokemon creation/stat functions.
  - Covers: all species/forms, base stats, typing, ability slots, gender/form variants, level-up/default move assignment, nature/stat effects, held-item defaults, friendship, Pokeball, personality/IV metadata, shiny/form change hooks, and evolution-after-battle handoff metadata.
  - Validate: no generated species/form used by wild/trainer/party/capture/reward paths is missing a battle data row; macro-partial species remain explicit unsupported records until expanded.

- [ ] B4.7 Add battle data completeness smokes.
  - Target files: `tools/godot_smoke/battle_pokemon_data_coverage_smoke.gd`, `tools/godot_smoke/battle_trainer_roster_coverage_smoke.gd`.
  - Validate: every generated trainer party Pokemon can construct or deliberately fail with source-referenced unsupported metadata; every battle-eligible species can resolve stats, typing, default ability metadata, and at least one battle sprite status row.

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
  - Hooks: switch-in, before-move, priority, target selection, accuracy, damage, immunity, contact, after-damage, status, end-turn, weather/terrain, item interaction, form change, suppression/copy/swap/trace/overwrite, AI visibility, and popup timing.
  - Validate: all 311 generated ability records have hook-family coverage; popup timing metadata and at least one smoke per hook family exist before marking a family supported.

- [ ] B5.7a Add ability coverage report and smoke matrix.
  - Source: `src/data/abilities.h`, battle ability handlers, generated ability flags.
  - Output: `data/generated/reports/battle_ability_coverage.json`.
  - Validate: every ability is categorized as `implemented`, `metadata_only`, `not_battle_relevant`, or `unsupported`, with source files and tests listed.

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

- [ ] B6.8 Complete generated trainer roster runtime coverage.
  - Source: `src/data/trainers.party`, trainer constants, `tools/trainerproc/main.c`, generated trainer JSON, battle setup, AI, reward, mugshot, music, and trainer class data.
  - Covers: all 855 trainers, 1825 trainer party Pokemon, 77 double battles, 141 trainers with items, 839 trainers with AI flags, 5 mugshot trainers, explicit moves, source default move assignment, held items, gendered species rewrites, itemed form rewrites, rematch/reward/post-battle metadata.
  - Validate: every generated trainer id/symbol can be selected by the debug trainer launcher and either creates a valid battle state or returns a source-referenced unsupported record.

- [ ] B6.9 Add trainer roster coverage report and smokes.
  - Output: `data/generated/reports/battle_trainer_coverage.json`.
  - Validate: report rows exist for trainer party construction, AI flags, item use, battle type, transition type, sprite asset, reward/post-battle handling, and unsupported status.

## B7 - Pokemon, Trainer, And Battle Environment Assets

- [x] B7.1 Export Pokemon battle sprite metadata.
  - Source: `src/data/graphics/pokemon.h`, `graphics/pokemon`, `src/pokemon_animation.c`, species data.
  - Output: `data/generated/pokemon/battle_sprites.json`, textures under `assets/generated/pokemon_battle/`.
  - Covers: every generated battle-eligible species/form, front pic, back pic, distinct normal/shiny/gender/form image variants, import-only source color provenance, shadow/offset/scale, front animation, icon refs where battle UI needs them, and cry refs.
  - Current first pass: `tools/importer/export_pokemon_battle_sprites.py` imports 1330 front/back sprite pairs and 1328 icons as Godot-friendly PNG textures, records 1329 normal/shiny source color provenance sets, 1328 front-animation metadata records, 1330 cry refs as `metadata_only`, and preserves 245 explicit unsupported Pokemon asset rows for macro/partial or missing source references.
  - Boundary: no runtime GBA palette-bank/VRAM/OAM model or palette-remap path is allowed. Shiny and other color variants must become distinct RGBA assets; affine transforms and sprite animation timing should use Godot materials/animation while matching the source-visible rhythm. Audio remains metadata-only.
  - Validate: the coverage report lists every missing or unsupported species/form asset; Torchic, Mudkip, Treecko, Geodude, one gender variant, one form variant, one shiny image-variant requirement, and one macro-partial species are fixture rows.

- [x] B7.2 Export trainer battle sprite metadata.
  - Source: `src/data/graphics/trainers.h`, `graphics/trainers`, generated trainers.
  - Output: `data/generated/battle/trainer_sprites.json`, textures under `assets/generated/trainers/`.
  - Covers: every trainer pic referenced by generated trainer records, trainer front pic, baked source color provenance, class/pic linkage, mugshot/special refs, slide-in coordinates, and unsupported records for trainer ids without a normal battle sprite path.
  - Current first pass: `tools/importer/export_trainer_sprites.py` imports 155 front trainer textures, 10 back trainer textures, 155 front source color records, 10 back source color records, 5 mugshot background source color refs, and resolves 855/855 generated trainer ids to first-pass trainer sprite rows. PNG color fallback is used for source front pics that do not have checked-in `.pal` companions.
  - Boundary: trainer slide-in and mugshot x/y/rotation metadata are preserved from `BtlController_HandleDrawTrainerPic`, `BtlController_HandleTrainerSlide`, and `battle_transition.c`, but runtime playback remains pending under `battle_animation_runtime_pending`; audio remains metadata-only.
  - Validate: `data_registry_trainer_sprites_smoke.gd` checks Sawyer, Hiker shared sprite lookup, Sidney mugshot lookup, Wallace mugshot offsets, and Brendan back sprite lookup; `battle_parity_report_smoke.gd` asserts trainer asset rows no longer carry `trainer_asset_import_pending`.

- [x] B7.3 Export battle backgrounds and environment metadata.
  - Source: `src/data/graphics/battle_environment.h`, `src/data/battle_environment.h`, `graphics/battle_environment`.
  - Output: `data/generated/battle/environments.json`, textures under `assets/generated/battle_environment/`.
  - Current first pass: `tools/importer/export_battle_environments.py` parses 35 `BATTLE_ENVIRONMENT_*` records, 65 graphics definitions, 8 `sMapBattleSceneMapping` rows, and bakes 23 full background PNGs plus 23 entry overlay PNGs from source tilemaps and import-only source colors. Generated backgrounds preserve full source tilemap dimensions (`512x256` for BG3 environment maps when present) and mark the `240x160` visible viewport for later presentation cropping/scrolling.
  - Covers: grass, long grass, sand, underwater, water, pond, mountain/rock, cave, building/plain/frontier/gym/leader, Magma/Aqua, Elite Four/Champion stadium variants, Groudon/Kyogre/Rayquaza special backgrounds, source color variants, Nature Power, Secret Power, Camouflage, battle intro slide symbols, and map battle scene environment overrides.
  - Boundary: the 12 source environments without background assets (`SOARING` through `ULTRA_SPACE`) are retained as logic/terrain metadata with `battle_environment_asset_pending`; runtime background selection, scrolling, entry animation playback, and audio playback remain explicit pending work. Pyramid/Dome do not have standalone battle background records in `gBattleEnvironmentInfo` and stay covered by source mapping/Frontier or later transition/runtime tasks as traced.
  - Validate: `data_registry_battle_environments_smoke.gd` checks Grass, Water, Leader, Gym/Frontier map-scene mapping, Soaring pending metadata, image existence, source color provenance, and viewport/audio notes; `battle_parity_report_smoke.gd` verifies 35 environment coverage rows and no missing expected coverage.

- [x] B7.4 Export battle transition assets.
  - Source: `include/battle_transition.h`, `src/battle_setup.c`, `src/battle_transition.c`, `src/battle_transition_frontier.c`, `graphics/battle_transitions`, and `graphics/field_effects/palettes/pokeball.pal`.
  - Output: `data/generated/battle/transitions.json`, textures under `assets/generated/battle_transitions/`.
  - Current first pass: `tools/importer/export_battle_transitions.py` parses 38 concrete `B_TRANSITION_*` records, 10 transition groups, 55 graphics definitions, 4 wild transition table rows, 4 trainer transition table rows, 12 Battle Frontier entries, 3 Battle Pyramid entries, and 4 Battle Dome entries. It imports 23 transition PNGs as Godot-friendly RGBA textures, preserves 19 import-only source color refs, and decodes all 14 binary/tilemap refs into composite PNGs or explicit dynamic block previews.
  - Covers: ordinary wild/trainer lower-level and equal-or-higher branches, cave/Flash/water transition groups, Mugshot, Magma/Aqua, legendary/special transitions, Frontier, Pyramid, Dome, Big Pokeball, Pokeball trail, and concrete transition ids currently emitted by `BattleEngine`.
  - Boundary: no runtime GBA palette-bank/VRAM/OAM model or palette-remap path is allowed; Big Pokeball, Mugshot, Aqua/Magma, Regi, Weather Trio, Frontier Logo, Frontier Circles, and VS-frame tilemaps have static composite assets, while Frontier Squares is only a 4x4 dynamic block preview because the source repeatedly places that tilemap during task playback. Later fades, masks, mosaic-like timing, HBlank/VBlank-inspired effects, source color flashes, and affine transforms should use Godot-native shaders/materials/animation while matching the source-visible rhythm. Audio remains metadata-only.
  - Validate: `data_registry_battle_transitions_smoke.gd` checks transition stats, Big Pokeball/Aqua/Mugshot/Rayquaza/Frontier asset refs, source selection tables, all 14 tilemap composites/previews, concrete `BattleEngine` transition ids, runtime-pending metadata, and audio notes; `battle_parity_report_smoke.gd` verifies 38 transition coverage rows and no missing expected coverage.

- [x] B7.5 Add battle asset image-quality smoke checks.
  - Output: `tools/godot_smoke/battle_asset_image_quality_smoke.gd`, plus battle parity report test references for first-pass Pokemon, trainer, environment, and transition asset rows.
  - Current first pass: the smoke validates generated Godot-friendly asset metadata across 4,428 image references, 231 import-only source color provenance records, and 14 transition tilemap composites/previews; it opens 14 representative PNGs to verify actual alpha behavior, metadata dimensions, and nonblank/opaque/transparent expectations.
  - Covers: source-index-0 transparency metadata, Pokemon frame-size metadata inside generated sprite sheets, trainer front/back sprite transparency metadata, battle background opaque conversion, entry overlay alpha conversion, transition texture alpha where source color provenance exists, transition tilemap composite dimensions, transition missing-asset refs, and known missing-image report counts.
  - Boundary: this is an asset-quality smoke, not runtime playback. Runtime palette remaps or palette animation are forbidden; source color flashes/fades, affine scaling/rotation, masks/fades, sprite animation timing, and audio playback remain pending and should use Godot-native shaders/materials/animation while matching the source-visible result.
  - Validate: `battle_asset_image_quality_smoke.gd` reports `image_load_count=14`, `metadata_image_ref_count=4428`, `source_color_provenance_count=231`, and `tilemap_composite_count=14`; `battle_parity_report_smoke.gd` asserts the smoke is attached to representative first-pass rows.

- [x] B7.6 Add Pokemon data and asset completeness report.
  - Output: `data/generated/reports/pokemon_battle_asset_coverage.json`.
  - Current first pass: `tools/report_pokemon_battle_assets.py` emits 1573 Pokemon/form coverage rows, 1330 normal front/back first-pass sprite pairs, 1328 imported battle UI icons, 100 complete source-required female variant asset sets, 1329 normal/shiny source color provenance rows, 1328 front-animation metadata rows, and 1330 cry refs marked `metadata_only`.
  - Variant gaps: the report marks 1329 rows with pending distinct source-color image variants and 2664 total pending distinct RGBA image assets, including 1329 shiny front gaps, 1329 shiny back gaps, 3 female shiny front gaps, and 3 female shiny back gaps. These are tracked as asset TODOs, not runtime color remap paths.
  - Boundary: the report exposes source color provenance only. Source `.pal`/`.gbapal` paths and source color symbols remain import-only trace data; runtime battle presentation must consume distinct RGBA images plus Godot Shader/Material/Animation parameters for tint/fade/flash/affine effects. Audio playback remains closed and all cry refs remain metadata-only.
  - Validate: `pokemon_battle_asset_coverage_smoke.gd` checks report schema/policy, row shapes, Torchic, Pikachu, Unfezant, Unown, Geodude, Castform, Mega Venusaur, icons needed by battle UI, distinct shiny/female-shiny gaps, front animations, placement/shadow metadata, cry metadata-only status, unsupported reason registry, and absence of a `runtime_palette` API.

- [x] B7.7 Add trainer data and asset completeness report.
  - Output: `data/generated/reports/trainer_battle_asset_coverage.json`.
  - Current first pass: `tools/report_trainer_battle_assets.py` emits 855 trainer coverage rows, 855 first-pass trainer front-sprite asset rows, 155 imported front trainer texture definitions, 10 imported player back-sprite definitions, 93 unique front sprites used by trainers, 855 front source color provenance rows, 5 mugshot source color provenance rows, and 855 encounter music refs marked `metadata_only`.
  - Party coverage: the report checks all 1825 trainer party Pokemon against the Pokemon battle asset coverage report. Current first pass has 852 trainer rows with complete party Pokemon sprite requirements, 1 no-party row, and 2 rows with explicit `SPECIES_CASTFORM` alias gaps (`TRAINER_ANGELICA` and `TRAINER_KAYLEY`) marked `trainer_party_species_asset_pending`.
  - Transition gaps: the report records 787 normal trainer-transition-table rows, 5 mugshot special transition rows, 33 Team Magma special transition rows, and 30 Team Aqua special transition rows. Runtime playback for trainer slides, mugshots, Magma/Aqua transitions, double battles, AI, intro/defeat/post-battle text, rewards, and audio remains explicit unsupported metadata.
  - Boundary: source color records stay import-only provenance. Runtime trainer presentation must consume RGBA images plus Godot Shader/Material/Animation parameters for tint/fade/flash/affine effects; audio playback remains metadata-only.
  - Validate: `trainer_battle_asset_coverage_smoke.gd` checks report schema/policy, stats, row shapes, `TRAINER_NONE`, Sawyer, Sidney, Wallace, Aqua/Magma grunts, Angelica Castform alias gap, Gabby & Ty double-battle metadata, unsupported reason registry, and absence of a `runtime_palette` API.

## B8 - Battle Interface, HUD, Menus, And Text Windows

- [x] B8.1 Export battle interface graphics.
  - Source: `graphics/battle_interface`, `src/battle_interface.c`, `src/battle_bg.c`.
  - Output: `data/generated/battle/interface.json`, textures under `assets/generated/battle_interface/`.
  - Covers: textboxes, healthboxes, HP/EXP bars, numbers, status icons, party summary balls, ability popups, type/gimmick indicators, last-used-ball, move-info windows.
  - Current metrics: 68/68 source PNG textures exported as ordinary RGBA images, 8 source color files recorded as import-only provenance, 1/1 `textbox_map.bin` tilemap composite generated under `assets/generated/battle_interface/composites/`, 25 `sStandardBattleWindowTemplates` records parsed with Godot semantic style ids, 2 `sBattlerHealthboxCoords` groups parsed, 5 healthbox frame textures, 13 healthbox element textures, 5 gimmick trigger textures, 23 gimmick indicator textures, 0 missing textures, and 0 tilemap warnings.
  - Validate: `tools/godot_smoke/data_registry_battle_interface_smoke.gd`, `tools/godot_smoke/battle_asset_image_quality_smoke.gd`, and `tools/godot_smoke/battle_parity_report_smoke.gd`.
  - Boundary: this is an asset/metadata slice only. Source-equivalent textbox/window rendering, healthbox animation, menus, ability popup playback, gimmick indicator playback, shader/material visual effects, and audio playback remain later B8/B9 tasks.

- [ ] B8.2 Implement source window layer renderer.
  - Target: `scripts/battle/battle_window_renderer.gd`.
  - Covers: BG0/BG1-style tilemap windows, font layout, borders, RGBA/text material styles, text speed/waits.
  - Current first pass: `BattleWindowRenderer` consumes generated `data/generated/battle/interface.json`, blits generated per-window `tilemap_composite_rect` records from the B8.1 `textbox_map.png` RGBA composite for `B_WIN_MSG`, action prompt/menu, four move-name windows, PP windows, and move type, reads generated `text_info` records from `sTextOnWindowsInfo_Normal`, and now drives a first-pass source-aware `BattleTextPrinter` event stream. `BattleScene` still mounts this renderer for intro/action/move bottom windows while keeping existing buttons as transparent input hit zones and defaulting demo text to immediate reveal.
  - Current generated/runtime metrics: 10 source-window composite rects are generated from `sStandardBattleWindowTemplates`; 25 normal battle-window `text_info` records are generated from `sTextOnWindowsInfo_Normal`; generated `text_printer.font_metrics` now preserves 14 `sFontInfos` source font records from `src/text.c`, 12 Latin glyph width table bindings from `src/fonts.c`, Chinese double-byte/punctuation rules from `src/chinese_text.c`, 11 source font atlas RGBA images under `assets/generated/battle_fonts/`, 11 source font role-mask PNGs under `assets/generated/battle_fonts/roles/`, 16 RenderText material color entries from `graphics/battle_interface/textbox.png`, 317 single-byte charmap entries, 12 font-to-atlas/role-mask bindings, and per-window font metric summaries; `text_printer` metadata preserves `BattlePutTextOnWindow` message speed source, A/B speed-up flag intent, recorded-battle speeds `[8,4,1,0]`, and player text speed delay/modifier/scroll tables. Runtime `BattleTextPrinter` resolves `GetPlayerTextSpeedDelay`, models the source `AddTextPrinter` nonzero-speed `speed - 1` delay counter, supports speed-zero synchronous menu text, can parse generated `source_text` records for `\n`, `\l`, `\p`, trailing `$`, `{PAUSE n}`, `{PAUSE_UNTIL_PRESS}`, metadata-only audio tokens such as `{PLAY_SE ...}`/`{WAIT_SE}`, and style controls, and still falls back to display-text events when no source text is available. It propagates generated `encoding.bytes`/hex plus `encoding.glyphs` when text records have no runtime substitutions, drives first-pass events directly from source bytes for `CHAR_NEWLINE`, `CHAR_PROMPT_SCROLL`, `CHAR_PROMPT_CLEAR`, `PLACEHOLDER_BEGIN`, `CHAR_DYNAMIC`, `CHAR_KEYPAD_ICON`, `CHAR_EXTRA_SYMBOL`, and known EXT control codes, reports byte-control summaries with offsets/args, splits prompt-scroll versus prompt-clear waits in runtime snapshots, groups visible source-byte events by generated glyph byte spans, resolves source single-byte fallback through `charmap.txt` such as `F -> 0xC0`, applies first-pass RenderText color controls to per-glyph role slots, exposes `source_glyph_layout` records with source font id, origin/cursor, line count, glyph width/height/advance, source byte spans, layout control events, source atlas/role-mask crop rects, and RenderText color indices, and `BattleWindowRenderer` now composes first-pass `render_text_role_colored_preview` bitmap text layers over the generated textbox windows. Generated battle strings currently preserve 752 visible glyph spans, including 580 multi-byte spans.
  - Link/recorded text controller context first pass: runtime snapshots now expose `source_battle_text_context_first_pass`, `auto_scroll_source`, source auto-scroll reasons, recorded text speed index/value, and recorded speed table metadata traced from `BattlePutTextOnWindow`/`TextPrinterWaitWithDownArrow`. `BattleEngine` now derives `battle_text_setup_context_first_pass` from source-traced setup flags/options, including `BATTLE_TYPE_LINK`, `BATTLE_TYPE_RECORDED`, `BATTLE_TYPE_RECORDED_LINK`, `recorded_text_speed_index`, and metadata-only unsupported notes for link synchronization/recorded playback. `EventManager` copies those setup options into battle-start requests and exposes the context on transition sequences. `BattleScene` maps battle-state/sequence text context keys such as `battle_type_flags`, `battle_text_mode`, `battle_type_*`, `test_runner_enabled`, and `recorded_text_speed_index` into message/action/move text-printer options, exposes `source_battle_text_controller_context_first_pass`, and `BattleWindowRenderer` restarts same-text printers when their text-printer options change. The first pass covers link speed override, recorded speeds `[8,4,1,0]`, recorded-link speed `1`, test-runner auto-scroll, the source nuance that `BATTLE_TYPE_RECORDED_LINK` alone does not set `gTextFlags.autoScroll`, and 50-frame auto-scroll prompt release.
  - RenderText control-code side-effect first pass: runtime snapshots now expose `source_render_text_control_side_effects_first_pass` summaries for source-byte EXT controls. Smoke coverage verifies `SHIFT_RIGHT`, `SHIFT_DOWN`, `SKIP`, `MIN_LETTER_SPACING`, `BACKGROUND`, `CLEAR`, `CLEAR_TO`, and `FILL_WINDOW` side effects, including source-origin cursor targets, min-spacing advance clamping, 2 filled `ClearTextSpan` spans, and 1 `FillWindowPixelBuffer` reset fixture. It also verifies source-byte font/material/language/color-family controls: `FONT`, `RESET_FONT`, `JPN`, `ENG`, `PALETTE`, `COLOR_HIGHLIGHT_SHADOW`, `HIGHLIGHT`, and `TEXT_COLORS`.
  - Screenshot-layout bridge first pass: `BattleScene` now mounts exported RGBA battle assets before claiming pixel equivalence: default `BATTLE_ENVIRONMENT_GRASS` background and entry textures, generated Pokemon battle back/front PNGs, the opponent shadow, and generated singles healthbox frame PNGs are placed on 240x160 screenshot-aligned rects. The runtime snapshot records `battle_presentation_assets.status = exported_asset_layout_first_pass`, `asset_rules.runtime_image_policy = exported_rgba_textures_only`, and `asset_rules.source_equivalence = not_claimed`; source healthbox coordinate metadata from `src/battle_interface.c:sBattlerHealthboxCoords` is preserved separately from these screenshot-aligned top-left rects. The grass background uses a first-pass Godot shader that discards exact zero-RGB gaps over a pale green backdrop; this remains an explicit presentation approximation, not source BG scroll/tile priority equivalence.
  - Full-scene source profile first pass: 24 Chinese Emerald 2011 full-battle 240x160 screenshots are now stored under `assets/source/battle_scene_captures/emerald_2011_zh/capture_00.png` through `capture_23.png` as a scene-layout profile. This profile is separate from the 3 exact transparent window-layer captures expected by `assets/source/battle_window_captures/`; `tools/godot_smoke/battle_scene_source_profile_smoke.gd` verifies count, dimensions, stable signatures, key phases (`action_menu`, `move_menu`, `move_message`, `grass_intro`, `send_out_ball`, `send_out_complete`), and confirms the exact window-layer capture slots remain distinct.
  - Full-scene layout measurement first pass: `battle_scene_source_profile_smoke.gd` now measures 8 key rects directly from the 24-capture profile: capture 00 opponent/player HP green rects `[52,33,48,2]` and `[174,92,48,2]`, capture 00 action prompt red frame/body rects `[1,115,119,42]` and `[8,117,112,38]`, capture 02 full message red frame/body rects `[1,115,238,42]` and `[8,117,224,38]`, and capture 23 opponent/player HP green rects `[52,33,48,2]` and `[179,91,48,2]`. `BattleScene` exposes this as `source_scene_layout_profile`, and its first-pass HP fills now use the capture-00 static 48x2 two-row RGBA layout instead of the older 48x4 Godot rectangle.
  - Keyboard input bridge first pass: `BattleScene._unhandled_input` now routes Godot `ui_accept`, `ui_cancel`, `ui_left`, `ui_right`, `ui_up`, and `ui_down` actions into the intro, action-select, and move-select phases, with visible first-pass action/move cursor labels. This fixes the debug BattleScene path where keyboard actions were not wired and the transparent buttons had `FOCUS_NONE`; full source `HandleInputChooseAction` semantics, disabled actions, Bag/Pokemon/Run flows, sound cues, and controller edge cases remain B8.4 work.
  - Remaining for this task: exact transparent source-capture acquisition/import for the 3 expected action/message/move PNGs under `assets/source/battle_window_captures/`, real link synchronization/recorded action playback/full battle controller flow beyond setup metadata and text-window propagation, and full `RenderText` pixel equivalence beyond the current first-pass control-code side-effect coverage. The comparison gate now exists and currently reports 3 expected captures, 3 missing captures, 0 compared captures, and 0 source-capture pixel diffs while captures are absent; the 24 full-scene profile screenshots are available for layout work but are not used as exact window-layer captures.
  - Current validation: `tools/godot_smoke/data_registry_battle_interface_smoke.gd` verifies the 10 generated composite rects, 25 generated text-info records, 14 source font metric records, 11 source font atlases, 11 source font role atlases, 12 source font atlas/role-mask bindings, 16 RenderText material colors, 317 charmap entries, 12 Latin width table bindings, normal font line advance 16, normal max width 6, narrow move-name width table binding, Chinese low-byte max `0xF6`, and source charmap bytes `F=0xC0`/`P=0xCA`; `tools/godot_smoke/data_registry_battle_strings_smoke.gd` verifies generated glyph spans for `gText_MoveInterfacePP` and a multi-byte first glyph for `gText_MoveInterfaceType`; `tools/godot_smoke/battle_text_printer_smoke.gd` verifies slow/instant player-speed metadata, source `speed - 1` delay setup, speed-zero synchronous text plus layout glyph count, first-frame reveal, one A/B speed-up event, one display-text page wait, one source-text `\p` page wait, source-text `{PAUSE}` metadata, source-text `\l` plus trailing terminator handling, a direct source-byte newline event count of 3 independent of source-text escapes, a two-source-byte glyph span grouping to one source-byte visible event, grouped source glyph layout width 12 px/height 15 px/advance 12 px, source font role-mask status, an `F` charmap glyph crop rect `[0,192,16,16]`, one RenderText color control changing foreground 1 -> 4, source-byte prompt-clear and prompt-scroll metadata, EXT_CTRL_CODE_PAUSE byte args, metadata-only PLAY_SE/WAIT_SE events, and link speed override metadata; `tools/godot_smoke/battle_window_renderer_smoke.gd` verifies action/menu and move/menu 240x160 layer composition, generated source/composite/text rects, source font metric snapshot count 14, source font role-mask binding count 12, generated RenderText material metadata, opaque RGBA pixels, immediate menu text, role-colored bitmap text pixels (`action_menu_text_pixels=2250`), explicit asynchronous message reveal, one renderer-level display page wait, one renderer-level source-record prompt-clear wait from generated bytes with 3 source-byte events, and no runtime palette/source-color keys; `tools/godot_smoke/battle_window_screenshot_smoke.gd` verifies source-backed 240x160 action/message/move layer signatures (`E1635039`, `D256DE44`, `43C20F69`), action menu opaque/text counts 2670/2122, two source `CLEAR_TO` pixel spans, message opaque/text pixels 3478/774, one prompt-clear fill-window effect, four prompt-scroll pixel steps totaling 16 px, move-name/type opaque counts 2048/560, PP label source bytes, source-capture slots expected/missing/compared as 3/3/0, and no runtime palette/source-color keys; `tools/godot_smoke/battle_scene_source_profile_smoke.gd` verifies 24 full-scene source profile captures, 6 key phases, stable signatures, and 8 measured layout rects; `tools/godot_smoke/battle_scene_smoke.gd` verifies `BattleScene` uses the renderer/generated text info, passes generated source bytes and 2 generated glyph spans for the static PP label, passes generated `gText_BattleMenu` source text to the action menu, keeps dynamic action prompt/type text on source-text event streams, exposes the 24-capture full-scene profile and measured layout profile separately from exact window captures, loads 7 screenshot-layout presentation assets, records exported RGBA/no-source-equivalence asset rules, uses 48x2 first-pass HP fill rects, routes 6 direct battle input calls, routes 6 Godot `_unhandled_input` events, and verifies 2 Scene -> Renderer -> TextPrinter battle text controller contexts with recorded intro delay `4` and recorded-link intro delay `1`.
  - Additional text-context validation: `tools/godot_smoke/battle_text_printer_smoke.gd` now verifies recorded speed cases `[8,4,1,0]`, recorded-link delay `1`, `source_battle_text_context_first_pass` snapshots, link/recorded/test-runner auto-scroll reasons, recorded-link flag-only auto-scroll false metadata, and 50-frame auto-scroll release. `tools/godot_smoke/battle_engine_smoke.gd` verifies 3 setup contexts, link setup flags, recorded-link setup flags, and recorded-link setup speed index `2`; `tools/godot_smoke/event_manager_smoke.gd` verifies trainer battle-start sequence text mode `recorded_link`; `tools/godot_smoke/battle_scene_smoke.gd` verifies controller context propagation from BattleEngine-created recorded and recorded-link states into real message-window printers.
  - Additional RenderText-control validation: `tools/godot_smoke/battle_text_printer_smoke.gd` now verifies 7 source-byte EXT controls in one cursor/clear/fill fixture, 2/2 filled clear spans, 1 fill-window reset, 1 min-letter-spacing control, source cursor positions for shift/skip/clear-to controls, plus 8 font/material source-byte EXT controls, 1 font switch, 1 reset-font no-op, 1 palette/material-bank skip, 3 color-family controls, and 2 JPN/ENG language controls.
  - Validate next: supply or record the 3 source capture PNGs so the existing action/message/move gate performs exact pixel comparison, extend link/recorded coverage into real link synchronization/recorded action playback/full battle controller flow beyond setup metadata and text-window propagation, and continue exact RenderText pixel equivalence for remaining control/font/string paths.

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
  - Covers: tag symbol, image table, import-only source color table references, frame table, affine anim table, OAM shape/size.
  - Validate: tags required by Tackle/Ember/Water Gun resolve.

- [ ] B10.3 Convert battle animation sprites.
  - Source: `graphics/battle_anims`.
  - Output: textures under `assets/generated/battle_anims/`.
  - Validate: frame rects, transparency handling, atlas coordinates, and tag-to-texture lookup.

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

## B13 - Debug Battle Launchers

- [x] B13.1 Add debug input map actions.
  - Proposed defaults: `debug_quick_wild_battle` on F6, `debug_trainer_battle_selector` on F7, and optional trainer id increment/decrement/search controls inside the selector.
  - Implemented: `scripts/main.gd` registers runtime `InputMap` actions for F6/F7 and preserves the existing `G` grid toggle.
  - Remaining polish: explicit debug-build gating can be added when the project has a release/dev build split.

- [x] B13.2 Implement quick wild battle launch.
  - Implemented behavior: F6 is a Godot-only developer fixture that selects a random generated species and random level, then launches through `BattleEngine.create_wild_battle_state` and the existing battle-scene handoff.
  - Boundary: this is intentionally not grass/water/fishing encounter parity and does not use encounter rates, slots, Repel/Lure, map metatile behavior, or `MapRuntime`.
  - Metadata: results carry `debug_random_wild_not_source_encounter`; normal battle stats are not incremented, matching the source debug-battle convention more closely than normal wild battle counters.
  - Validate: `tools/godot_smoke/debug_battle_launcher_smoke.gd` proves deterministic species/level selection, temporary player-party fallback, battle state creation, handoff sequence, and no wild battle stat mutation.

- [x] B13.3 Implement trainer battle selector launch.
  - Source: generated trainer records, `BattleSetup_StartTrainerBattle`, `DoTrainerBattle`, `CreateNPCTrainerPartyFromTrainer`, trainer transition selection, and current `BattleEngine.create_trainer_battle_state`.
  - Implemented behavior: F7 selector accepts numeric id, full `TRAINER_*` symbol, or short symbol; invalid ids stay in the selector as validation errors; launch uses `EventManager.request_trainer_battle_start` and `BattleEngine.create_trainer_battle_state`.
  - Boundary: no map object events or trainer sightlines are required; transition hints are passed as explicit debug context.
  - Validate: `tools/godot_smoke/debug_battle_launcher_smoke.gd` resolves Sawyer by full symbol, short symbol, and numeric id; rejects invalid ids; and confirms temporary debug party fallback is not persisted.

- [ ] B13.4 Add debug launcher UI/presentation handoff.
  - Target: `scripts/main.gd` or a small debug overlay scene that can open above the current runtime.
  - Covers: input lock while selecting, current selected trainer id display, search/filter by trainer symbol/name/class, cancel behavior, clear unsupported messages, and transition into `BattleScene`.
  - Current first pass: `scripts/main.gd` creates a compact F7 overlay with a `LineEdit`, Launch/Cancel buttons, input lock, Enter/Escape handling, and BattleScene handoff. Search/filter and screenshot validation remain pending.
  - Validate: screenshot or scene smoke proves the selector is usable at 240x160 without overlapping text.

- [ ] B13.5 Add debug launcher smoke tests.
  - Target files: `tools/godot_smoke/debug_battle_launcher_smoke.gd`, possibly a scene smoke for the selector.
  - Current first pass: `tools/godot_smoke/debug_battle_launcher_smoke.gd` covers launcher contracts without configuring `MapRuntime`; scene-level F6/F7 action smoke still needs a runner that loads project autoloads under headless `--script`.
  - Validate: F6/F7 actions exist, quick wild and selected trainer paths produce battle state contracts, no `MapRuntime` lookup is required, invalid trainer ids are safe, and developer-only metadata is attached to results.

## Suggested Task Order

1. B0.1, B0.2, B0.3 - build the report so all later work is measurable.
2. B13.1 to B13.3 - add developer-only random wild/trainer launchers so battle fixtures can be reached without map dependencies.
3. B1.1 to B1.4 - battle strings and text ids.
4. B2.1 to B2.5 - battle scripts, move effects, and move links.
5. B7.1, B7.2, B7.3, B7.4, B7.6, B7.7, B8.1 - Pokemon/trainer/background/transition/HUD asset imports and coverage reports.
6. B9.1, B9.2 - source-backed static battle composition.
7. B3.1 to B3.5 - VM ordinary damage path.
8. B8.2 to B8.5 - text windows, healthbox, action menu, move menu.
9. B10.1 to B10.6 - first move animation interpreter slice.
10. B4, B5, B6.8, B6.9 - expand Pokemon data, abilities, trainer roster, and logic mechanics through source hooks.
11. B6 - AI, rewards, capture, double battles, and special modes.
12. B9.3 to B9.6 - exact intro, transitions, interaction animation, and post-battle flow.
13. B12 and B13.4 to B13.5 - keep adding fixtures, selector UI, and debug launcher tests as each behavior moves from unsupported to supported.

## Parallel Work Lanes

- Import lane: B1, B2, B7, B8.1, B10.1 to B10.3, B11.
- Rules lane: B3, B4, B5, B6.
- Presentation lane: B8.2 to B8.6, B9, B10.4 to B10.7.
- Verification lane: B0.3 to B0.5, B12.
- Debug lane: B13, which must stay developer-only and map-decoupled.

Each lane can move independently, but no user-visible battle feature is parity-complete until the import, rules, presentation, and verification rows for that feature are all complete.

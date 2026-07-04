# Battle Parity Todo

This page records the first broad audit for a source-equivalent battle experience that is decoupled from map runtime. The target is not a loose battle prototype: battle logic, UI flow, sprites, HUD, effects, move animation scripts, interaction timing, and generated assets must trace the source before being treated as equivalent.

## Audit Snapshot

Godot battle state today:

- `scripts/autoload/battle_engine.gd` is a UI-independent first slice. It builds battle Pokemon, wild battle state, trainer battle state, basic damage, one player move turn, and result contracts.
- `scripts/battle/battle_scene.gd` is explicitly `first_slice_not_source_equivalent`. It has a source-shaped intro -> action select -> move select -> one deterministic player turn flow, but uses Godot controls and simplified rectangles instead of source battle tilemaps, sprites, windows, text printer, and animation systems.
- Generated battle-adjacent data already exists for 1573 species, 935 moves, 21 types, 311 abilities, 874 items, 399 wild encounter records, 855 trainers, 1825 trainer party Pokemon, 1104 learnsets, 25 natures, and 647 evolution entries.
- There is no importer/runtime yet for battle Pokemon sprites, trainer battle sprites, battle backgrounds, battle interface graphics, battle transition graphics, move animation sprite sheets, move animation scripts, battle scripts, battle string tables, or audio playback.

Source battle topology from the first pass:

- `src/battle_setup.c` owns field-to-battle setup and transition selection: `Task_BattleStart`, `BattleSetup_StartWildBattle`, `DoStandardWildBattle`, `DoTrainerBattle`, `GetWildBattleTransition`, and `GetTrainerBattleTransition`.
- `src/battle_main.c` owns battle allocation/init/main loop/intro/turn action execution: `CB2_InitBattle`, `CB2_InitBattleInternal`, `BattleMainCB2`, `DoBattleIntro`, `HandleTurnActionSelectionState`, `SetActionsAndBattlersTurnOrder`, and `RunTurnActionsFunctions`.
- `src/battle_controller_player.c` owns player controller commands, action input, move input, move PP/type/window display, item/party/run actions, trainer slides, and controller command responses.
- `src/battle_script_commands.c`, `data/battle_scripts_1.s`, `data/battle_scripts_2.s`, and `src/data/battle_move_effects.h` own battle script command semantics and move-effect script routing.
- `src/battle_anim.c`, `data/battle_anim_scripts.s`, and `src/data/battle_anim.h` own the animation bytecode interpreter, move/general/status/special animation scripts, animation sprite tags, background effects, waits, blending, sounds, and visual tasks.
- `src/battle_interface.c` owns healthboxes, HP/EXP/status bars, party status summary, ability popups, indicators, last-used-ball and move-info windows.
- `src/battle_bg.c` owns battle BG templates and window templates, including `sStandardBattleWindowTemplates`.
- `src/battle_message.c` and `include/constants/battle_string_ids.h` own battle string ids, battle placeholder expansion, and source battle UI strings such as `gText_WhatWillPkmnDo`, `gText_BattleMenu`, `gText_MoveInterfacePP`, and `gText_MoveInterfaceType`.
- Pokemon/trainer graphic tables live under `src/data/graphics/pokemon.h`, `src/data/graphics/trainers.h`, `src/pokemon_animation.c`, and `src/trainer_pokemon_sprites.c`.

Source asset scope from the first pass:

- `graphics/battle_anims`: 683 files.
- `graphics/battle_environment`: 65 files.
- `graphics/battle_interface`: 77 files.
- `graphics/battle_transitions`: 55 files.
- `graphics/pokemon`: 14213 files.
- `graphics/trainers`: 282 files.
- `graphics/types`: 33 files.

## Architectural Boundary

Battle must remain map-decoupled.

- Map/overworld may emit a battle-start request with plain setup context, player party, trainer id or wild candidate, transition hint, and map-derived metadata.
- Battle logic must not query `MapRuntime` directly. It consumes generated data and plain setup context.
- Battle presentation must not own rules. It consumes battle state/events/animation sequence data and returns user choices or sequence completion.
- Battle importers convert source graphics/scripts/data into generated Godot-friendly assets with trace metadata and unsupported reports.

## Todo Checklist

### 1. Battle Source Trace Inventory

- [ ] Build a source trace index for battle setup, battle main loop, player/opponent controllers, battle script commands, move effects, animation commands, interface/HUD, transitions, messages, Pokemon sprites, trainer sprites, and battle audio cues.
- [ ] Add a generated unsupported report listing every source battle subsystem not yet represented in Godot.
- [ ] Define a stable source-reference schema for battle generated data: file, line, symbol, active preprocessor config, referenced assets, runtime owner, and unsupported notes.
- [ ] Record active battle config values from `include/config/battle.h` and adjacent config headers that affect visible behavior and rules.
- [ ] Decide the first parity target battle scenario, probably a single wild or simple single trainer battle, and trace only that path end to end before broad coverage.

### 2. Generated Data And Asset Import

- [ ] Export battle string ids and battle message text from `src/battle_message.c` plus `include/constants/battle_string_ids.h`, preserving `STRINGID_*`, battle placeholders, source text controls, and Chinese text encoding.
- [ ] Export battle script command labels and instruction streams from `data/battle_scripts_1.s` and `data/battle_scripts_2.s`.
- [ ] Export `src/data/battle_move_effects.h:gBattleMoveEffects`, linking each `EFFECT_*` to its battle script label and flags.
- [ ] Extend move data so each generated move links to its battle effect script, battle animation script symbol, target rules, split/category, flags, additional effects, Z/Max/Tera/Gimmick metadata, and unsupported behavior notes.
- [ ] Export battle animation script labels and instruction streams from `data/battle_anim_scripts.s`.
- [ ] Export battle animation sprite tag metadata from `src/data/battle_anim.h:gBattleAnimTable`.
- [ ] Export battle animation background metadata from `src/data/battle_anim.h:gBattleAnimBackgroundTable` and `graphics/battle_environment`.
- [ ] Convert `graphics/battle_anims` sprite sheets/palettes into normal RGBA atlases while preserving frame sizes, OAM shape metadata, palette tags, and source tag symbols.
- [ ] Convert `graphics/battle_interface` into Godot-friendly textures: textbox, healthboxes, HP/EXP bars, numbers, status icons, type/gimmick indicators, ability popups, party summary balls, last-used-ball, and move-info windows.
- [ ] Convert `graphics/battle_transitions` assets for trainer/wild/frontier/team transitions.
- [ ] Export Pokemon battle sprite asset metadata from `src/data/graphics/pokemon.h`, `graphics/pokemon`, `src/pokemon_animation.c`, and species records: front pic, back pic, normal palette, shiny palette, icon where relevant, gender/form variants, shadow/offset/scale metadata, front animation data, and cry refs.
- [ ] Export trainer battle sprite asset metadata from `src/data/graphics/trainers.h`, generated trainer data, and `graphics/trainers`: front pic, back pic, palette, mugshot/special transition refs, slide-in coordinates.
- [ ] Export battle background/environment metadata from `src/data/graphics/battle_environment.h`, `src/data/battle_environment.h`, and `graphics/battle_environment`.
- [ ] Add import smoke tests for asset existence, alpha handling, palette baking, atlas frame coordinates, and symbol-to-texture lookup.

### 3. Battle Domain Runtime

- [ ] Replace hardcoded `TYPE_EFFECTIVENESS` in `BattleEngine` with generated `gTypeEffectivenessTable` data.
- [ ] Build a source-shaped battle state model for battlers, sides, parties, active battler ids, battle type flags, turn counters, battle resources, field/side statuses, volatile statuses, stat stages, move history, item state, ability state, weather/terrain/room state, and script variables.
- [ ] Implement source RNG contracts for battle: damage roll, accuracy, critical hits, secondary effects, multi-hit counts, AI randomness, wild personality/IV/held item generation, and capture.
- [ ] Implement complete `CalculateBaseDamage`/`DoMoveDamageCalcVars`/modifier stack including critical hits, burn/frostbite, screens, weather, abilities, held items, spread targets, parental/multi-hit rules, protection, immunities, and generation/config branches.
- [ ] Implement accuracy/evasion and move failure checks through the battle script flow rather than ad hoc move-name logic.
- [ ] Implement priority, speed order, action order, switching order, pursuit-like special cases, run/item/party actions, and forced action handling from `SetActionsAndBattlersTurnOrder` and `RunTurnActionsFunctions`.
- [ ] Implement battle script VM opcodes from `src/battle_script_commands.c`, starting with the minimal ordinary attack script path: attack canceler, accuracy check, print attack string, PP decrement, damage calc, type calc, attack animation, healthbar update, data HP update, crit/effectiveness/result messages, faint checks, move end.
- [ ] Implement move effects by consuming generated `gBattleMoveEffects`, not by inferred move names.
- [ ] Implement status systems: non-volatile status, confusion, flinch, attraction, bind/wrap, leech seed, curse, perish song, encore, taunt, torment, heal block, protection, substitute, recharge, charge turns, semi-invulnerable states, and source cleanup order.
- [ ] Implement ability behavior using generated ability flags plus source C tracing for switch-in, on-move, on-damage, end-turn, suppression/copy/swap/overwrite, AI visibility, and popup timing.
- [ ] Implement held item behavior using generated item data and source C tracing for berries, damage modifiers, status cures, focus sash/band, choice/assault items, gems/plates/drives/memories, and item consumption messages.
- [ ] Implement trainer AI from `src/battle_ai_*`, including move scoring, switching, item use, double battle considerations, and source AI flags from generated trainer data.
- [ ] Implement EXP, EVs, money/rewards, item rewards, pickup/payday, friendship, level-up, move learning, evolution-after-battle handoff, trainer flags/rematches, and post-battle scripts.
- [ ] Implement capture, ball shake logic, Safari actions, Wally tutorial special flow, run-away rules, and wild flee behavior.
- [ ] Implement single, double, two-opponent, partner, multi, link/recorded, Safari, Battle Frontier/Pike/Pyramid/Dome/Arena/Palace/Tent, Dynamax/Tera/Z/other expansion battle modes as separate traced slices.

### 4. Battle Presentation Runtime

- [ ] Replace `BattleScene` Godot controls/rectangles with source-backed battle viewport composition at 240x160.
- [ ] Build a battle renderer that layers background planes, battler sprites, trainers, healthboxes, windows, text, animation sprites, blend/fade effects, and transitions from structured runtime state.
- [ ] Implement source text windows and battle text printer behavior from `src/battle_bg.c`, `src/battle_message.c`, and source window/text info.
- [ ] Implement action menu input, cursor movement, B/cancel behavior, disabled action rules, menu sounds as metadata first, and then audio playback when audio scope opens.
- [ ] Implement move select UI: four move windows, PP, type label, target select, move descriptions, effectiveness overlay, Z/Max/Tera/Gimmick triggers, cursor positions, and PP-zero behavior.
- [ ] Implement party screen handoff, bag handoff, run confirmation/failure flow, yes/no windows, target selection, and multi-action partner prompts.
- [ ] Implement healthbox creation, slide-in/out, HP drain/restore timing, EXP bar timing, level/status text, status icons, party status summary, bounce effects, indicators, ability popups, and last-used-ball/move-info overlays.
- [ ] Implement Pokemon send-out, trainer slide-in/out/back, Pokeball throw/shake/capture, faint animation, return-to-ball, switch-in, shiny animation, cry wait/restored BGM metadata, and ball animation waits.
- [ ] Implement battle transitions selected by `BattleEngine` metadata: wild, trainer, mugshot, Magma/Aqua, legendary, frontier, pyramid, dome, team and special transitions.
- [ ] Implement exact battle intro sequence from `DoBattleIntro`, including background loading, battler placement, intro message, send-out text, trainer text, and state waits.
- [ ] Implement exact post-battle presentation: faint/result messages, EXP/level-up/move-learning windows, money, trainer defeat text, capture/nickname/send-to-box messages, whiteout, and return-to-field callback handoff.

### 5. Battle Animation System

- [ ] Create a Godot battle animation interpreter for `data/battle_anim_scripts.s` commands traced in `src/battle_anim.c`.
- [ ] Implement animation commands for loading/unloading sprite graphics, creating sprites, creating sprites on targets, delays, waits, visual tasks, calls/returns/gotos, arg mutation, pan/sound metadata, battler invisibility/visibility, alpha/blend, BG changes/fades, mon BG masks, split priorities, and contest branches where relevant.
- [ ] Implement source visual tasks from `src/battle_anim_*` files as Godot-native tasks with equivalent timing and end conditions.
- [ ] Implement battler sprite affine/translation/blend helpers used by move animations.
- [ ] Implement general/status/special animations from `src/battle_anim.c` and `data/battle_anim_scripts.s` in addition to move animations.
- [ ] Build an asset coverage report showing each move's `battleAnimScript` symbol, required animation tags, required visual tasks, required sounds, and current runtime support status.
- [ ] Start with a tiny verified animation set, for example Tackle, Ember, Water Gun, stat up/down, status infliction, faint, and Pokeball throw, then expand by source tag/task coverage.

### 6. Audio Metadata And Later Playback

- [ ] Preserve battle music, cries, fanfares, and sound-effect symbols in generated data and runtime sequence events.
- [ ] Trace source cue timing in battle setup, intro, controller commands, animation scripts, UI input, healthbar drain, fainting, capture, level-up, and victory.
- [ ] Keep playback unsupported until the project reopens audio scope; do not use approximated replacement sounds.
- [ ] When audio scope opens, import source `sound/` assets through the existing source build/conversion path and verify cue timing against animation/event sequences.

### 7. Verification

- [ ] Add importer tests for battle strings, battle scripts, move effects, animation scripts, animation assets, interface assets, Pokemon sprites, trainer sprites, and battle environments.
- [ ] Add domain smoke tests for the ordinary attack battle script path, type chart from generated data, accuracy/miss, crit, status move, stat move, faint, switch, item use, run, capture, trainer win/loss, and end-turn effects.
- [ ] Add presentation smoke tests with screenshot or pixel checks for source-backed battle scene composition at 240x160 and scaled windows.
- [ ] Add animation smoke tests for sprite creation, delays/waits, blend/fade, BG transitions, battler movement, healthbox visibility during animations, and move-specific visual sequences.
- [ ] Add parity fixtures for a few source-known battles and compare ordered event logs: input prompts, selected actions, messages, HP/PP changes, animation sequence ids, waits, and battle result.
- [ ] Ensure every non-equivalent behavior remains visible through `unsupported` metadata and wiki notes.

## Suggested Implementation Order

1. Build the battle source/generated coverage report first. This prevents the next slices from hiding gaps.
2. Import battle UI assets and Pokemon/trainer sprites for one verified single battle.
3. Replace the current battle scene rectangles with source-backed textures and static sprite placement.
4. Add a battle script VM for the ordinary damaging move path and route `MOVE_TACKLE`, `MOVE_EMBER`, and `MOVE_WATER_GUN` through source scripts.
5. Add the first animation interpreter slice for those moves and healthbox HP updates.
6. Extend battle input to full action and move selection before broad move-effect coverage.
7. Add rewards/post-battle flow only after a full single-battle loop can finish source-equivalently.


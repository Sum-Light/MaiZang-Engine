# Roadmap

## Milestone 0 - Knowledge Base and Skill

- Create project wiki.
- Create project-specific Codex skill.
- Establish update protocol for future Q&A and work sessions.

## Milestone 1 - Godot Foundation

- Add project directory structure. Done.
- Add `Main.tscn`, runtime autoloads, and basic input map. Main scene and autoloads are done; movement currently uses default `ui_*` actions.
- Add placeholder player scene with grid movement. Done.
- Add smoke-test scene startup.

## Milestone 2 - Import Pipeline

- Read source path from local config. First pass done with `tools/import_config.example.json`.
- Parse `layouts.json` and `map.json`. First probe done for `LittlerootTown`.
- Decode layout `map.bin` into metatile ids, collision values, elevation values, and raw u16 map-grid values. First pass done for `LittlerootTown`.
- Build a generated manifest for maps, layouts, and tilesets. First map manifest done for `LittlerootTown`.
- Report missing or unsupported data without failing the whole import. First probe report implemented for required files and first-slice assets.

## Milestone 3 - Map Rendering Slice

- Convert one tileset pair used by `LittlerootTown`. First pass done for `gTileset_General` + `gTileset_Petalburg` as a palette-baked RGBA metatile atlas.
- Render `LittlerootTown` in Godot. Debug rendering now uses generated map ids plus the generated metatile atlas; real TileMapLayer rendering remains.
- Add collision and movement permissions. First pass done with generated map-grid collision through `MapRuntime`; metatile behavior-specific movement rules remain.
- Spawn object events from `map.json`. First pass done as visible placeholders with occupied-cell blocking; real overworld sprites and event scripts remain.

## Milestone 4 - Event Script Slice

- Index object, BG/sign, and warp events for interaction lookup. First pass done in `MapRuntime`.
- Add an interaction dispatcher path from player facing direction to debug dialogue. First pass done with `EventManager`; real script execution remains.
- Parse `.inc` event scripts into labels and instructions. First pass done for `LittlerootTown`, including script labels, movement labels, local text labels, and direct `msgbox`/`message` references.
- Preview simple generated dialogue from object/BG event scripts. First pass done through `EventManager.get_script_preview`; this is not a full `ScriptVM`.
- Add a minimal `ScriptVM` execution path. First pass done for synchronous dialogue scripts, including `msgbox`, `message`, source-derived `MSGBOX_NPC/SIGN/DEFAULT` expansion, basic flow control, simple flag/var operations, and VM result reporting.
- Support a minimal ScriptVM command set:
  - `msgbox`. First pass done for `MSGBOX_NPC`, `MSGBOX_SIGN`, and `MSGBOX_DEFAULT`.
  - `setflag`, `clearflag`, `checkflag`. First pass done for `setflag` and `clearflag`.
  - `setvar`, `addvar`, `compare`. First pass done for `setvar` and simple branch-time var reads.
  - `goto`, `call`, `return`, `end`. First pass done.
  - `goto_if_eq`, `call_if_eq`, `call_if_set`, `call_if_unset`. First pass done for set/unset/eq/ne variants used by the first slice.
  - `warp`, `warpsilent`
  - `applymovement`, `waitmovement`
  - `lock`, `lockall`, `release`, `releaseall`. First pass records execution effects; real object freezing remains.
  - `showobject`, `hideobject`, `addobject`, `removeobject`

## Milestone 5 - Text Pipeline

- Parse `charmap.txt`.
- Extract text macros and labels.
- Convert text into UTF-8 Godot resources.
- Preserve control codes and placeholders.

## Milestone 6 - Pokemon Data Slice

- Export species, moves, abilities, items, wild encounters, and trainers.
- Build `DataRegistry` accessors.
- Add validation for cross-references.

## Milestone 7 - Battle Prototype

- Implement simple single battle.
- Add type chart, damage formula, move PP, HP, fainting, and battle messages.
- Keep battle rules separate from UI.

## Milestone 8 - Full Game Systems

- Party menu, bag, Pokemon summary, Pokedex, shops, healing, saving, and overworld effects.
- Expand event script support by unsupported-opcode reports.
- Add advanced expansion mechanics after the base loop is stable.

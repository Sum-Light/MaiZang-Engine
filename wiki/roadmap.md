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

- Convert one tileset pair used by `LittlerootTown`.
- Render `LittlerootTown` in Godot. Temporary debug-palette rendering from generated metatile ids is done; real TileMap/metatile rendering remains.
- Add collision and movement permissions from metatile attributes.
- Spawn object events from `map.json`.

## Milestone 4 - Event Script Slice

- Parse `.inc` event scripts into labels and instructions.
- Support a minimal ScriptVM command set:
  - `msgbox`
  - `setflag`, `clearflag`, `checkflag`
  - `setvar`, `addvar`, `compare`
  - `goto`, `call`, `return`, `end`
  - `goto_if_eq`, `call_if_eq`, `call_if_set`, `call_if_unset`
  - `warp`, `warpsilent`
  - `applymovement`, `waitmovement`
  - `lock`, `lockall`, `release`, `releaseall`
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

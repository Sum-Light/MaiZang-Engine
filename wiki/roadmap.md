# Roadmap

## Milestone 0 - Knowledge Base and Skill

- Create project wiki.
- Create project-specific Codex skill.
- Establish update protocol for future Q&A and work sessions.

## Milestone 1 - Godot Foundation

- Add project directory structure.
- Add `Main.tscn`, runtime autoloads, and basic input map.
- Add placeholder player scene with grid movement.
- Add smoke-test scene startup.

## Milestone 2 - Import Pipeline

- Read source path from local config.
- Parse `layouts.json` and `map.json`.
- Decode layout `map.bin` into metatile IDs.
- Build a generated manifest for maps, layouts, and tilesets.
- Report missing or unsupported data without failing the whole import.

## Milestone 3 - Map Rendering Slice

- Convert one tileset pair used by `LittlerootTown`.
- Render `LittlerootTown` in Godot.
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

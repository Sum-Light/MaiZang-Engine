# Import Pipeline

## Principle

Keep source data authoritative and conversion reproducible.

Godot should consume generated data, not raw GBA build files at runtime. This keeps the runtime simpler and makes import failures easy to inspect.

## Inputs

### Maps

- `data/maps/*/map.json`
- `data/maps/*/scripts.inc`
- `data/layouts/layouts.json`
- `data/layouts/*/map.bin`
- `data/layouts/*/border.bin`

### Tilesets

- `data/tilesets/primary/*/tiles.png`
- `data/tilesets/secondary/*/tiles.png`
- `data/tilesets/**/metatiles.bin`
- `data/tilesets/**/metatile_attributes.bin`
- `data/tilesets/**/palettes/*.pal`
- `include/constants/metatile_behaviors.h`
- `include/constants/metatile_labels.h`
- `src/field_door.c`
- `graphics/door_anims/*.png`

### Gameplay Data

- `src/data/wild_encounters.json`
- `src/data/trainers.party`
- `src/data/pokemon/species_info.h`
- `src/data/moves_info.h`
- `src/data/items.h`
- `src/data/abilities.h`
- `src/data/pokemon/level_up_learnsets/gen_*.h`
- `src/pokemon.c:gNaturesInfo`
- `src/data/pokemon/species_info.h` `.evolutions = EVOLUTION(...)` entries
- `include/constants/*.h`

### Text

- `charmap.txt`
- `tools/preproc/charmap.cpp`
- `tools/preproc/string_parser.cpp`
- `tools/preproc/c_file.cpp`
- `tools/preproc/asm_file.cpp`
- `data/text/*.inc`
- `asm/macros/event.inc`
- `src/scrcmd.c`
- `include/constants/characters.h`
- `include/constants/global.h`
- text labels inside map scripts
- C macros such as `_("")` and `COMPOUND_STRING()`

### Event Script Semantics

- `data/maps/*/scripts.inc` for map-local labels, command streams, movement labels, and local text labels
- `data/scripts/*.inc` shared script includes for labels, common movement scripts, and shared text labels referenced by map scripts
- `src/scrcmd.c` for script command implementations
- Field/event modules referenced by commands, including object movement, map transitions, field effects, doors, sounds, flags, vars, and message handling
- Referenced resources such as movement labels, text labels, object graphics, fanfares/sound effects, map layouts, metatile behaviors, and warp destinations

## Outputs

Recommended generated output layout:

```text
assets/generated/
  maps/
  tilesets/
  door_anims/
  sprites/
  ui/
data/generated/
  maps/
  scripts/
  pokemon/
  battle/
  text/
  import_manifest.json
  import_report.json
```

## Validation

Each import run should report:

- maps imported
- maps skipped
- missing layouts
- missing tilesets
- missing object graphics
- unsupported script instructions
- unresolved labels
- invalid warp targets
- text decode failures
- charmap encoding warnings
- script command implementations that have not yet been traced to source C behavior

## Source Behavior Rule

Generated JSON is an index and interchange format, not proof that an opcode or gameplay feature has been correctly implemented.

Before implementing a script instruction, gameplay feature, source function, or code-backed system in Godot, inspect the matching source C logic and the resources it references. Use that source behavior to design the Godot implementation, aiming for visible behavior and rules consistent with the original project while keeping the runtime Godot-native. If exact behavior is deferred, the generated data or runtime should report the approximation.

GBA hardware graphics and resource formats are an exception to runtime fidelity: palettes, 4bpp tiles, binary metatiles, packed map blocks, and similar platform/storage constraints should be decoded during import into ordinary Godot images/data. The importer should preserve enough source metadata for debugging and special cases, but the Godot runtime should not reproduce GBA palette, tile-memory, or binary packing constraints just because the source format used them. Gameplay systems should follow the same principle by matching visible rules and outcomes while using Godot-native data and runtime structures.

Importers should prefer partial success plus a clear report over all-or-nothing failure.

## Current Tooling

`tools/importer/source_probe.py` is the first read-only importer utility. It accepts `--config`, `--source`, `--map`, and optional `--write-report`.

Current checks:

- source root exists
- required source files exist
- map/layout counts
- first-slice `map.json` and `scripts.inc`
- first-slice layout lookup
- layout blockdata and border files
- primary and secondary tileset files

`tools/importer/export_map.py` exports one source map into generated Godot-friendly JSON. It accepts `--config`, `--source`, `--map`, and `--output-root`.

Current export behavior:

- Reads `data/maps/<Map>/map.json`, `data/maps/<Map>/scripts.inc`, and `data/layouts/layouts.json`.
- Decodes `data/layouts/<Layout>/map.bin` as little-endian u16 map-grid entries.
- Uses `include/global.fieldmap.h` masks: bits 0-9 are metatile id, bits 10-11 are collision, and bits 12-15 are elevation.
- Decodes `data/layouts/<Layout>/border.bin` and writes `border_grid` metadata for the Emerald `src/fieldmap.c:GetBorderBlockAt` rule, including `MAP_OFFSET = 7`, the parity index expression, source runtime coordinate note, and impassable collision fallback.
- Writes `data/generated/maps/littleroot_town.json` for the current first slice.
- Updates `data/generated/import_manifest.json` with exported map id, name, path, layout id, and size while preserving existing entries for other maps, tilesets, and scripts.
- Preserves source event arrays for connections, object events, warps, coordinate events, and background events.
- Preserves existing script manifest entries when updating the shared import manifest.

`tools/importer/export_tilesets.py` exports one map's primary/secondary tileset pair into a palette-baked metatile atlas. It accepts `--config`, `--source`, `--map`, `--output-data-root`, and `--output-asset-root`.

Current tileset export behavior:

- Reads the map layout's primary and secondary tileset symbols.
- Reads `tiles.png`, `metatiles.bin`, `metatile_attributes.bin`, and `palettes/*.pal` for both tilesets.
- Uses GBA tile-entry bits from `tools/gbagfx/gfx.h`: 10-bit tile id, horizontal flip, vertical flip, and 4-bit palette number.
- Parses `include/constants/metatile_behaviors.h` so generated metatile attributes carry source behavior names as well as numeric ids.
- Parses `include/constants/metatile_labels.h` and `src/field_door.c` so used animated-door metatiles can resolve their source animation image, palette slots, frame order, and sound intent.
- Writes a generated `metatile_labels` table from `include/constants/metatile_labels.h` so runtime script commands such as `setmetatile` can resolve source `METATILE_*` symbols without hardcoded Godot ids.
- Builds source palette slots with primary palettes 0-5 and secondary palettes 6-12, then bakes colors into a normal RGBA PNG.
- Flattens each 16x16 metatile by compositing bottom entries 0-3 and top entries 4-7.
- Bakes supported source door animation tile strips into normal RGBA frame atlases under `assets/generated/door_anims/`; palette numbers are used only at import time.
- Writes `assets/generated/tilesets/littleroot_town_metatiles.png`.
- Writes `data/generated/tilesets/littleroot_town.json` with atlas metadata, source tile entries, metatile attributes, metatile behavior names, metatile label ids, used metatile ids, coverage notes, and warnings.
- Writes generated `door_animations` metadata into the tileset JSON for supported used door metatiles, including source labels, metatile ids, frame size, frame rectangles, 60fps frame timing, open/close frame indices, and source sound-effect symbol.
- Updates `data/generated/import_manifest.json` with exported tileset metadata while preserving existing entries for other maps, tilesets, and scripts.

`tools/importer/export_event_scripts.py` exports one map's `scripts.inc`, or a named shared script bundle, into generated Godot-friendly JSON. It accepts `--config`, `--source`, `--map`, `--output-root`, `--shared-name`, and repeatable `--include-script`.

Current event script export behavior:

- Reads `data/maps/<Map>/scripts.inc` or the requested shared include files as UTF-8 and writes generated JSON with LF endings through the shared importer JSON writer.
- Loads `charmap.txt` and follows the source preprocessor model from `tools/preproc/charmap.cpp`, `tools/preproc/string_parser.cpp`, and `tools/preproc/c_file.cpp` for text-byte validation.
- Parses labels, map script tables, script instruction streams, movement labels, and local `.string` text labels. Shared bundles preserve each label/instruction `source_file` so runtime/debug output can trace records back to the include that defined them.
- Records per-script raw operations, direct `msgbox`/`message` references, call/goto references, and simple runtime preview summaries.
- Keeps Godot display text as UTF-8 while preserving source charmap encoding metadata for each local text label: status, source bytes, source hex, byte count, `$` terminator presence, control codes, placeholders, and warnings.
- Converts display escapes for preview/runtime text: `\n` and `\l` become newlines, `\p` becomes a blank line, and trailing `$` terminators are removed from `display_text`.
- Records source behavior traces for supported preview behavior from `src/scrcmd.c`, `data/event_scripts.s`, and `data/scripts/std_msgbox.inc`.
- Updates `data/generated/import_manifest.json` with exported map-script or shared-script metadata while preserving existing entries for other maps, tilesets, scripts, and text datasets. Shared bundle manifest entries use `scope = "shared"` and store their included source files.

`tools/importer/export_text.py` exports global `data/text/*.inc` labels into generated Godot-friendly JSON. It accepts `--config`, `--source`, `--output-root`, and repeatable `--file`.

Current global text export behavior:

- Reads all `data/text/*.inc` files as UTF-8.
- Parses normal `.string` labels and keeps UTF-8 `display_text` plus source charmap encoding metadata: status, source bytes, source hex, byte count, `$` terminator presence, control codes, placeholders, and warnings.
- Parses `.braille` labels and the preceding `brailleformat` header. The 6-byte header is preserved in `braille_format` and `source_bytes.format_header`, while generated braille text bytes are derived from `tools/preproc/asm_file.cpp:AsmFile::ReadBraille` and `include/constants/characters.h`.
- Records `source_pointer_skip_bytes = 6` for braille labels because `ScrCmd_braillemessage` reads the pointer plus 6 bytes before expanding the string.
- Handles the currently used global text preprocessor branch `#if IS_FRLG/#else/#endif` with `IS_FRLG = false`, traced to `include/constants/global.h`, so generated text matches the Emerald branch.
- Writes `data/generated/text/global_text.json` with source metadata, per-file counts, label index, text records, reports, and stats.
- Updates `data/generated/import_manifest.json` with a `texts` entry while preserving existing map, tileset, and script entries.

`tools/importer/export_species.py` exports the active Pokemon species initializer table into generated Godot-friendly JSON. It accepts `--config`, `--source`, and `--output-root`.

Current species export behavior:

- Reads `src/data/pokemon/species_info.h` plus included `species_info/gen_*_families.h` files after evaluating source config branches from `include/config/general.h`, `include/config/battle.h`, `include/config/overworld.h`, `include/config/pokemon.h`, and `include/config/species_enabled.h`.
- Reads species, type, growth-rate, body-color, ability, item, cry, national-dex, egg-group, and gender constants from source headers, then stores source symbols and numeric values together in generated records.
- Parses explicit struct initializers into source-backed fields for base stats, EV yields, catch rate, exp yield, gender ratio, egg cycles, friendship, dimensions, display text, types, abilities, egg groups, growth rate, body color, dex number, held items, flags, graphics references, learnset references, evolution references, and form-table references.
- Converts source species/category/description string literals to Godot-facing UTF-8 `display_text` while keeping source-facing raw text fields.
- Preserves macro-generated initializers as partial `macro_call` records with raw macro text, arguments, source location, and warnings until the relevant C macros and referenced resources are traced deeply enough for safe expansion.
- Writes `data/generated/pokemon/species.json` and updates `data/generated/import_manifest.json` with a `pokemon` entry for category `species`.

Latest verified species export:

- generated path: `data/generated/pokemon/species.json`
- manifest category: `pokemon` / `species`
- active species initializers: 1573
- struct initializers: 1366
- macro-call partial initializers: 207
- species with complete first-pass base stats: 1329
- preprocessor decisions: 2043
- preprocessor warnings: 0
- deliberate macro-partial warnings: 207
- unsupported field notes: 2879

`tools/importer/export_moves.py` exports the active move initializer table into generated Godot-friendly JSON. It accepts `--config`, `--source`, and `--output-root`.

Current moves export behavior:

- Reads `src/data/moves_info.h` after evaluating active source config branches from `include/config/general.h`, `include/config/battle.h`, `include/config/contest.h`, `include/config/overworld.h`, `include/config/pokemon.h`, and `include/config/item.h`.
- Reads move, battle effect, type, damage category, target, additional move effect, Z move, contest, combo starter, weather/status, hold effect, ability, and species constants from source headers.
- Parses explicit `struct MoveInfo` initializers from `include/move.h` fields into source-backed core battle fields, flags, ban flags, arguments, additional effects, contest fields, and battle animation script symbols.
- Converts source move names and descriptions from `COMPOUND_STRING(...)`/`_("")`-style C string literals into UTF-8 `display_text` while preserving source-facing raw text fields and shared description symbols.
- Writes `data/generated/pokemon/moves.json` and updates `data/generated/import_manifest.json` with a `pokemon` entry for category `moves`.
- Treats generated move records as data and source-symbol provenance for later battle/runtime work. Move effect behavior, targeting, animation scripts, contest behavior, and additional-effect execution still require separate source C/resource tracing before Godot implementation.

Latest verified moves export:

- generated path: `data/generated/pokemon/moves.json`
- manifest category: `pokemon` / `moves`
- active move initializers: 935
- moves with complete first-pass core battle fields: 935
- moves with additional-effect records: 337
- shared text records: 24
- preprocessor decisions: 77
- preprocessor warnings: 0
- export warnings: 0
- unsupported fields: 0

`tools/importer/export_abilities.py` exports the active ability initializer table into generated Godot-friendly JSON. It accepts `--config`, `--source`, and `--output-root`.

Current ability export behavior:

- Reads `src/data/abilities.h` after evaluating active source config values from `include/config/general.h` and `include/config/battle.h`.
- Reads ability constants from `include/constants/abilities.h` and traces the `struct AbilityInfo` shape from `include/pokemon.h`.
- Parses explicit `struct AbilityInfo` initializers into source-backed ability records with ids, names, descriptions, `ai_rating`, copy/swap/trace/suppress/overwrite/breakable/Imposter flags, raw fields, raw flag expressions, source locations, and explicit C default markers for omitted zero/false fields.
- Converts source ability names and descriptions from `COMPOUND_STRING(...)`/`_("")`-style C string literals into UTF-8 `display_text` while preserving source-facing raw text fields.
- Writes `data/generated/pokemon/abilities.json` and updates `data/generated/import_manifest.json` with a `pokemon` entry for category `abilities`.
- Treats generated ability records as source-traceable data for later battle, overworld, UI, and AI work. Ability behavior, popups, summary/Pokedex display, overworld effects, and copy/swap/suppress/overwrite semantics still require separate source C/resource tracing before Godot implementation.

Latest verified abilities export:

- generated path: `data/generated/pokemon/abilities.json`
- manifest category: `pokemon` / `abilities`
- active ability initializers: 311
- records with explicit `aiRating`: 310
- records with at least one present flag field: 122
- records with at least one true flag after active config evaluation: 120
- preprocessor decisions: 0
- preprocessor warnings: 0
- export warnings: 0
- unsupported fields: 0

`tools/importer/export_items.py` exports the active item initializer table and item effect byte arrays into generated Godot-friendly JSON. It accepts `--config`, `--source`, and `--output-root`.

Current item export behavior:

- Reads `src/data/items.h` and `src/data/pokemon/item_effects.h` after evaluating active source config branches from `include/config/general.h`, `include/config/battle.h`, `include/config/overworld.h`, `include/config/item.h`, `include/config/save.h`, and `include/config/pokemon.h`.
- Reads item, pocket, item sort, item use type, battle usage, hold effect, Pokeball, type, stat, move, nature, item effect, and TM/HM alias constants from source headers.
- Parses explicit `struct ItemInfo` initializers from `include/item.h` fields into source-backed records with ids, text, price/sell price, pocket/sort/type/battle-usage fields, secondary ids, hold effects, field-use function symbols, item effect symbols, icon symbols, source locations, raw fields, and C default markers.
- Converts source item names and descriptions from `_("")`, `COMPOUND_STRING(...)`, `ITEM_NAME(...)`, `ITEM_PLURAL_NAME(...)`, and shared text references into UTF-8 `display_text` while preserving source-facing raw text fields.
- Parses `src/data/pokemon/item_effects.h` designated byte arrays, preserving source symbols, lengths, evaluated values, u8 byte values, and expanded source helper macros for friendship changes.
- Resolves source TM/HM aliases such as `ITEM_TM_THUNDER` and `ITEM_HM_CUT` from `include/constants/tms_hms.h` so generated records keep their source numeric item ids even though the source enum uses macro expansion.
- Writes `data/generated/pokemon/items.json` and updates `data/generated/import_manifest.json` with a `pokemon` entry for category `items`.
- Treats generated item records as source-traceable data for later bag, shop, berry, held-item, Pokeball, field-use, and battle-item systems. The generated data records source symbols needed for that work; it does not by itself define Godot behavior.

Latest verified items export:

- generated path: `data/generated/pokemon/items.json`
- manifest category: `pokemon` / `items`
- active item initializers: 874
- `ITEMS_COUNT`: 874
- highest item id: 873
- item records with effect references: 139
- parsed item effect byte arrays: 72
- preprocessor decisions: 254
- preprocessor warnings: 0
- export warnings: 0
- unsupported fields: 0

`tools/importer/export_wild_encounters.py` exports source wild encounter tables into generated Godot-friendly JSON. It accepts `--config`, `--source`, and `--output-root`.

Current wild encounter export behavior:

- Reads `src/data/wild_encounters.json`.
- Traces the source generated-header semantics from `tools/wild_encounters/wild_encounters_to_header.py`, `include/wild_encounter.h`, `include/constants/wild_encounter.h`, `include/constants/rtc.h`, `include/config/overworld.h`, and `include/config/dexnav.h`.
- Reconstructs map group/number constants from `data/maps/map_groups.json`, using `tools/mapjson/required_map_defines.json` only for required-map fallback symbols.
- Reads species constants from `include/constants/species.h` so each slot stores source species symbol and numeric id.
- Exports land, water, rock smash, and fishing tables with encounter rates, slot levels, source slot probabilities, cumulative thresholds, and fishing rod probability groups.
- Records the current time-of-day encounter config: `OW_TIME_OF_DAY_ENCOUNTERS = FALSE`, generated fallback `TIME_MORNING`, and runtime `TIME_OF_DAY_DEFAULT`.
- Records source runtime references such as `src/wild_encounter.c`, `src/field_control_avatar.c`, `src/metatile_behavior.c`, DexNav/Pokedex/Match Call references, fishing, Sweet Scent, roamer, Battle Pike, and Battle Pyramid files for later behavior work.
- Records `MAP_ALTERING_CAVE` as a special case selected by `VAR_ALTERING_CAVE_WILD_SET` and `NUM_ALTERING_CAVE_TABLES`.
- Writes `data/generated/pokemon/wild_encounters.json` and updates `data/generated/import_manifest.json` with a `pokemon` entry for category `wild_encounters`.
- Treats generated encounter records as source-traceable data for later overworld encounter runtime work. Step encounter checks, Repel, abilities, surfing/fishing state, DexNav, mass outbreaks, Feebas, roamers, and battle setup remain separate source-backed implementations.

Latest verified wild encounter export:

- generated path: `data/generated/pokemon/wild_encounters.json`
- manifest category: `pokemon` / `wild_encounters`
- header groups: 3
- encounter records: 399
- map encounter records: 388
- land/water/rock-smash/fishing table counts: 332 / 155 / 34 / 153
- total wild-mon slots: 6459
- unique species: 222
- export warnings: 0
- unsupported fields: 0

`tools/importer/export_trainers.py` exports source trainer party data into generated Godot-friendly JSON. It accepts `--config`, `--source`, and `--output-root`.

Current trainer export behavior:

- Reads `src/data/trainers.party` as UTF-8 and parses the same trainer DSL consumed by `tools/trainerproc/main.c`.
- Traces generated-header behavior from `tools/trainerproc/main.c` and `include/data.h`, including default trainer difficulty, source default Pokemon level 100, default IVs 31/31/31/31/31/31, C-defaulted held item/ability/nature/shiny fields, battle type, AI flags, trainer items, mugshots, starting status, and party-size/pool fields.
- Resolves trainer ids, trainer classes, trainer pics, encounter music, trainer genders, mugshot colors, AI flags, battle types, difficulties, pool constants, Pokemon species, moves, items, abilities, balls, natures, and types from source headers.
- Preserves trainer names and nicknames as UTF-8 `display_text` while avoiding shell-encoding based edits to source Chinese text.
- Preserves per-Pokemon explicit moves; Pokemon without explicit moves are marked with `move_source_behavior.kind = "level_up_default"` from `src/battle_main.c:CustomTrainerPartyAssignMoves`.
- Preserves source rewrite rules from `trainerproc`, including gendered species such as `Nidoran (M)` -> `Nidoran-M` and itemed forms such as `Arceus-Fire` -> `Arceus @ Flame Plate`, even though the current source trainer file does not use those cases.
- Writes `data/generated/pokemon/trainers.json` and updates `data/generated/import_manifest.json` with a `pokemon` entry for category `trainers`.
- Treats generated trainer records as source-traceable data for later battle runtime work. Enemy party construction, AI behavior, pool selection, trainer transition/mugshot presentation, battle music, exact send-out timing, party move fallback, and item/ability behavior still require separate source-backed Godot implementation.

Latest verified trainer export:

- generated path: `data/generated/pokemon/trainers.json`
- manifest category: `pokemon` / `trainers`
- trainers: 855
- `TRAINERS_COUNT`: 855
- highest trainer id: 854
- party Pokemon: 1825
- double battles: 77
- trainers with explicit items: 141
- trainers with AI flags: 839
- mugshot trainers: 5
- Pokemon with explicit move lists: 436
- Pokemon using source level-up default moves: 1389
- held-item Pokemon: 142
- unique trainer species: 208
- unique trainer moves: 210
- warnings: 0
- unsupported fields: 0
- unresolved constants: 0

`tools/importer/export_learnsets.py` exports the active Pokemon level-up learnset table into generated Godot-friendly JSON. It accepts `--config`, `--source`, and `--output-root`.

Current level-up learnset export behavior:

- Reads `include/config/pokemon.h` and related generation config to select the active `src/data/pokemon/level_up_learnsets/gen_*.h` file; the current source target selects `GEN_9`.
- Parses `LEVEL_UP_MOVE(level, MOVE_*)` entries into ordered per-species learnset records while preserving source labels, source locations, move symbols, numeric move ids, levels, level-zero entries, and unresolved-move reporting.
- Records runtime behavior references for source default trainer moves, including `src/battle_main.c:CustomTrainerPartyAssignMoves`, `src/pokemon.c:GiveBoxMonInitialMoveset`, `src/pokemon.c:GetSpeciesLevelUpLearnset`, and `src/pokemon.c:GetMovePP`.
- Writes `data/generated/pokemon/learnsets.json` and updates `data/generated/import_manifest.json` with a `pokemon` entry for category `learnsets`.
- Treats generated learnset records as source-traceable data for battle, party creation, evolution, relearning, UI, and broader move-learning work. Only the trainer default initial-moves slice is currently implemented in `BattleEngine`.

Latest verified level-up learnset export:

- generated path: `data/generated/pokemon/learnsets.json`
- manifest category: `pokemon` / `learnsets`
- active generation: `GEN_9`
- learnsets: 1104
- move entries: 16616
- level-zero move entries: 294
- preprocessor decisions: 640
- warnings: 0
- unresolved moves: 0

`tools/importer/export_natures.py` exports source nature data into generated Godot-friendly JSON. It accepts `--config`, `--source`, and `--output-root`.

Current nature export behavior:

- Reads `src/pokemon.c:gNaturesInfo` after tracing `include/pokemon.h:struct NatureInfo` and `include/constants/pokemon.h` nature/stat constants.
- Preserves source nature ids, names, `statUp`/`statDown`, Pokeblock animation fields, Battle Palace percent data, flavor text ids, smokescreen target preferences, and nature girl message symbols.
- Expands the source `PALACE_STYLE(atk, def, atkLow, defLow)` macro into stored cumulative values plus high/low HP attack/defense/support percentages.
- Records `src/pokemon.c:CalculateMonStats`, `ModifyStatByNature`, `GetNature`, and `GetNatureFromPersonality` as runtime references.
- Writes `data/generated/pokemon/natures.json` and updates `data/generated/import_manifest.json` with a `pokemon` entry for category `natures`.
- Treats generated nature data as source-backed runtime input for stat modifiers. Summary UI, Pokeblock feeding animation, Battle Palace behavior, personality-derived nature selection, mints, and presentation details remain future source-traced systems.

Latest verified nature export:

- generated path: `data/generated/pokemon/natures.json`
- manifest category: `pokemon` / `natures`
- natures: 25
- neutral natures: 5
- non-neutral natures: 20
- preprocessor decisions: 0 after slicing to the `gNaturesInfo` table
- warnings: 0
- unsupported fields: 0
- unresolved stat constants: 0

`tools/importer/export_evolutions.py` exports source Pokemon evolution data into generated Godot-friendly JSON. It accepts `--config`, `--source`, and `--output-root`.

Current evolution export behavior:

- Reads `src/data/pokemon/species_info.h` plus included `species_info/gen_*_families.h` files after evaluating the same active source config branches used by the species importer.
- Traces the source data shapes from `include/pokemon.h:struct Evolution`, `struct EvolutionParam`, `src/data/pokemon/species_info.h` `EVOLUTION(...)`/`CONDITIONS(...)` macros, and `include/constants/pokemon.h` evolution methods, conditions, modes, and spin directions.
- Resolves source constants for species, items, moves, types, natures, gender, time of day, weather, regions, map sections, maps, and `FRIENDSHIP_EVO_THRESHOLD`.
- Preserves source order, raw macro text, method params, target species, additional conditions, defaulted condition args, typed condition args, runtime mode metadata, and source runtime references for `GetEvolutionTargetSpecies`, `DoesMonMeetAdditionalConditions`, `GetSpeciesPreEvolution`, and `TryCreateSplitEvoMon`.
- Writes `data/generated/pokemon/evolutions.json` and updates `data/generated/import_manifest.json` with a `pokemon` entry for category `evolutions`.
- Treats generated evolution records as source-traceable data for later party/evolution-scene/runtime work. Actual evolution checks, item/held-item consumption, Everstone, trade/item/battle/overworld/script-trigger modes, split-evolution creation, move learning, cries, animation, UI, audio, and timing still require separate source-backed Godot implementation.

Latest verified evolution export:

- generated path: `data/generated/pokemon/evolutions.json`
- manifest category: `pokemon` / `evolutions`
- species with evolution records: 486
- evolution entries: 647
- condition entries: 291
- species with conditions: 109
- split evolution entries: 1
- preprocessor decisions: 2043
- warnings: 0
- unresolved values: 0

Porymap can be used as a reference for how pokeemerald projects interpret primary/secondary tilesets, palettes, metatile attributes, and editor context. The Godot importer should use those semantics to generate Godot-friendly outputs instead of reproducing Porymap's Qt editor architecture.

Latest verified first-slice source facts for `LittlerootTown`:

- map id: `MAP_LITTLEROOT_TOWN`
- layout id: `LAYOUT_LITTLEROOT_TOWN`
- size: 20x20
- primary tileset: `gTileset_General` -> `data/tilesets/primary/general`
- secondary tileset: `gTileset_Petalburg` -> `data/tilesets/secondary/petalburg`
- object events: 8
- warp events: 3
- coord events: 9
- connections: 1
- missing files: none

Latest verified first-slice export for `LittlerootTown`:

- generated path: `data/generated/maps/littleroot_town.json`
- manifest path: `data/generated/import_manifest.json`
- map-grid entries: 400
- unique metatile ids: 63
- metatile id range: 1 to 587

Latest verified Route101 map export:

- generated path: `data/generated/maps/route101.json`
- manifest path: `data/generated/import_manifest.json`
- map-grid entries: 400
- unique metatile ids: 31
- metatile id range: 1 to 487
- connections: north to `MAP_OLDALE_TOWN`, south to `MAP_LITTLEROOT_TOWN`

Latest verified first-slice tileset export for `LittlerootTown`:

- generated metadata path: `data/generated/tilesets/littleroot_town.json`
- generated atlas path: `assets/generated/tilesets/littleroot_town_metatiles.png`
- atlas size: 512x336 pixels
- metatile count: 656 total, 512 primary and 144 secondary
- used metatile ids: 63
- visible warnings: 0
- coverage notes: 8 bottom-layer out-of-range tile references in metatiles 586 and 587 are fully covered by opaque top-layer tiles in the flattened atlas
- generated door animations: 2 supported size-1 animated-door metatiles, `METATILE_Petalburg_Door_Littleroot` and `METATILE_Petalburg_Door_BirchsLab`
- generated door animation atlases: `assets/generated/door_anims/littleroot_town_littleroot.png` and `assets/generated/door_anims/littleroot_town_birchs_lab.png`
- generated metatile label data: source `METATILE_*` ids from `include/constants/metatile_labels.h`

Latest verified Route101 tileset export:

- generated metadata path: `data/generated/tilesets/route101.json`
- generated atlas path: `assets/generated/tilesets/route101_metatiles.png`
- atlas size: 512x336 pixels
- metatile count: 656 total, 512 primary and 144 secondary
- used metatile ids: 31
- visible warnings: 0

Latest verified first-slice event script export for `LittlerootTown`:

- generated path: `data/generated/scripts/littleroot_town.json`
- manifest path: `data/generated/import_manifest.json`
- labels: 130
- scripts: 78
- movement labels: 34
- local text labels: 18
- charmap status: 18 ok, 0 warnings
- source text bytes: 1358
- orphan instructions: 0
- current generated-data preview fields: first direct `msgbox`/`message` text references for debug inspection
- current text pipeline scope: local map-script text labels and global `data/text/*.inc` labels have UTF-8 `display_text` plus source encoding metadata; global `.braille` labels preserve source braille bytes and `brailleformat`; C text macros remain future import work
- current runtime execution scope: `ScriptVM` executes the first synchronous dialogue subset and expands `MSGBOX_NPC`, `MSGBOX_SIGN`, and `MSGBOX_DEFAULT` from source standard script behavior
- current local-id runtime scope: generated object events preserve source local-id names and runtime numeric aliases, while numeric script operands, OnFrame table comparisons, and movement command targets resolve `LOCALID_*` through current-map object-event order (`tools/mapjson/mapjson.cpp` emits index + 1 constants) plus source special ids
- current map-script runtime scope: direct map-load lifecycles run `MAP_SCRIPT_ON_TRANSITION`, affected object-template sync, then `MAP_SCRIPT_ON_LOAD`; `MAP_SCRIPT_ON_FRAME_TABLE`/`map_script_2` has a callable source-traced table evaluator, but true field-input-loop dispatch and async script-context timing remain future work
- current movement runtime scope: `ScriptVM` resolves generated movement labels for `applymovement`/`waitmovement`, follows source `VarGet` target semantics, preserves raw/resolved movement targets, and emits structured movement-effect results; real dispatch fast-forwards map/player positions through `MapRuntime`, while animation queues and object movement tasks are still future runtime work
- current field-effect runtime scope: `ScriptVM` records `delay`, `setmetatile`, `opendoor`, `closedoor`, and `waitdooranim` as structured field-effect results; `setmetatile` resolves source `METATILE_*` labels through generated tileset metadata and `MapRuntime` applies the current-map grid mutation while preserving elevation; transition presentation now consumes generated door animation metadata for first-pass door warp overlays, while standalone script-driven door animation, real audio playback, and true asynchronous timing remain future work
- current audio/transition/player-effect runtime scope: `ScriptVM` records `playse`, `playfanfare`, `waitfanfare`, `warp`, `warpsilent`, `waitstate`, and `hideplayer` as structured result data after source tracing; real sound playback, fanfare waiting, map loading/fades, and player presentation visibility remain future runtime work
- current coordinate-event runtime scope: `MapRuntime` indexes generated coord events and resolves normal `var`/`var_value` step triggers by x/y/elevation plus `GameState`; full weather/immediate-script/wild-encounter/step-count chaining remains future work

Latest verified Route101 event script export:

- generated path: `data/generated/scripts/route101.json`
- manifest path: `data/generated/import_manifest.json`
- scripts: 14
- movement labels: 13
- local text labels: 7
- charmap warnings: 0

Godot-only map overlay export:

- source path: `data/overlays/map_debug_fixtures.json`
- generated path: `data/generated/maps/debug_overlays.json`
- manifest category: `map_overlays` / `debug_fixtures`
- current overlay count: 1 map, 1 object event
- current fixture: `LOCALID_DEBUG_BATTLE_NPC` on `MAP_LITTLEROOT_TOWN` at `(10,12)` with `OBJ_EVENT_GFX_BOY_1`, `trainer_battle` metadata, and trainer id `TRAINER_SAWYER_1`
- runtime application: source map data remains unchanged by default; tests or `Main` must opt in through `include_debug_overlays`/`set_debug_map_overlays_enabled`

First-pass object-event sprite export:

- generated path: `data/generated/object_events/object_event_sprites.json`
- generated asset path: `assets/generated/object_events/boy_1.png`
- manifest category: `object_event_sprites` / `object_events`
- current sprite: `OBJ_EVENT_GFX_BOY_1`
- current scope: static source sheet extraction only; full facing/walking animation timing remains unsupported metadata/future work
- current runtime scope: static down-facing frame only; walking/facing animation tables remain future overworld sprite work

Latest verified additional maps for the first transition slice:

- `LittlerootTown_BrendansHouse_1F`: generated map `data/generated/maps/littleroot_town_brendans_house_1_f.json`, tileset `data/generated/tilesets/littleroot_town_brendans_house_1_f.json`, atlas `assets/generated/tilesets/littleroot_town_brendans_house_1_f_metatiles.png`, scripts `data/generated/scripts/littleroot_town_brendans_house_1_f.json`, size 11x9, 26 scripts, 11 movement labels, 29 text labels, 0 charmap warnings
- `LittlerootTown_MaysHouse_1F`: generated map `data/generated/maps/littleroot_town_mays_house_1_f.json`, tileset `data/generated/tilesets/littleroot_town_mays_house_1_f.json`, atlas `assets/generated/tilesets/littleroot_town_mays_house_1_f_metatiles.png`, scripts `data/generated/scripts/littleroot_town_mays_house_1_f.json`, size 11x9, 31 scripts, 11 movement labels, 8 text labels, 0 charmap warnings

Latest verified shared script export:

- `shared_players_house`: generated script bundle `data/generated/scripts/shared_players_house.json`
- source files: `data/scripts/movement.inc` and `data/scripts/players_house.inc`
- export counts: 122 labels, 49 scripts, 73 movement labels, 0 local text labels, 0 charmap warnings, 0 orphan instructions
- runtime use: Brendan/May house OnFrame intro scripts branch into `PlayersHouse_1F_EventScript_EnterHouseMovingIn`, with text and movement labels resolved through the local-first then global generated script namespace

Latest verified global text export:

- generated path: `data/generated/text/global_text.json`
- manifest category: `texts` / `global`
- source files: 37 `data/text/*.inc`
- labels/text records: 3454
- standard `.string` text records: 3393
- `.braille` text records: 61
- source text bytes: 216404 normal text bytes and 798 braille bytes
- charmap warnings: 0
- braille warnings: 0
- preprocessor decisions: 6, all from `data/text/pc_transfer.inc` `IS_FRLG` branches
- preprocessor warnings: 0
- unsupported directives: 0

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
- `include/constants/*.h`

### Text

- `charmap.txt`
- `tools/preproc/charmap.cpp`
- `tools/preproc/string_parser.cpp`
- `tools/preproc/c_file.cpp`
- `data/text/*.inc`
- text labels inside map scripts
- C macros such as `_("")` and `COMPOUND_STRING()`

### Event Script Semantics

- `data/maps/*/scripts.inc` for labels, command streams, movement labels, and local text labels
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

Before implementing a script instruction or gameplay feature in Godot, inspect the matching source C logic and the resources it references. Use that source behavior to design the Godot implementation, aiming for visible behavior and rules consistent with the original project while keeping the runtime Godot-native. If exact behavior is deferred, the generated data or runtime should report the approximation.

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
- Builds source palette slots with primary palettes 0-5 and secondary palettes 6-12, then bakes colors into a normal RGBA PNG.
- Flattens each 16x16 metatile by compositing bottom entries 0-3 and top entries 4-7.
- Bakes supported source door animation tile strips into normal RGBA frame atlases under `assets/generated/door_anims/`; palette numbers are used only at import time.
- Writes `assets/generated/tilesets/littleroot_town_metatiles.png`.
- Writes `data/generated/tilesets/littleroot_town.json` with atlas metadata, source tile entries, metatile attributes, metatile behavior names, used metatile ids, coverage notes, and warnings.
- Writes generated `door_animations` metadata into the tileset JSON for supported used door metatiles, including source labels, metatile ids, frame size, frame rectangles, 60fps frame timing, open/close frame indices, and source sound-effect symbol.
- Updates `data/generated/import_manifest.json` with exported tileset metadata while preserving existing entries for other maps, tilesets, and scripts.

`tools/importer/export_event_scripts.py` exports one map's `scripts.inc` into generated Godot-friendly JSON. It accepts `--config`, `--source`, `--map`, and `--output-root`.

Current event script export behavior:

- Reads `data/maps/<Map>/scripts.inc` as UTF-8 and writes generated JSON with LF endings through the shared importer JSON writer.
- Loads `charmap.txt` and follows the source preprocessor model from `tools/preproc/charmap.cpp`, `tools/preproc/string_parser.cpp`, and `tools/preproc/c_file.cpp` for text-byte validation.
- Parses labels, map script tables, script instruction streams, movement labels, and local `.string` text labels.
- Records per-script raw operations, direct `msgbox`/`message` references, call/goto references, and simple runtime preview summaries.
- Keeps Godot display text as UTF-8 while preserving source charmap encoding metadata for each local text label: status, source bytes, source hex, byte count, `$` terminator presence, control codes, placeholders, and warnings.
- Converts display escapes for preview/runtime text: `\n` and `\l` become newlines, `\p` becomes a blank line, and trailing `$` terminators are removed from `display_text`.
- Records source behavior traces for supported preview behavior from `src/scrcmd.c`, `data/event_scripts.s`, and `data/scripts/std_msgbox.inc`.
- Updates `data/generated/import_manifest.json` with exported script metadata while preserving existing entries for other maps, tilesets, and scripts.

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
- current text pipeline scope: local map-script text labels have UTF-8 `display_text` plus source charmap byte/control-code metadata; global text macros and broader text resources remain future import work
- current runtime execution scope: `ScriptVM` executes the first synchronous dialogue subset and expands `MSGBOX_NPC`, `MSGBOX_SIGN`, and `MSGBOX_DEFAULT` from source standard script behavior
- current movement runtime scope: `ScriptVM` resolves generated movement labels for `applymovement`/`waitmovement` and emits structured movement-effect results; real dispatch fast-forwards map/player positions through `MapRuntime`, while animation queues and object movement tasks are still future runtime work
- current field-effect runtime scope: `ScriptVM` records `delay`, `opendoor`, `closedoor`, and `waitdooranim` as structured field-effect results; transition presentation now consumes generated door animation metadata for first-pass door warp overlays, while standalone script-driven door animation, real audio playback, and true asynchronous timing remain future work
- current audio/transition/player-effect runtime scope: `ScriptVM` records `playse`, `playfanfare`, `waitfanfare`, `warp`, `warpsilent`, `waitstate`, and `hideplayer` as structured result data after source tracing; real sound playback, fanfare waiting, map loading/fades, and player presentation visibility remain future runtime work
- current coordinate-event runtime scope: `MapRuntime` indexes generated coord events and resolves normal `var`/`var_value` step triggers by x/y/elevation plus `GameState`; full weather/immediate-script/wild-encounter/step-count chaining remains future work

Latest verified additional maps for the first transition slice:

- `LittlerootTown_BrendansHouse_1F`: generated map `data/generated/maps/littleroot_town_brendans_house_1_f.json`, tileset `data/generated/tilesets/littleroot_town_brendans_house_1_f.json`, atlas `assets/generated/tilesets/littleroot_town_brendans_house_1_f_metatiles.png`, scripts `data/generated/scripts/littleroot_town_brendans_house_1_f.json`, size 11x9, 26 scripts, 11 movement labels, 29 text labels, 0 charmap warnings
- `LittlerootTown_MaysHouse_1F`: generated map `data/generated/maps/littleroot_town_mays_house_1_f.json`, tileset `data/generated/tilesets/littleroot_town_mays_house_1_f.json`, atlas `assets/generated/tilesets/littleroot_town_mays_house_1_f_metatiles.png`, scripts `data/generated/scripts/littleroot_town_mays_house_1_f.json`, size 11x9, 31 scripts, 11 movement labels, 8 text labels, 0 charmap warnings

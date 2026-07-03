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
- `graphics/door_anims/*.png` for future visible runtime door-tile cases when a map needs them

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
- script command implementations that have not yet been traced to source C behavior

## Source Behavior Rule

Generated JSON is an index and interchange format, not proof that an opcode or gameplay feature has been correctly implemented.

Before implementing a script instruction or gameplay feature in Godot, inspect the matching source C logic and the resources it references. Use that source behavior to design the Godot implementation, aiming for visible behavior and rules consistent with the original project while keeping the runtime Godot-native. If exact behavior is deferred, the generated data or runtime should report the approximation.

GBA hardware graphics formats are an exception to runtime fidelity: palettes, 4bpp tiles, binary metatiles, and packed map blocks should be decoded during import into ordinary Godot images/data. The importer should preserve enough source metadata for debugging and special cases, but the Godot runtime should not reproduce GBA palette or tile-memory constraints just because the source format used them.

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
- Updates `data/generated/import_manifest.json` with exported map id, name, path, layout id, and size while preserving existing tileset entries.
- Preserves source event arrays for connections, object events, warps, coordinate events, and background events.
- Preserves existing script manifest entries when updating the shared import manifest.

`tools/importer/export_tilesets.py` exports one map's primary/secondary tileset pair into a palette-baked metatile atlas. It accepts `--config`, `--source`, `--map`, `--output-data-root`, and `--output-asset-root`.

Current tileset export behavior:

- Reads the map layout's primary and secondary tileset symbols.
- Reads `tiles.png`, `metatiles.bin`, `metatile_attributes.bin`, and `palettes/*.pal` for both tilesets.
- Uses GBA tile-entry bits from `tools/gbagfx/gfx.h`: 10-bit tile id, horizontal flip, vertical flip, and 4-bit palette number.
- Builds source palette slots with primary palettes 0-5 and secondary palettes 6-12, then bakes colors into a normal RGBA PNG.
- Flattens each 16x16 metatile by compositing bottom entries 0-3 and top entries 4-7.
- Writes `assets/generated/tilesets/littleroot_town_metatiles.png`.
- Writes `data/generated/tilesets/littleroot_town.json` with atlas metadata, source tile entries, metatile attributes, used metatile ids, coverage notes, and warnings.
- Updates `data/generated/import_manifest.json` with exported tileset metadata while preserving existing map entries.

`tools/importer/export_event_scripts.py` exports one map's `scripts.inc` into generated Godot-friendly JSON. It accepts `--config`, `--source`, `--map`, and `--output-root`.

Current event script export behavior:

- Reads `data/maps/<Map>/scripts.inc` as UTF-8 and writes generated JSON with LF endings through the shared importer JSON writer.
- Parses labels, map script tables, script instruction streams, movement labels, and local `.string` text labels.
- Records per-script raw operations, direct `msgbox`/`message` references, call/goto references, and simple runtime preview summaries.
- Converts simple display escapes for preview only: `\n` and `\l` become newlines, `\p` becomes a blank line, and trailing `$` terminators are removed.
- Records source behavior traces for supported preview behavior from `src/scrcmd.c`, `data/event_scripts.s`, and `data/scripts/std_msgbox.inc`.
- Updates `data/generated/import_manifest.json` with exported script metadata while preserving existing map and tileset entries.

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

Latest verified first-slice event script export for `LittlerootTown`:

- generated path: `data/generated/scripts/littleroot_town.json`
- manifest path: `data/generated/import_manifest.json`
- labels: 130
- scripts: 78
- movement labels: 34
- local text labels: 18
- orphan instructions: 0
- current generated-data preview fields: first direct `msgbox`/`message` text references for debug inspection
- current runtime execution scope: `ScriptVM` executes the first synchronous dialogue subset and expands `MSGBOX_NPC`, `MSGBOX_SIGN`, and `MSGBOX_DEFAULT` from source standard script behavior

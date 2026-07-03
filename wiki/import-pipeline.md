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
- Writes `data/generated/import_manifest.json` with exported map id, name, path, layout id, and size.
- Preserves source event arrays for connections, object events, warps, coordinate events, and background events.

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

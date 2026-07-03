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

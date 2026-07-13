# Architecture

## Repository Layout

| Path | Responsibility |
|---|---|
| `new-game-project/` | Godot 4.7 project, runtime scripts, scenes, and tests |
| `new-game-project/battle/` | Isolated battle development root with an editor-only Q0 quick start and no world-runtime dependency |
| `new-game-project/scripts/platinum_collision_map.gd` | Manifest-backed tile attributes, BDHC height queries, step validation, and decoded collision retention |
| `tools/` | DSPRE export, GLB dedupe, Godot import, validation, and Git automation |
| `wiki/` | Versioned source for the project and GitHub Wiki |
| `.codex/skills/maizang-engine-godot/` | Project-specific Codex workflow and memory |
| `generated/` | Local conversion output, intentionally ignored |
| `.work/` | Temporary converter state, intentionally ignored |

## Runtime Scene

`new-game-project/scenes/main.tscn` owns:

- `WorldEnvironment` and one directional light.
- A `CharacterBody3D` player with a billboarded four-direction sprite.
- A front-facing orthographic `Camera3D` that follows the player, owns pitch
  input, and exposes an `F1` perspective debug mode.
- `PlatinumWorldStreamer` and its `LoadedChunks` runtime container.
- A native-resolution `F2` debug destination panel that pauses the active
  world while a jump is being configured.

`PlatinumWorldStreamer` uses the player as its focus. It reads the generated
matrix catalog and selected destination manifest, requests terrain and building
`PackedScene` resources asynchronously, instantiates ready cells, and releases
distant cells and cache references. It also owns one independent
`PlatinumCollisionMap` `Resource`, exposes that resource's step and height
queries to the player, and refreshes its decoded collision region separately
from visual scene instantiation.

The catalog key is a destination rather than only a matrix ID. This preserves
the two AreaData variants of matrices `0049` and `0052`. Startup debug settings
select `(matrix_id, area_data_id, cell, tile)` before the streamer issues any
threaded load. In-game jumps use the same side-effect-free resolver, place one
validated request on the persistent `SceneTree`, and reload the complete main
scene. The next streamer consumes that request once before falling back to
command-line or ProjectSettings configuration.

## Display Contract

The current viewer uses one native NDS-sized screen:

```text
logical viewport = 256 x 192
window content   = 256 x 192
aspect ratio     = 4:3
scaling layer    = none
```

The window is fixed-size. This represents one NDS screen, not the combined
dual-screen `256 x 384` layout. Texture filtering remains nearest-neighbor.

## Coordinate Contract

The conversion follows the original Platinum field constants:

```text
one map cell       = 32 Godot world units
one matrix altitude = 0.5 Godot world units
one model unit      = 1 / 16 Godot world unit
```

Matrix cells use their top-left origin. World-to-cell conversion therefore
uses `floor`, not nearest-integer rounding.

Source map models, MapProps, and BDHC use the center of a `32 x 32` cell as
their local X/Z origin. Runtime chunks preserve the top-left matrix contract
with this hierarchy:

```text
Chunk root = (cell_x * 32, 0, cell_z * 32)
Terrain    = (16, matrix_altitude * 0.5, 16)
Buildings  = (16, 0, 16)
```

MapProp Y values and BDHC heights are already absolute field heights. Matrix
altitude is applied to the terrain model only and is not added again to either
value. A map tile center remains `(cell * 32 + tile + 0.5)` in world X/Z.

## Collision Ownership

Destination manifest schema 3 embeds one collision asset per unique land-data
map and links every occupied matrix cell through `collision_asset_key`.
`PlatinumCollisionMap` validates those links and keeps the Base64 source
records independently of rendered nodes. It decodes the `32 x 32` little-endian
terrain attributes and packed BDHC arrays on demand, retaining decoded records
only around the current player cell.

The exported `a.dat` terrain-attribute high bit (`0x8000`) is authoritative
static collision; the low byte is the tile behavior. Directional behaviors are
checked from both the current and destination tiles. The walking behavior layer
classifies every step as `allow`, `blocked`, or `special` and returns an
`action`, `landing_target`, and next movement context. Special behavior is
resolved before the raw collision bit so a correctly approached ledge exposes
`jump` or `jump_two` with a two-tile landing even when the ledge tile has bit 15
set.

BDHC from `h.bhc` supplies absolute terrain height, including overlapping
plates selected relative to the player's current height. A height
discontinuity of `20` source units (`1.25` world units) or more blocks a normal
grid step. Successful steps carry a `bridge_layer` context so elevated bridge
travel remains distinct from water-level travel beneath the same X/Z tiles.
Capabilities without a runtime executor, including Surf, transitions, forced
ice movement, dynamic mechanisms, Rock Climb, and bicycle movement, return a
named `special` action and fail closed.

Static buildings and other MapProps do not create collision meshes. Their
walkable footprint is already represented by the cell terrain attributes;
MapProp records remain visual placement data and support anchor lookup for
later interactions. During manifest configuration, their center-origin
positions are converted to global world tiles and stored in an O(1) index.
Queries therefore find anchors that extend beyond the MapProp's owner cell and
remain valid when the visual chunk has not loaded or has already been released.

## Material Ownership

GLBs retain valid local material slots, but import settings redirect matching
material names to catalog-wide external `.tres` resources. Runtime fallback
sharing is implemented with `MeshInstance3D` surface overrides and never
mutates a shared `ArrayMesh`.

## Offline Matrix Boundary

The local converter inventories all 289 source matrix records. It publishes
only destinations whose AreaData is established by headers, duplicate map
evidence, or a unique complete Nitro texture/palette match. Unreferenced and
ambiguous records stay visible in `matrix_catalog.json` as unresolved metadata
but have no runtime manifest path. ROM-derived manifests, GLBs, textures, and
catalog files remain under ignored asset roots.

## Remaining Non-Goals

- Dynamic collision overrides for moving platforms and scripted map changes.
- NPCs, scripts, warps, animations, and world-to-battle integration. The
  isolated Q0 battle root is only an editor smoke surface at this stage.
- Guessing AreaData for unreferenced or internally inconsistent source matrices.

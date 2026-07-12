# Architecture

## Repository Layout

| Path | Responsibility |
|---|---|
| `new-game-project/` | Godot 4.7 project, runtime scripts, scenes, and tests |
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
matrix catalog and selected destination manifest, requests terrain and building `PackedScene` resources
asynchronously, instantiates ready cells, and releases distant cells and cache
references.

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

## Non-Goals for the Current Milestone

- Terrain height snapping and player collision rules.
- `a.dat` tile behavior and `h.bhc` height queries.
- NPCs, scripts, warps, animations, and battle systems.
- Guessing AreaData for unreferenced or internally inconsistent source matrices.

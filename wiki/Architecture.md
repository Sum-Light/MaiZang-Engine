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

`PlatinumWorldStreamer` uses the player as its focus. It reads the generated
matrix manifest, requests terrain and building `PackedScene` resources
asynchronously, instantiates ready cells, and releases distant cells and cache
references.

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
material names to 511 external `.tres` resources. Runtime fallback sharing is
implemented with `MeshInstance3D` surface overrides and never mutates a shared
`ArrayMesh`.

## Non-Goals for the Current Milestone

- Terrain height snapping and player collision rules.
- `a.dat` tile behavior and `h.bhc` height queries.
- NPCs, scripts, warps, animations, and battle systems.
- Full indoor, dungeon, or underground matrix coverage.

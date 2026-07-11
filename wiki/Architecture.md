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
- A free-fly `Camera3D` used as the streaming focus.
- `PlatinumWorldStreamer` and its `LoadedChunks` runtime container.

`PlatinumWorldStreamer` reads the generated matrix manifest, requests terrain
and building `PackedScene` resources asynchronously, instantiates ready cells,
and releases distant cells and cache references.

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

- Player collision and movement rules.
- `a.dat` tile behavior and `h.bhc` height queries.
- NPCs, scripts, warps, animations, and battle systems.
- Full indoor, dungeon, or underground matrix coverage.

# MaiZang Engine Wiki

MaiZang Engine reconstructs the Pokemon Platinum overworld in Godot 4.7 from
local DSPRE exports. The project currently focuses on a faithful visual world,
repeatable conversion tooling, and bounded runtime streaming. It is not yet a
complete game port.

## Current Milestone

- Inventory all 289 source matrices and export 276 strict-ready matrices through
  278 AreaData-aware destinations with DSPRE's bundled Apicula converter.
- Deduplicate external PNGs and material signatures without changing GLB mesh data.
- Import shared Godot materials and lossless nearest-filtered textures.
- Preserve matrix `0000` as the default streamed overworld while making indoor
  and dungeon destinations available through debug startup settings.
- Control Dawn with four-direction walking and `Z` running animations.
- Use a native-size orthographic camera with an `F1` perspective debug mode.
- Stream nearby chunks around the player with bounded asset retention.
- Keep 13 unreferenced or internally inconsistent source matrices unresolved
  instead of assigning guessed textures.

## Documentation

- [Architecture](Architecture)
- [Asset Pipeline](Asset-Pipeline)
- [Runtime Streaming](Runtime-Streaming)
- [Player Control](Player-Control)
- [Validation](Validation)
- [Development Workflow](Development-Workflow)
- [Repository Policy](Repository-Policy)
- [Current State](Current-State)
- [Change Log](Change-Log)

The Markdown source for this Wiki is versioned under `wiki/` in the main
repository and synchronized to the GitHub Wiki after project commits.

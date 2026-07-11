# MaiZang Engine Wiki

MaiZang Engine reconstructs the Pokemon Platinum overworld in Godot 4.7 from
local DSPRE exports. The project currently focuses on a faithful visual world,
repeatable conversion tooling, and bounded runtime streaming. It is not yet a
complete game port.

## Current Milestone

- Export main-world matrix `0000` through DSPRE's bundled Apicula converter.
- Deduplicate external PNGs and material signatures without changing GLB mesh data.
- Import shared Godot materials and lossless nearest-filtered textures.
- Assemble 468 occupied terrain cells and 501 building instances.
- Stream nearby chunks around a free camera with bounded asset retention.

## Documentation

- [Architecture](Architecture)
- [Asset Pipeline](Asset-Pipeline)
- [Runtime Streaming](Runtime-Streaming)
- [Validation](Validation)
- [Development Workflow](Development-Workflow)
- [Repository Policy](Repository-Policy)
- [Current State](Current-State)
- [Change Log](Change-Log)

The Markdown source for this Wiki is versioned under `wiki/` in the main
repository and synchronized to the GitHub Wiki after project commits.

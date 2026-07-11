# Project Map

## Ownership

| Path | Owner and purpose |
|---|---|
| `new-game-project/scripts/platinum_world_streamer.gd` | Manifest loading, asynchronous asset cache, chunk lifecycle, placement |
| `new-game-project/scripts/free_fly_camera.gd` | Viewer navigation only |
| `new-game-project/scenes/main.tscn` | Minimal runnable world shell |
| `new-game-project/tests/` | Streaming and render-capture integration tests |
| `new-game-project/tools/` | Godot-side shared-material generation and validation |
| `tools/dspre_batch_export.ps1` | DSPRE binary data to isolated terrain/building GLBs and manifest |
| `tools/dedupe_dspre_materials.ps1` | Shared texture pool, material signatures, GLB JSON rewrite |
| `tools/sync_dspre_godot_assets.ps1` | Local generated output to ignored Godot asset tree |
| `tools/configure_dspre_godot_materials.ps1` | External material mappings and scene reimport |
| `tools/configure_dspre_godot_textures.ps1` | Lossless, no-mipmap texture import |
| `wiki/` | Versioned GitHub Wiki source of truth |

## Runtime Constants

- Single-screen viewport and window: `256 x 192`, fixed 4:3.
- Default camera: yaw `0`, downward pitch `60`, wheel pitch step `5`.
- `CHUNK_SIZE = 32.0`
- `HEIGHT_STEP = 0.5`
- `MODEL_SCALE = 1.0 / 16.0`
- Default start cell `(3, 27)`
- Load radius 1, prefetch radius 2, unload/retention radius 3

## Generated Baseline

- Matrix `0000`: `30 x 30`, 468 occupied cells.
- 176 terrain variants.
- 222 building/texture variants.
- 501 building instances.
- 398 GLBs.
- 480 unique PNGs from 3060 source image references.
- 511 unique materials and 3249 mesh surface references.

## Local Dependencies

Paths are configurable script parameters. Current machine defaults include:

- Godot 4.7 stable console executable under the user's Downloads directory.
- DSPRE Portable's `Tools/apicula.exe`.
- A user-owned DSPRE project ending in `_DSPRE_contents`.

Do not encode source ROM data into repository files or Wiki pages.

# Project Map

## Ownership

| Path | Owner and purpose |
|---|---|
| `new-game-project/scripts/platinum_world_streamer.gd` | Manifest loading, asynchronous asset cache, chunk lifecycle, placement |
| `new-game-project/scripts/player_controller.gd` | Cardinal movement, Dawn animation, walking and running state |
| `new-game-project/scripts/follow_camera.gd` | Player following and mouse-wheel pitch control |
| `new-game-project/scripts/visual_profile_controller.gd` | Classic/HD2D environment, sun, pixel-snap, and player-shadow ownership |
| `new-game-project/visual_profiles/` | Versioned Classic and HD2D visual parameter resources |
| `new-game-project/scenes/main.tscn` | Minimal runnable world shell |
| `new-game-project/tests/` | Streaming and render-capture integration tests |
| `new-game-project/tools/` | Godot-side shared-material generation and validation |
| `tools/dspre_batch_export.ps1` | DSPRE binary data to isolated terrain/building GLBs and manifest |
| `tools/dedupe_dspre_materials.ps1` | Shared texture pool, material signatures, GLB JSON rewrite |
| `tools/sync_dspre_godot_assets.ps1` | Local generated output to ignored Godot asset tree |
| `tools/configure_dspre_godot_materials.ps1` | External material mappings and scene reimport |
| `tools/configure_dspre_godot_textures.ps1` | Lossless, no-mipmap texture import |
| `tools/import_player_sprite.ps1` | Local Dawn walk/run atlas extraction and color-key transparency |
| `wiki/` | Versioned GitHub Wiki source of truth |

## Runtime Constants

- Single-screen viewport and window: `256 x 192`, fixed 4:3.
- Physics tick rate: `60 Hz`.
- Player: half-integer-centered one-unit grid; Platinum's 30 Hz 8/4-frame
  walk/run actions map to 16/8 Godot physics ticks, with 6-tick stationary turns.
- Follow camera: orthographic size `11.24` and distance `16`; debug perspective
  FOV `75` and distance `8`; yaw `0`, downward pitch `50`, wheel step `5`.
- Visual profile: Classic default; `F2` HD2D preview with camera-local pixel snap,
  depth fog, player ground shadow, and no gameplay or mesh mutation.
- `CHUNK_SIZE = 32.0`
- `HEIGHT_STEP = 0.5`
- `MODEL_SCALE = 1.0 / 16.0`
- Source tile size 16 pixels = 1.0 world unit
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

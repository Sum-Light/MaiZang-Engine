# Project Map

## Ownership

| Path | Owner and purpose |
|---|---|
| `new-game-project/battle/` | Isolated battle business root; Q0 owns the editor-only quick start, text smoke shell, battle-local tests/tools, and future battle implementation without world-runtime dependencies |
| `new-game-project/scripts/platinum_world_streamer.gd` | Catalog/Header destination selection, manifest loading, asynchronous visual cache, collision/Warp delegation, animated MapProp registration, chunk lifecycle, placement |
| `new-game-project/scripts/platinum_collision_map.gd` | Lazy terrain-attribute and BDHC decode, walking behavior classification, height/step queries, bridge context, global MapProp anchor index |
| `new-game-project/scripts/platinum_warp_controller.gd` | Static Warp execution, input lock, door animation, fade, and one-shot scene-reload handoff |
| `new-game-project/scripts/world_transition_request.gd` | Strict process-local Warp destination handoff across a main-scene reload |
| `new-game-project/scripts/platinum_map_animation_controller.gd` | Explicitly registered 30 Hz NSBCA loops and door one-shots using weak instance ownership |
| `new-game-project/scripts/platinum_field_texture_animation_controller.gd` | Lazy 30 Hz `fldtanime` frame loading and runtime-owned surface material overrides |
| `new-game-project/scripts/debug_destination_resolver.gd` | Side-effect-free catalog, manifest, AreaData, cell, and tile resolution shared by startup and in-game jumps |
| `new-game-project/scripts/debug_destination_request.gd` | One-shot process-local destination handoff across a complete main-scene reload |
| `new-game-project/scripts/debug_destination_panel.gd` | Native-resolution F2 modal, paused input ownership, validation feedback, and reload submission |
| `new-game-project/scripts/player_controller.gd` | Cardinal movement, Dawn animation, walking/running state, collision preflight, slope sampling, bridge-layer context |
| `new-game-project/scripts/follow_camera.gd` | Player following and mouse-wheel pitch control |
| `new-game-project/scenes/main.tscn` | Minimal runnable world shell |
| `new-game-project/tests/` | Collision, player, streaming, debug-destination, and render-capture tests |
| `new-game-project/tools/` | Godot-side shared-material generation and validation |
| `new-game-project/tools/material_catalog_support.gd` | Exact catalog/GLB material binding and content comparison helpers |
| `tools/dspre_batch_export.ps1` | DSPRE binary data to isolated terrain/building GLBs and manifest |
| `tools/dspre_collision_support.ps1` | Packed land-data plus field-feature/animation manifest validation and deterministic source/tool fingerprints |
| `tools/dspre_field_feature_support.ps1` | MapHeader event archive parsing, static/dynamic Warp classification, and endpoint resolution |
| `tools/dspre_map_animation_support.ps1` | `bm_anime` descriptor parsing and atomic Nitro animation-member extraction |
| `tools/dspre_field_texture_animation_support.ps1` | Strict `fldtanime`/TEX0 parsing, target-palette selection, and frame decoding |
| `tools/build_dspre_field_texture_animations.ps1` | Global content-pooled field texture animation build and paired generated/Godot publication |
| `tools/resolve_dspre_matrix_areas.ps1` | Strict MapHeader, duplicate-map, and Nitro texture/palette AreaData resolution |
| `tools/dspre_export_all_matrices.ps1` | Resumable all-matrix export, dedupe, sync, catalog, and Godot import orchestration |
| `tools/dedupe_dspre_materials.ps1` | Shared texture pool, material signatures, GLB JSON rewrite |
| `tools/sync_dspre_godot_assets.ps1` | Transactional generated-output reconciliation into the ignored Godot asset tree, preserving unchanged import sidecars |
| `tools/configure_dspre_godot_materials.ps1` | External material mappings and scene reimport |
| `tools/configure_dspre_godot_textures.ps1` | Lossless, no-mipmap texture import |
| `tools/import_player_sprite.ps1` | Local Dawn walk/run atlas extraction and color-key transparency |
| `tools/validate_dspre_matrix_catalog.ps1` | Bidirectional catalog, manifest, stage-marker, GLB, texture-hash, and spawn-cell validation |
| `wiki/` | Versioned GitHub Wiki source of truth |

## Runtime Constants

- Single-screen viewport and window: `256 x 192`, fixed 4:3.
- Physics tick rate: `60 Hz`.
- Player: half-integer-centered one-unit grid; Platinum's 30 Hz 8/4-frame
  walk/run actions map to 16/8 Godot physics ticks, with 6-tick stationary turns.
- Follow camera: orthographic size `11.24` and distance `16`; debug perspective
  FOV `75` and distance `8`; yaw `0`, downward pitch `50`, wheel step `5`.
- `CHUNK_SIZE = 32.0`
- `HEIGHT_STEP = 0.5`
- `MODEL_SCALE = 1.0 / 16.0`
- Source tile size 16 pixels = 1.0 world unit
- Default start cell `(3, 27)`
- Default debug destination: matrix `0000`, automatic AreaData, cell `(3, 27)`, tile `(16, 16)`
- In-game debug destination shortcut: `F2`, validated one-shot full-scene reload
- Static Warp transitions: Header-scoped one-shot reload; dynamic/special Warp records fail closed
- MapProp animation clock: 30 Hz, explicit loaded-instance registration; NSBCA automatic/door clips only
- Field texture animation clock: 30 Hz, lazy active-binding frame loads and per-material surface overrides
- Battle development entry: Inspector tool button in `res://battle/quick_start/battle_quick_start.tscn`; Q0 launches only the independent synthetic text smoke shell
- Load radius 1, prefetch radius 2, unload/retention radius 3

## Generated Baseline

- Matrix `0000`: `30 x 30`, 468 occupied cells.
- Source inventory: 289 matrices.
- Strict runtime catalog: 276 ready matrices through 278 destinations.
- Multi-AreaData destinations: matrix `0049` areas `4/61` and matrix `0052` areas `8/54`.
- Unresolved unreferenced source matrices: 13; these have no runnable destination.
- Matrix `0000` retains 176 terrain variants, 222 building/texture variants,
  176 collision assets, 501 building instances, 398 GLBs, 480 unique PNGs, and
  511 materials.
- Complete catalog collision data: 637 globally unique assets and 647
  destination-scoped assets across 1,153 occupied cells.

## Local Dependencies

Paths are configurable script parameters. Current machine defaults include:

- Godot 4.7 stable console executable under the user's Downloads directory.
- DSPRE Portable's `Tools/apicula.exe`.
- A user-owned DSPRE project ending in `_DSPRE_contents`.

Do not encode source ROM data into repository files or Wiki pages.

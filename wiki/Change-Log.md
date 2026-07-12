# Change Log

## 2026-07-12 - Tune the HD2D atmosphere

- Balance the opt-in HD2D preview with restrained depth fog, cool ambient fill, and a softer warm sun while keeping glow, adjustments, dynamic shadows, water, and foliage effects disabled.
- Add a reproducible six-scene visual matrix with 16-frame stability, frozen Classic SHA, exact draw topology, and 1800-frame CPU/GPU p95 gates.

## 2026-07-12 - Lock native player sprite pixels

- Render all 32 player frames through an isolated Compatibility SubViewport and require source-identical alpha coordinates, preventing the HD2D comparison image from squeezing or shifting sprite columns.
- Add explicit down/up/left/right world captures with 16-frame stability checks and include the pixel test in full repository validation.

## 2026-07-12 - Add world-scale HD2D semantic classification

- Derive a hash-free semantic profile from catalog signatures, GLB texture bindings, alpha modes, emissive factors, and all 3249 material-bearing primitive surfaces.
- Rebuild the ignored eight-material P3 seed from the manifest and catalog in both configuration and full-validation workflows.
- Derive the seed's nine instances and 22 selected GLB surfaces, reject semantic-policy conflicts, and recursively prune unknown stale variant tags.
- Preserve static water, alpha foliage, legacy shadows, and ambiguous materials while applying 16 low-energy emissive variants and retaining six explicit P3 lit variants.
- Add 32-toggle material identity stress coverage, sparse-neighborhood capture readiness, and eight-frame RGBA stability validation.

## 2026-07-12 - Enforce clean renderer teardown

- Flush the Compatibility renderer after world-test cleanup and make full validation reject logged shader, RID, resource, or orphan leaks even when Godot exits with code zero.

## 2026-07-12 - Add the HD2D semantic material pilot

- Generate and validate eight ignored per-vertex-lit material variants for the bounded `(3, 27)` pilot while hash-protecting all 511 shared base materials.
- Bind 22 surfaces across nine terrain/building instances with reversible per-instance overrides, legacy-shadow restoration, F2 identity checks, and cross-region cleanup tests.

## 2026-07-12 - Add reversible HD-2D visual profiles

- Add Classic/HD2D profile resources, F2 and command-line switching, camera-local orthographic pixel snapping with native-size Sprite3D compensation, a prebuilt player ground shadow, lightweight depth fog, and render-performance capture metrics.
- Keep Classic pixel-identical through a zero-influence warm fog path that avoids a Godot 4.7 Compatibility shader leak during profile roundtrips.

## 2026-07-12 - Add grid movement and fix foreground clipping

- Center the player on half-integer tile coordinates and move one 16-pixel tile per atomic action, mapping Platinum's 30 Hz walk/run timing to 16/8 Godot physics ticks.
- Reproduce source-style six-tick stationary turns, grid-boundary direction/Z sampling, historical diagonal priority, and the continuous four-pose walk/run gait timeline.
- Move the orthographic camera to distance 16 while retaining distance 8 for perspective debug mode, preventing foreground roofs from crossing the camera plane.
- Repair render-capture argument parsing and add cell offsets for reproducible building regression captures.

## 2026-07-12 - Set 50-degree camera composition

- Set the default camera pitch to 50 degrees and use the requested orthographic size of 11.24 for a closer player and building composition.

## 2026-07-12 - Match orthographic camera scale

- Set the default orthographic size to 12.3 so the player appears at nearly the same scale as the FOV-75 perspective debug view.


## 2026-07-12 - Add orthographic camera debug toggle

- Start the player-follow camera in size-8 orthographic mode and let F1 toggle a transform-preserving FOV-75 perspective debug view.


## 2026-07-12 - Add playable Dawn character

- Add cardinal walking, Z-key running animations, a player-follow camera, local sprite-atlas import tooling, and focused runtime validation.


## 2026-07-12 - Set front-facing 60-degree camera

- Use a zero-yaw 60-degree downward default view and map mouse-wheel input to 5-degree pitch steps instead of movement speed.


## 2026-07-12 - Use native NDS screen resolution

- Set the Godot window, viewport, and render-capture contract to a fixed 256 by 192 single-screen layout.


## 2026-07-12 - Remove obsolete remote branches

- Deleted 17 superseded codex branches and documented master as the only long-lived project branch.


## 2026-07-12 - Handle initialized GitHub Wiki remotes

- Reset the disposable Wiki worktree to the initialized remote before publishing versioned pages.


## 2026-07-12 - Replace repository with the DSPRE-to-Godot pipeline

- Replaced the prior repository worktree with the current MaiZang Engine project.
- Added the matrix `0000` export, material dedupe, Godot import, and sync tools.
- Added streamed terrain and building placement with bounded asset retention.
- Added shared-material, streaming, and render-capture validation.
- Added a versioned Wiki, Codex Skill, repository hooks, and SSH-authenticated GitHub Wiki sync flow.
- Kept proprietary Pokemon and ROM-derived assets outside the public repository.

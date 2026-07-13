# Validation

## PowerShell Syntax

Parse every project script before committing workflow changes:

```powershell
$bad = @()
Get-ChildItem .\tools -Filter *.ps1 | ForEach-Object {
  $errors = $null
  $tokens = $null
  [Management.Automation.Language.Parser]::ParseFile(
    $_.FullName, [ref]$tokens, [ref]$errors
  ) | Out-Null
  if ($errors.Count) { $bad += $_.FullName }
}
if ($bad.Count) { throw "PowerShell syntax failures: $bad" }
```

Fast repository validation also runs the proprietary-data-free collision
parser test:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tools\test_dspre_collision_support.ps1
```

It synthesizes a land-data file in memory and verifies exact Base64 retention
of `a.dat` collision/behavior bits and signed FX32 BDHC data. The focused test
rejects a truncated source, out-of-range plate indices, and zero-Y plate
normals. The same shared validator is used at every pipeline boundary to reject
inconsistent array counts, invalid hashes, missing cell references, and invalid
building scale/collision descriptors. The test also proves that the complete
DSPRE tree fingerprint is stable across absolute root relocation and file
creation order, while a same-length content edit or relative-path rename changes
it. Tool hashes ignore installation path but react to content changes. Area
resolution hashes ignore generated time and absolute source path while reacting
to semantic resolution changes. All-matrix export recomputes those fingerprints
before catalog publication, detecting source or tool changes made during a run.

## Collision and Height Validation

The Godot collision subsystem has two asset-independent focused tests:

```powershell
& "D:\path\to\Godot_v4.7-stable_win64_console.exe" `
  --headless --path .\new-game-project `
  --script res://tests/platinum_collision_map_test.gd

& "D:\path\to\Godot_v4.7-stable_win64_console.exe" `
  --headless --path .\new-game-project `
  --script res://tests/player_collision_test.gd
```

The first decodes schema-3 Base64 payloads and covers static collision bit
`0x8000`, directional barriers, overlapping BDHC plate selection with explicit
bridge-layer context, and the exact 20-source-unit (`1.25` world-unit) height
discontinuity. It also verifies that walk movement fails closed on sea-water
behavior, a directional ledge can override bit 15 and report a two-grid landing,
unknown and ice behaviors report unsupported special actions, and map props are
indexed by global tile even when their anchors extend into another matrix cell.
These results only expose requirements to later locomotion systems; the test
does not claim that Surf, Warp, ice movement, or the ledge-jump animation is
implemented. It additionally covers collision-cache pruning independent of
rendered chunks. The second test verifies that a blocked cardinal step never
starts and that a permitted 16-tick step resamples BDHC height throughout a
slope.

A generated destination can be checked directly without loading its GLBs:

```powershell
& "D:\path\to\Godot_v4.7-stable_win64_console.exe" `
  --headless --path .\new-game-project `
  --script res://tests/platinum_collision_map_test.gd -- `
  --real-manifest=res://assets/platinum/matrix_0049_area_0061/manifest.json
```

Real-data integration is also part of the matrix `0000` streaming smoke test:
it requires 176 source collision assets, at least one decoded retained asset,
zero decode failures, a known `a.dat` blocked step, and BDHC-derived spawn and
movement heights. Matrix altitude affects visual placement only; validation
explicitly rejects adding it to the absolute BDHC ground height.

## Shared Material Validation

```powershell
& "D:\path\to\Godot_v4.7-stable_win64_console.exe" `
  --headless --path .\new-game-project `
  --script res://tools/validate_shared_materials.gd
```

The validator reads every runnable destination from `matrix_catalog.json`,
checks every GLB against its material catalog and raw GLB content, rejects null
material surfaces, verifies every material surface uses the expected external
`.tres`, and rejects unreferenced material resources. For a bounded
parser/import check, pass `-- --limit-assets=1`.

The synthetic material-signature and nonzero-altitude coordinate checks do not
depend on generated Platinum assets:

```powershell
& "D:\path\to\Godot_v4.7-stable_win64_console.exe" `
  --headless --path .\new-game-project `
  --script res://tests/material_catalog_support_test.gd

& "D:\path\to\Godot_v4.7-stable_win64_console.exe" `
  --headless --path .\new-game-project `
  --script res://tests/debug_coordinate_test.gd
```

## Matrix Catalog Validation

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tools\validate_dspre_matrix_catalog.ps1 -RequireComplete
```

This validates all 289 matrix status records, all 278 expected destination
keys, their matrix/AreaData bindings, one-to-one matrix ownership, default
occupied cells, unique manifest-relative GLB paths, GLB headers, stage-complete
manifest hashes, recomputed summary counts, and the 13 unresolved records with
no runnable destination. It requires catalog schema `2` and destination
manifest schema `3`, then validates every embedded collision payload through
the shared parser. The complete count contract is 637 globally unique and 647
destination-scoped collision assets, with exactly 1,024 terrain tiles and one
BDHC payload per destination-scoped asset. This yields 662,528
destination-scoped terrain tiles and 647 destination-scoped BDHC payloads.
Reused map IDs must retain identical terrain and BDHC hashes across AreaData
variants.

`validate_repository.ps1 -Full` also requires every destination PNG import
sidecar to retain lossless compression, disabled mipmaps, and disabled 3D
texture compression before it starts the Godot material and runtime tests.
It runs the collision-map and player-collision tests before the real renderer
smoke tests.
The fast validation also guards the destructive sync ordering: an explicitly
requested cross-volume hard-link transfer must fail before an existing Godot
destination can be removed.

## Streaming Smoke Test

Use a real OpenGL renderer so renderer cleanup is exercised:

```powershell
& "D:\path\to\Godot_v4.7-stable_win64_console.exe" `
  --path .\new-game-project `
  --audio-driver Dummy `
  --rendering-method gl_compatibility `
  --rendering-driver opengl3 `
  --script res://tests/world_streamer_smoke_test.gd
```

The test verifies:

- Explicit matrix `0000` startup independent of developer ProjectSettings.
- 468 manifest cells.
- Destination manifest schema `3` and 176 map-ID collision assets.
- Lazy Base64 collision decode with zero failures and retention independent of
  rendered `PackedScene` resources.
- A known real `a.dat` collision bit blocks its cardinal step.
- BDHC height sampling drives spawn, slopes, and the target Y of every step.
- Initial `3 x 3` chunk load.
- Dawn's ignored local walk/run atlas is loaded.
- Diagonal input resolves to one cardinal axis.
- A 16-pixel source tile maps to one world unit.
- Player positions stay on half-integer tile centers without the prior 8-pixel offset.
- The 32-pixel source sprite projects within one pixel of its native height at
  orthographic size `11.24` on the 192-pixel viewport.
- Platinum's 30 Hz walk/run actions map to 16/8 Godot physics ticks per tile.
- A stationary direction change uses six ticks and does not move the player.
- Walking and running preserve the 32-tick `neutral, foot A, neutral, foot B`
  gait timeline in atlas banks `0..3` and `4..7` respectively.
- Direction and `Z` changes during a step take effect only at the next tile.
- Held input starts walking immediately after a stationary turn; continuous
  walking changes direction without inserting another turn.
- Held movement chains cells without drift; teleports clear unfinished actions.
- The orthographic camera follows at distance `16`.
- The camera starts orthographic at size `11.24`.
- `F1` switches to distance-8, FOV-75 perspective and restores distance 16 at
  the unchanged test target and pitch.
- Default camera yaw `0`, downward pitch `50`, and wheel pitch steps of `5`.
- Mouse-wheel pitch changes preserve the follow distance.
- Correct floor-based cell boundaries.
- Long-distance load and origin unload.
- Zero failed assets and zero runtime material replacements.
- Loaded assets do not exceed the current retention set.

## Debug Destination Smoke Test

```powershell
& "D:\path\to\Godot_v4.7-stable_win64_console.exe" `
  --path .\new-game-project `
  --audio-driver Dummy `
  --rendering-method gl_compatibility `
  --rendering-driver opengl3 `
  --script res://tests/debug_destination_test.gd

& "D:\path\to\Godot_v4.7-stable_win64_console.exe" `
  --path .\new-game-project `
  --audio-driver Dummy `
  --rendering-method gl_compatibility `
  --rendering-driver opengl3 `
  --script res://tests/debug_destination_test.gd -- `
  --matrix=49 --area=4 --tile=7,9 --expect-runtime-cli
```

The focused test covers the explicit pre-tree API priority, command-line
selection, automatic catalog default cells, AreaData variant selection,
small-matrix chunk counts, and BDHC-aware tile-centered player placement. The
integration case verifies an absolute BDHC height independently of nonzero
matrix altitude; the synthetic coordinate test covers cross-cell height
selection and capture offsets.

## Runtime Debug Jump Test

```powershell
& "D:\path\to\Godot_v4.7-stable_win64_console.exe" `
  --path .\new-game-project `
  --audio-driver Dummy `
  --rendering-method gl_compatibility `
  --rendering-driver opengl3 `
  --script res://tests/runtime_debug_jump_test.gd -- `
  --capture-panel=res://captures/runtime_debug_jump_panel.png
```

The test injects `F2`, checks modal focus and paused movement, rejects an
ambiguous matrix `0049` request without reloading, then performs a real scene
reload to AreaData `61`, cell `(1,1)`, tile `(31,31)`. It verifies one-shot
request consumption, one live streamer, four loaded chunks, zero failed
assets, and the expected tile-centered player position. The optional panel
capture must be a nonblank native `256 x 192` image with no clipped controls.

## Render Capture

```powershell
& "D:\path\to\Godot_v4.7-stable_win64_console.exe" `
  --path .\new-game-project `
  --audio-driver Dummy `
  --rendering-method gl_compatibility `
  --rendering-driver opengl3 `
  --script res://tests/render_world_capture.gd -- `
  --cell=3,27 --output=res://captures/world_player_orthographic.png

& "D:\path\to\Godot_v4.7-stable_win64_console.exe" `
  --path .\new-game-project `
  --audio-driver Dummy `
  --rendering-method gl_compatibility `
  --rendering-driver opengl3 `
  --script res://tests/render_world_capture.gd -- `
  --matrix=49 --area=61 --tile=31,31 `
  --output=res://captures/matrix_0049_area_0061.png

& "D:\path\to\Godot_v4.7-stable_win64_console.exe" `
  --path .\new-game-project `
  --audio-driver Dummy `
  --rendering-method gl_compatibility `
  --rendering-driver opengl3 `
  --script res://tests/render_world_capture.gd -- `
  --cell=5,26 --offset=-4,-2 `
  --output=res://captures/building_regression_orthographic.png

& "D:\path\to\Godot_v4.7-stable_win64_console.exe" `
  --path .\new-game-project `
  --audio-driver Dummy `
  --rendering-method gl_compatibility `
  --rendering-driver opengl3 `
  --script res://tests/render_world_capture.gd -- `
  --cell=3,27 --output=res://captures/world_player_perspective.png --perspective
```

Inspect the image for nonblank output, terrain seams, incorrect axes, building
placement, player visibility, sprite transparency, nearest filtering, and
overlapping geometry. Small destinations are ready when their selected focus
chunk is loaded; they are not required to contain nine cells. The building
regression capture must show complete blue foreground roofs without V-shaped
camera-plane cuts. All PNGs must be exactly `256 x 192` pixels, and the
reported projection and camera distance must match the requested mode.

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
no runnable destination.

`validate_repository.ps1 -Full` also requires every destination PNG import
sidecar to retain lossless compression, disabled mipmaps, and disabled 3D
texture compression before it starts the Godot material and runtime tests.
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
small-matrix chunk counts, and altitude-aware tile-centered player placement.
The integration case also verifies matrix `0000` cell `(4,25)` at nonzero
altitude; the synthetic coordinate test covers cross-cell capture offsets.

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

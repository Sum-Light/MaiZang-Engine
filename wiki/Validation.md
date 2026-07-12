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

Expected baseline:

```text
assets: 398
material_surface_references: 3249
unique_materials: 511
```

## HD2D Material Variant Validation

Build the local pilot after shared materials are configured:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tools\configure_hd2d_material_variants.ps1 `
  -ProjectRoot .\new-game-project
```

Expected pilot baseline:

```text
profile_assets: 5
unique_variants: 8
pilot_instances: 9
registered_surfaces: 22
active_overrides: Classic 0, HD2D 22
shared_base_material_hash_changes: 0 of 511
```

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
- Classic keeps a visually zero fog blend with pixel snap and ground shadow off.
- `F2` switches to HD2D and restores Classic without changing gameplay,
  streaming state, projection, Environment RID, or ground-shadow mesh RID.
- HD2D screen-plane snap stays within half an output pixel and preserves view depth.
- HD2D maps the 32-pixel player canvas to exactly 32 output pixels and keeps
  its camera-relative center unchanged while compensating the camera snap.
- The local HD2D pilot preloads exactly 8 shared variants and binds exactly 22
  surfaces across 9 instances in cell `(3, 27)`.
- F2 changes those instance overrides `0 -> 22 -> 0` while node, Mesh, base
  material, Environment, and ground-shadow resource identities remain stable.
- Base surfaces stay unshaded; variants are separate per-vertex-lit resources
  with the original texture dependency.
- Leaving the pilot cell releases all 9 instance bindings and 22 surface
  bindings; toggling HD2D at the destination affects no non-pilot surface.
- Teardown waits for a rendered cleanup frame and synchronizes the rendering
  server before exit. Full validation rejects Godot logs containing resource,
  RID, orphan, or shader cleanup errors even when the process returns success.

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
overlapping geometry. The building regression capture must show complete blue
foreground roofs without V-shaped camera-plane cuts. All PNGs must be exactly
`256 x 192` pixels, and the reported projection and camera distance must match
the requested mode.

HD-2D baseline and measurement example:

```powershell
& "D:\path\to\Godot_v4.7-stable_win64_console.exe" `
  --path .\new-game-project `
  --audio-driver Dummy `
  --rendering-method gl_compatibility `
  --rendering-driver opengl3 `
  --script res://tests/render_world_capture.gd -- `
  --visual-profile=hd2d --cell=3,27 `
  --warmup-frames=300 --measure-frames=1800 `
  --output=res://captures/hd2d_start.png `
  --metrics-output=res://captures/hd2d_start.metrics.json
```

Metrics collection must finish before PNG readback. Reports must show 9 loaded
chunks, zero failed assets, zero runtime base-material replacements, and
nonempty render samples. The pilot HD2D capture must additionally report 8
variants, 9 active pilot instances, and 22 active overrides. Classic and HD2D
captures remain local ignored artifacts.

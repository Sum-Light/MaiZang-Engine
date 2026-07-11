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
- `Z` running is faster than walking and selects columns 4-7.
- The camera follows the player at distance `8`.
- The camera starts orthographic at size `12.3`.
- `F1` switches to FOV-75 perspective and back without changing its transform.
- Default camera yaw `0`, downward pitch `60`, and wheel pitch steps of `5`.
- Mouse-wheel pitch changes preserve the follow distance.
- Correct floor-based cell boundaries.
- Long-distance load and origin unload.
- Zero failed assets and zero runtime material replacements.
- Loaded assets do not exceed the current retention set.

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
  --cell=3,27 --output=res://captures/world_player_perspective.png --perspective
```

Inspect the image for nonblank output, terrain seams, incorrect axes, building
placement, player visibility, sprite transparency, nearest filtering, and
overlapping geometry. Both PNGs must be exactly `256 x 192` pixels, and the
reported projection must match the requested mode.

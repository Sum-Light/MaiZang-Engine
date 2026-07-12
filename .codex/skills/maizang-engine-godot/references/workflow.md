# Workflow Reference

## Asset Rebuild

Run from the repository root:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\dspre_batch_export.ps1 `
  -DspreContents "D:\path\to\game_DSPRE_contents" `
  -ApiculaPath "D:\path\to\apicula.exe"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\dedupe_dspre_materials.ps1 -Force
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\sync_dspre_godot_assets.ps1
& "D:\path\to\Godot_console.exe" --headless --path .\new-game-project --import
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\configure_dspre_godot_materials.ps1 `
  -GodotPath "D:\path\to\Godot_console.exe"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\import_player_sprite.ps1 `
  -SourcePath "D:\path\to\Dawn.png"

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tools\configure_hd2d_material_variants.ps1 `
  -ProjectRoot .\new-game-project `
  -GodotPath "D:\path\to\Godot_console.exe"
```

Never run `sync_dspre_godot_assets.ps1 -Force` until the destination resolves
under `new-game-project/assets/platinum` and the generated source has passed
its summary checks.

## Validation

Fast repository checks:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\validate_repository.ps1
```

Full local asset and renderer checks:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\validate_repository.ps1 `
  -Full -GodotPath "D:\path\to\Godot_console.exe"
```

Expected Godot baselines:

- 398 imported assets.
- 3249 material-bearing mesh surface references.
- 511 unique external materials.
- 9 active chunks at the initial and destination cells.
- 0 failed assets and 0 runtime material replacements.
- Half-integer-centered one-unit cardinal steps: 16 Godot physics ticks walking,
  8 with `Z`, and 6 for a stationary turn.
- Default pitch-50, size-11.24 orthographic projection at distance 16, with a
  distance-8 FOV-75 perspective debug toggle.
- Classic/HD2D F2 roundtrip preserves gameplay and streaming; HD2D capture uses
  camera-local pixel snap, depth fog, and a prebuilt player ground shadow.
- The local world-semantic profile covers 468 cells and partitions exactly 511
  materials / 3249 primitive surfaces into shadow, water, foliage, emissive,
  ordinary, and ambiguous classes.
- Full validation regenerates the ignored eight-material P3 seed before the
  world profile, rebuilds all variants, and requires the exact generated path
  set, so pre-existing local profile state cannot mask drift.
- Runtime preloads 22 immutable variants, preserves 63 classified materials,
  and switches active overrides `0 -> registered -> 0` for streamed cells.
- HD2D generation leaves the SHA-256 of all 511 shared base materials unchanged.
- The local `272 x 136` player atlas renders all 32 padded `34 x 34` frame cells
  with source-identical alpha coordinates; use capture `--facing` for each
  cardinal world regression.

## Documentation and Memory

For every functional change, update the relevant Wiki page and
`wiki/Change-Log.md`, then run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\update_project_memory.ps1 -Stage
```

This updates both `wiki/Current-State.md` and the Skill's generated
`references/project-state.md`.

## Commit and Publish

Preferred command:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\commit_project_change.ps1 `
  -Message "Imperative commit subject" `
  -Summary "Behavioral summary and reason"
```

This stages the complete change, validates it, commits, pushes the current
branch, and synchronizes the versioned Wiki to GitHub Wiki. Use `-NoPush` for
local-only work and `-FullValidation` for broad runtime or pipeline changes.

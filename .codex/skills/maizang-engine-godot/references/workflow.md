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
- Four-direction walking, `Z` running frames, and distance-8 camera following.
- Default size-8 orthographic projection and transform-preserving `F1` toggle.

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

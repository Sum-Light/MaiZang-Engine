# MaiZang Engine

MaiZang Engine is a Godot 4.7 research project for reconstructing the Pokemon
Platinum overworld from DSPRE exports. The current milestone renders matrix
`0000`, places its static buildings, shares imported materials, and streams
map chunks around a free camera.

The repository contains the original tooling and Godot runtime written for
this project. It intentionally does not contain Pokemon models, textures,
maps, ROM data, or other proprietary game assets. Those files remain local
and are regenerated from a user-supplied DSPRE project.

## Current Status

- 468 occupied cells from the `30 x 30` main-world matrix.
- 176 unique terrain variants and 222 building/texture variants.
- 501 placed building instances.
- 480 deduplicated textures and 511 shared Godot materials.
- Native single-screen NDS viewport and window at `256 x 192`.
- `3 x 3` active chunks, `5 x 5` asset prefetch, and radius-3 retention.
- Godot 4.7 OpenGL smoke tests with zero failed asset loads.

See [the project Wiki](wiki/Home.md) for architecture, pipeline, validation,
and maintenance details.

## Rebuild Local Assets

Requirements:

- A legally obtained Pokemon Platinum ROM and a local DSPRE export.
- DSPRE's bundled `apicula.exe`.
- Godot 4.7 stable.
- Windows PowerShell 5.1 or newer.

Run the pipeline from this repository root:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\dspre_batch_export.ps1 `
  -DspreContents "D:\path\to\game_DSPRE_contents" `
  -ApiculaPath "D:\path\to\apicula.exe"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\dedupe_dspre_materials.ps1 -Force
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\sync_dspre_godot_assets.ps1

& "D:\path\to\Godot_v4.7-stable_win64_console.exe" `
  --headless --path .\new-game-project --import

powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\configure_dspre_godot_materials.ps1 `
  -GodotPath "D:\path\to\Godot_v4.7-stable_win64_console.exe"
```

Open `new-game-project/project.godot` after the import completes. Use `WASD`
to move, `Q/E` to descend or ascend, right mouse drag to look, the mouse wheel
to change speed, and `Shift` to sprint.

## Development

Read [AGENTS.md](AGENTS.md) before changing the project. Every functional
change must update the versioned Wiki and project Skill before it is committed.
Use `tools/commit_project_change.ps1` for the normal commit and Wiki sync flow.

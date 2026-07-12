# MaiZang Engine

MaiZang Engine is a Godot 4.7 research project for reconstructing the Pokemon
Platinum overworld from DSPRE exports. The current milestone renders matrix
`0000`, places its static buildings, shares imported materials, and streams
map chunks around a playable Dawn character.

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
- Source-paced cardinal grid movement: one 16-pixel tile in 16 Godot physics
  ticks while walking or 8 ticks while holding `Z` to run.
- A size-11.24 orthographic follow camera with a 50-degree pitch, mouse-wheel
  pitch control, distance 16 to prevent the reproduced roof clipping, and an
  `F1` perspective debug view.
- Reversible Classic/HD2D visual profiles with orthographic pixel stability,
  restrained cool-depth/warm-sun atmosphere, and a pixel-scale player ground
  shadow. Classic remains the default A/B baseline; `F2` enables the preview.
- A world-scale semantic material profile that classifies all 511 materials and
  3249 surfaces, preserving pixel-critical water/foliage/shadows while applying
  reversible lit and low-energy emissive instance overrides; both ignored
  profile stages are reproducibly regenerated from tracked rules and manifests.
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

powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\import_player_sprite.ps1 `
  -SourcePath "D:\path\to\Dawn.png"
```

Open `new-game-project/project.godot` after the import completes. Use `WASD`
or the arrow keys for four-direction movement, hold `Z` to run, and use the
mouse wheel to adjust the follow camera pitch in 5-degree steps. Press `F1`
to toggle between the default orthographic view and the perspective debug view.
Press `F2` to compare the Classic baseline with the HD2D preview.

## Development

Read [AGENTS.md](AGENTS.md) before changing the project. Every functional
change must update the versioned Wiki and project Skill before it is committed.
Use `tools/commit_project_change.ps1` for the normal commit and Wiki sync flow.
Run `tools/capture_hd2d_visual_matrix.ps1` after any atmosphere, lighting,
camera, material, or sprite-rendering change.

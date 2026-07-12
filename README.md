# MaiZang Engine

MaiZang Engine is a Godot 4.7 research project for reconstructing the Pokemon
Platinum overworld from DSPRE exports. The current milestone catalogs every
source matrix, renders strict AreaData-aware destinations, shares imported
materials, and streams map chunks around a playable Dawn character. Matrix
`0000` remains the default overworld.

The repository contains the original tooling and Godot runtime written for
this project. It intentionally does not contain Pokemon models, textures,
maps, ROM data, or other proprietary game assets. Those files remain local
and are regenerated from a user-supplied DSPRE project.

## Current Status

- 289 inventoried source matrices, with 276 strict-ready matrices exposed
  through 278 runnable destinations.
- Separate AreaData destinations for matrices `0049` and `0052`.
- 13 unreferenced or internally inconsistent source records retained as
  unresolved metadata instead of receiving guessed textures.
- Catalog totals: 1,153 occupied cells, 3,041 building instances, and 2,042
  destination-scoped GLBs.
- Matrix `0000` retains its 468 occupied cells, 176 terrain variants, 222
  building/texture variants, and 501 placed building instances.
- Catalog-wide deduplication yields 1,722 unique texture keys and 1,804 shared
  external material keys.
- Native single-screen NDS viewport and window at `256 x 192`.
- Source-paced cardinal grid movement: one 16-pixel tile in 16 Godot physics
  ticks while walking or 8 ticks while holding `Z` to run.
- A size-11.24 orthographic follow camera with a 50-degree pitch, mouse-wheel
  pitch control, distance 16 to prevent the reproduced roof clipping, and an
  `F1` perspective debug view.
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
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\dspre_export_all_matrices.ps1 `
  -DspreContents "D:\path\to\game_DSPRE_contents" `
  -ApiculaPath "D:\path\to\apicula.exe" `
  -GodotPath "D:\path\to\Godot_v4.7-stable_win64_console.exe"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\import_player_sprite.ps1 `
  -SourcePath "D:\path\to\Dawn.png"
```

Open `new-game-project/project.godot` after the import completes. Use `WASD`
or the arrow keys for four-direction movement, hold `Z` to run, and use the
mouse wheel to adjust the follow camera pitch in 5-degree steps. Press `F1`
to toggle between the default orthographic view and the perspective debug view.

For a debug start at another destination, edit the `maizang/debug/*` project
settings or pass user arguments after `--`, for example:

```text
--matrix=49 --area=61 --cell=0,0 --tile=16,16
```

## Development

Read [AGENTS.md](AGENTS.md) before changing the project. Every functional
change must update the versioned Wiki and project Skill before it is committed.
Use `tools/commit_project_change.ps1` for the normal commit and Wiki sync flow.

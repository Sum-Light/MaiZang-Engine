# Workflow Reference

## Asset Rebuild

Run from the repository root:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\dspre_export_all_matrices.ps1 `
  -DspreContents "D:\path\to\game_DSPRE_contents" `
  -ApiculaPath "D:\path\to\apicula.exe" `
  -GodotPath "D:\path\to\Godot_console.exe"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\import_player_sprite.ps1 `
  -SourcePath "D:\path\to\Dawn.png"
```

The orchestrator resolves all source matrices, exports each strict destination,
deduplicates and syncs it, writes `matrix_catalog.json`, and performs one
initial import plus one configured reimport. Raw, dedupe, and sync marker
schema `2` binds every normalized output path, byte length, and SHA-256 to the
current input and stage-tool hashes, preventing partial, replaced, or stale
directories from being reused. Direct batch export reuses only a wholly valid
destination; otherwise it rebuilds the complete output and work slice. Partial
`-MatrixIds` publication first requires every unselected raw, dedupe, and sync
destination to match the same current input fingerprints and exact downstream
file sets. Published catalogs are removed before destination mutation and
restored from a temporary pair only after complete catalog aggregation, all
278 stage-marker identities are revalidated, and the final seven-input scan
passes; a controlled
publication failure withdraws both. Obsolete matrix-shaped stage directories
are removed only after all three stage trees pass non-following safety
preflight. Recursive cleanup scans each tree once immediately before deletion;
individual work writes validate their ancestor path without rescanning the
whole tree. Root creation, cleanup, work writes, file traversal, and publication
reject junctions and other reparse points from the repository root downward
without following them. Complete validation requires the
generated and Godot catalogs to be byte-identical and cross-checks the actual
generated raw/dedupe trees against the Godot sync tree. Use
`-RebuildExisting`
only for an intentional rebuild. Never run
`sync_dspre_godot_assets.ps1 -Force` until the destination resolves under
`new-game-project/assets/platinum` and the generated source has passed its
summary checks.

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

The full validator first runs
`tools/validate_dspre_matrix_catalog.ps1 -RequireComplete`, then validates all
lossless/no-mipmap texture imports, external materials, the matrix `0000`
streaming baseline, default and command-line debug destinations, and the
in-game F2 destination reload path.

Expected Godot baselines:

- 289 inventoried source matrices.
- 276 strict ready matrices through 278 destination manifests.
- 13 unresolved source records with no runtime destination.
- Catalog-derived imported asset, material-surface, texture, and external
  material counts; no matrix `0000` count is used as a global assertion.
- 9 active chunks around the matrix `0000` start and all available retained
  chunks for a smaller debug destination.
- 0 failed assets and 0 runtime material replacements.
- Half-integer-centered one-unit cardinal steps: 16 Godot physics ticks walking,
  8 with `Z`, and 6 for a stationary turn.
- Default pitch-50, size-11.24 orthographic projection at distance 16, with a
  distance-8 FOV-75 perspective debug toggle.

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

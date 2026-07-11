# Asset Pipeline

## Inputs

The pipeline expects a local DSPRE project and DSPRE's bundled `apicula.exe`.
Neither the input data nor generated Pokemon assets are stored in Git.

The matrix `0000` pipeline currently resolves:

- Matrix cells and map IDs.
- Map header to area-data mapping.
- Terrain model plus map texture pairs.
- Building model plus building texture variants.
- Per-cell building position, rotation, and size records.

## Stages

### 1. Export GLBs

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\dspre_batch_export.ps1 `
  -DspreContents "D:\path\to\game_DSPRE_contents" `
  -ApiculaPath "D:\path\to\apicula.exe"
```

The script extracts each terrain BMD0 section, pairs models with the area-data
texture set, exports isolated GLB directories, and writes `manifest.json`.
Conversion is resumable and validates every GLB header.

Baseline output:

| Metric | Count |
|---|---:|
| Occupied cells | 468 |
| Unique terrain variants | 176 |
| Unique building variants | 222 |
| Building instances | 501 |
| GLBs | 398 |

### 2. Deduplicate Textures and Materials

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\dedupe_dspre_materials.ps1 -Force
```

The dedupe pass hashes image content, rewrites GLB image URIs into a shared
texture pool, merges duplicate material slots within each GLB, and emits a
global material catalog. GLB binary geometry chunks remain byte-identical.

| Metric | Before | After |
|---|---:|---:|
| PNG references/files | 3060 | 480 |
| Material slots | 3192 | 3095 |
| Unique visual materials | 3192 | 511 |

### 3. Sync into Godot

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\sync_dspre_godot_assets.ps1
```

The script uses hard links when source and destination are on the same volume,
otherwise it copies. The destination is
`new-game-project/assets/platinum/matrix_0000`.

### 4. Import Shared Materials and Lossless Textures

Run one initial Godot import, then:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\configure_dspre_godot_materials.ps1 `
  -GodotPath "D:\path\to\Godot_v4.7-stable_win64_console.exe"
```

This generates 511 external materials, configures all 398 scene imports to use
them, and reimports all 480 textures with lossless compression and no mipmaps.

## Rebuild Rule

Do not hand-edit generated GLB, PNG, `.import`, material, or manifest output.
Change the converter or import script, rebuild, then validate the complete set.

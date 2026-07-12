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

### 5. Import the Local Player Sprite

The public repository does not contain Pokemon character art. Build the local
Dawn atlas from the supplied source sheet with:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\import_player_sprite.ps1 `
  -SourcePath "D:\path\to\Dawn.png"
```

The script extracts the 4-frame walk group at `(0, 0)` and the 4-frame run
group at `(170, 0)`, removes both source background colors, and writes an
`8 x 4` transparent atlas to the ignored path
`new-game-project/assets/platinum/characters/dawn_overworld.png`.

### 6. Build Local HD2D Material Variants

The public repository contains the builder, validator, and a placeholder
profile schema. The real profile and generated variants remain under the
ignored Platinum asset tree because their material keys are ROM-derived.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tools\configure_hd2d_material_variants.ps1 `
  -ProjectRoot .\new-game-project `
  -GodotPath "D:\path\to\Godot_v4.7-stable_win64_console.exe"
```

The wrapper first regenerates the ignored `(3, 27)` P3 seed from the manifest
and catalog, then derives the ignored world-semantic profile from tracked
rules, the local manifest/material catalog, and all 398 GLB JSON chunks. It then
builds 22 shared resources: six retained `lit_vertex` variants and 16
`emissive_window` variants. Water, alpha foliage, legacy shadows, and one
ambiguous material remain base-only through 63 explicit preserve policies.

Generation validates an exact partition of 511 materials and 3249 primitive
surface references. The seed stage derives and asserts its nine instances and
22 selected primitive surfaces from the GLBs. The builder recursively removes
stale variants even under unknown legacy tag directories, and the validator
accepts only the exact 22 generated paths. All 511 shared base `.tres` files are
hashed before and after the operation, including failed builds; any base change
fails the command.

## Rebuild Rule

Do not hand-edit generated GLB, PNG, `.import`, material, atlas, HD2D variant,
or manifest output. Change the converter, profile, or import script, rebuild,
then validate the complete set.

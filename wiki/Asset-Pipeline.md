# Asset Pipeline

## Inputs

The pipeline expects a local DSPRE project and DSPRE's bundled `apicula.exe`.
Neither the input data nor generated Pokemon assets are stored in Git.

The matrix pipeline resolves:

- Matrix cells and map IDs.
- Map header to area-data mapping.
- Multiple AreaData variants for headerless matrices reached through different
  headers.
- Terrain model plus map texture pairs.
- Building model plus building texture variants.
- Per-cell building position, rotation, and size records.

The source contains 289 matrix records. Strict resolution exposes 276 matrices
through 278 runnable destinations. Matrix `0049` has AreaData `4` and `61`
variants, while matrix `0052` has AreaData `8` and `54` variants.

AreaData resolution follows this order:

1. Per-cell headers embedded in a matrix.
2. Every distinct MapHeader AreaData linked to a headerless matrix.
3. A unique map ID reused by a header-backed matrix.
4. A unique complete match between the model's Nitro texture/palette names and
   one AreaData texture set.
5. An unresolved catalog entry when the source has no unique answer.

Thirteen unreferenced source matrices remain unresolved rather than receiving
guessed textures: `0027`, `0028`, `0029`, `0032`, `0033`, `0037`, `0038`,
`0054`, `0055`, `0056`, `0067`, `0158`, and `0202`. Matrix `0202` cannot be
satisfied by any single source texture bundle. These records are not exposed
as runtime debug destinations.

The complete runnable catalog contains 1,153 occupied matrix cells, 3,041
building instances, and 2,042 destination-scoped GLBs. Across those
destinations it identifies 645 terrain keys, 764 building keys, 1,722 unique
texture keys, and 1,804 unique material keys.

## Stages

### 1. Export the Matrix Catalog

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\dspre_export_all_matrices.ps1 `
  -DspreContents "D:\path\to\game_DSPRE_contents" `
  -ApiculaPath "D:\path\to\apicula.exe" `
  -GodotPath "D:\path\to\Godot_v4.7-stable_win64_console.exe"
```

The all-matrix command resolves AreaData, exports each runnable destination,
deduplicates it, syncs it into the ignored Godot asset tree, writes
`matrix_catalog.json`, imports the assets, and configures shared materials and
textures. Conversion is resumable. Use `-RebuildExisting` for an intentional
full rebuild and `-SkipGodotImport` when only refreshing offline assets.
Raw export, material dedupe, and Godot sync are treated as separate stages.
The latter two write their completion marker last and bind it to the upstream
manifest SHA-256. A missing, damaged, or mismatched marker rebuilds that stage
instead of reusing a possibly partial directory.

For a focused single-matrix export, use `dspre_batch_export.ps1 -MatrixId`.
The exporter automatically discovers the generated AreaData resolution file
and verifies its DSPRE source and header-table offset. Matrices with multiple
linked areas also require `-AreaDataId`.

Generated layout:

```text
generated/dspre_glb/matrix_####/
generated/dspre_glb_dedup/matrix_####/
generated/dspre_glb/matrix_0049_area_0004/
generated/dspre_glb_dedup/matrix_0049_area_0004/
new-game-project/assets/platinum/matrix_####/
new-game-project/assets/platinum/matrix_catalog.json
```

All of these generated paths remain ignored by Git.

The original matrix `0000` baseline remains:

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

The dedupe pass runs once per destination. It hashes image content, rewrites
GLB image URIs into that destination's shared texture pool, merges duplicate
material slots within each GLB, and emits a material catalog. The all-matrix
catalog also computes global unique asset, image, and material keys. GLB binary
geometry chunks remain byte-identical. Matrix `0000` remains the reference
for the before/after figures below:
Zero-texture GLBs are valid and retain zero-byte texture-pool totals.

| Metric | Before | After |
|---|---:|---:|
| PNG references/files | 3060 | 480 |
| Material slots | 3192 | 3095 |
| Unique visual materials | 3192 | 511 |

### 3. Sync into Godot

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\sync_dspre_godot_assets.ps1
```

The script derives the destination from the manifest variant, uses hard links
when source and destination are on the same volume, and otherwise copies. Its
GLB and PNG checks come from the manifest instead of fixed matrix `0000`
counts. Matrix ID and AreaData suffixes must agree with the manifest before the
destination is created, and source/destination path overlap is rejected before
any existing output can be removed. The source dedupe marker, manifest hash,
GLB/PNG sets, and material catalog are fully preflighted before an existing
destination can be removed.

### 4. Import Shared Materials and Lossless Textures

Run one initial Godot import, then:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\configure_dspre_godot_materials.ps1 `
  -GodotPath "D:\path\to\Godot_v4.7-stable_win64_console.exe"
```

This reads every runnable catalog destination, generates or reuses external
materials by stable material key, configures every scene import, and reimports
all destination textures with lossless compression and no mipmaps. One initial
import and one final reimport cover the complete catalog. If a complete builder
run succeeds but later sidecar or import work is interrupted,
`configure_dspre_godot_materials.ps1 -SkipMaterialBuild` resumes only after the
physical shared-material count matches the catalog.
If an open editor rewrites a subset of material or texture import sidecars
during reimport, the workflow retries only those missing mappings or invalid
texture settings and then revalidates the complete catalog.

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

## Rebuild Rule

Do not hand-edit generated GLB, PNG, `.import`, material, atlas, or manifest
output. Change the converter or import script, rebuild, then validate the
complete set.

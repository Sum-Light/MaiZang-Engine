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
- Per-cell building position, rotation, and exact FX32 scale records.
- Per-map `32 x 32` terrain attributes and complete BDHC payloads.
- Per-cell collision references and the source-faithful rule that map-prop
  blocking is owned by the cell terrain attributes rather than visual meshes.

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
texture keys, and 1,804 unique material keys. Collision data is keyed only by
map ID, independently of AreaData and texture variants. The complete catalog
therefore expects 637 globally unique collision assets and 647
destination-scoped collision assets. Each collision asset contributes exactly
1,024 terrain-attribute tiles and one BDHC payload.

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
All three write their completion marker last. Raw export writes
`.export-complete.json` with marker schema `2`, export contract `3`, the
matrix/variant binding, manifest SHA-256, occupied-cell count, and collision
asset count. It also binds the raw output to the complete DSPRE content tree,
batch exporter, shared collision support tool, `apicula.exe`, and semantic
AreaData resolution fingerprints. Dedupe and sync retain marker schema `1` and
bind their output to the upstream manifest SHA-256. A missing, damaged,
obsolete, or mismatched marker rebuilds that stage instead of reusing a
possibly partial directory.

The DSPRE source fingerprint recursively covers every file below the selected
`*_DSPRE_contents` root. It hashes an ordinally sorted stream of normalized
relative path, exact byte length, and per-file SHA-256 records. Absolute source
paths, timestamps, and the root directory name are not included, so identical
content relocated to another root retains the same fingerprint. The
all-matrix orchestrator computes this expensive fingerprint once and passes it
to every batch export; direct `dspre_batch_export.ps1` calls compute it when no
fingerprint is supplied.

Tool fingerprints are content-only SHA-256 values and are likewise independent
of installation path. The AreaData resolution fingerprint excludes its
generated timestamp and absolute DSPRE path, but includes the semantic matrix,
variant, AreaData, evidence, and unresolved records. Any source, tool, or
semantic resolution change invalidates raw reuse and forces both existing GLBs
and `.work` model slices to be rebuilt. The orchestrator recomputes every input
fingerprint after the destination loop and refuses to publish a catalog if any
source or tool changed during the run.

For a focused single-matrix export, use `dspre_batch_export.ps1 -MatrixId`.
The exporter automatically discovers the generated AreaData resolution file
and verifies its DSPRE source and header-table offset. Matrices with multiple
linked areas also require `-AreaDataId`.

Raw manifests use schema `2`. The dedupe stage validates that schema, preserves
the collision payload unchanged, adds `material_dedupe`, and emits destination
manifest schema `3`. `matrix_catalog.json` uses schema `2`; all Godot-side
material, texture, streaming, and validation consumers require those exact
versions.

Each raw and deduplicated manifest contains a `collision_format` schema `1`
record and a map-ID-deduplicated `collision_assets` array. A collision asset is
named `map_####_collision` and embeds both source sections without lossy JSON
number conversion:

- `terrain_attributes.data_base64` is the exact 2,048-byte, row-major `a.dat`
  payload. Bit `0x8000` is static collision and mask `0x00ff` is tile behavior.
- `bdhc.data_base64` is the complete source `BDHC` byte sequence. Its header
  counts, exact byte length, magic, and SHA-256 are retained alongside it.
- Both payloads have independent SHA-256 values which are recomputed after
  Base64 decoding by every offline pipeline boundary.
- Every occupied cell names its map's payload through `collision_asset_key`.
  No collision asset may be orphaned or disagree with the cell's `map_id`.
- Every building retains signed `scale_fx32`, a decoded `scale`, and
  `collision.mode = cell_terrain_attributes`. `build_model_matshp.dat` is a
  rendering material/shape table, not a source of physical collision boxes.

BDHC uses signed 20.12 fixed point, a map-center X/Z origin, 16 source units per
tile, and 16 source units per Godot world unit. BDHC plate heights are absolute
field heights: matrix altitude remains visual placement metadata and must not
be added to a sampled collision height.

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
| Collision assets / BDHC payloads | 176 |
| Terrain-attribute tiles | 180,224 |
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

Before touching GLBs, the stage validates manifest schema `2`, every packed
terrain/BDHC length and hash, BDHC indices and strip ordering, cell references,
and building scale/collision descriptors. Its schema `3` output is revalidated
by the orchestrator, so material processing cannot silently drop collision
data.

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
GLB/PNG sets, material catalog, destination manifest schema `3`, and complete
collision contract are fully preflighted before an existing destination can be
removed. Sync copies the manifest itself, so the embedded Base64 payloads and
their hashes cross into Godot without a separate sidecar lifecycle.

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

Do not hand-edit generated GLB, PNG, `.import`, material, atlas, manifest, or
completion-marker output. Change the converter or import script, rebuild, then
validate the complete set. A collision-schema or export-contract change must
invalidate raw export first; relying only on the downstream manifest hashes
would preserve stale source data.

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
asset count. It also records every raw output's relative path, byte length, and
SHA-256, and binds the raw output to the complete DSPRE content tree, batch
exporter, shared collision support tool, `apicula.exe`, and semantic AreaData
resolution fingerprints. A direct header-backed export without a resolution
file records a null resolution fingerprint, which direct dedupe accepts only
when the marker and expected contract are both unbound. Dedupe and sync use
marker schema `2`.
Dedupe binds its output to the upstream manifest and current dedupe-tool
SHA-256; sync binds to that manifest plus the current dedupe- and sync-tool
SHA-256 values. Both downstream markers record every output's normalized
relative path, exact byte length, and SHA-256. Godot-generated `.import`
sidecars are excluded from the sync record and destination post-check because
an open editor can create them during the copy; complete validation also ignores
Godot's transient `.import~*.TMP` atomic-write files. Source files and every
other destination file remain exact. Import sidecars are validated by the import
workflow. A missing, damaged, obsolete, or mismatched marker rebuilds
that stage instead of reusing a possibly partial directory.

A direct `dspre_batch_export.ps1` call may reuse a destination only when its
marker, manifest, summary, collision contract, declared GLBs, complete file
records, and all current input/tool fingerprints pass together. Otherwise it
removes and rebuilds the entire destination plus its matrix work slice; it
never re-certifies individual old GLBs from a valid header alone.

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
variant, AreaData, evidence, and unresolved records. Source, batch-export,
collision-support, `apicula.exe`, or semantic resolution changes invalidate raw
reuse and force both existing GLBs and `.work` model slices to be rebuilt.
Dedupe- or sync-tool changes invalidate only their downstream stage and later
stages. After complete catalog aggregation, the orchestrator recomputes all
seven source/tool/resolution fingerprints and refuses to publish if any input
changed during the run. It also revalidates all 278 expected raw, dedupe, and
sync marker identities immediately before that final fingerprint scan. Exact
file content is checked once before a stage is reused or consumed and again by
complete repository validation, rather than repeatedly hashing the same tree
after each successful child stage.

Shared-material validation compares texture pixels only after decompressing any
imported compressed `Image` copies, then normalizing both sides to RGBA8. This
keeps reuse checks content-based without asking Godot to convert a compressed
format directly.

A partial all-matrix run using `-MatrixIds` may publish a complete catalog only
after every unselected variant passes its current raw marker, manifest,
summary, collision, dedupe, and Godot-sync contracts against the same source,
tool, and AreaData fingerprints. Downstream checks compare exact file sets and
content, validate every GLB header, and reconcile PNGs and material bindings
with the material catalog instead of accepting equal file counts. This
preflight occurs before either published catalog or any destination is changed;
stale unselected output requires a full run. After preflight, both existing
`matrix_catalog.json` copies are withdrawn before destination mutation. After
catalog aggregation and the final fingerprint check, two temporary files are
written and promoted as a pair. A controlled failure removes both final paths,
so no old or half-published catalog points into a partially replaced asset
tree.

After both old catalogs are withdrawn, matrix-shaped directories no longer in
the current AreaData resolution are removed from raw, dedupe, and Godot output
only after candidates across all three trees pass the same non-following
reparse preflight. Other project asset roots such as `characters` and
`shared_materials` are not part of that cleanup.

Every recursive output removal in raw export, material dedupe, and Godot sync
must be a strict descendant of its declared generated root. The shared safety
check rejects the root itself and every junction or other reparse point from
that root through the target before `Remove-Item -Recurse` can run. The
all-matrix orchestrator applies the same check to the raw, dedupe, and Godot
roots before creating them, inspecting or withdrawing catalogs, and again
before catalog publication. Each delete target and stage-file traversal also
uses an explicit breadth-first walk that rejects a reparse file or directory
without descending through it. Direct raw output is restricted to `generated/`
and work slices to `.work/`. Recursive cleanup performs one complete non-following
tree check immediately before deletion, while each model write validates its
exact ancestor path without rescanning the whole work tree.

For a focused single-matrix export, use `dspre_batch_export.ps1 -MatrixId`.
The exporter automatically discovers the generated AreaData resolution file
and verifies its DSPRE source and header-table offset. Matrices with multiple
linked areas also require `-AreaDataId`.

Raw manifests use schema `2`. The dedupe stage validates that schema, preserves
the collision payload unchanged, adds `material_dedupe`, and emits destination
manifest schema `3`. `matrix_catalog.json` uses schema `2`; all Godot-side
material, texture, streaming, and validation consumers require those exact
versions. Per-destination `material_catalog.json` uses schema `1`.
Every material entry must contain an object signature, and every GLB must bind
at least one known material with a positive matching unique output count before
dedupe reuse, Godot sync, or catalog publication can proceed.

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
GLB/PNG sets, material catalog, destination manifest schema `3`, complete
collision contract, tool hashes, and dedupe marker's exact file records are
fully preflighted before an existing destination can be removed. The completed
sync is compared byte-for-byte with that source set before its marker is
published. Sync copies the manifest itself, so the embedded Base64 payloads and
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

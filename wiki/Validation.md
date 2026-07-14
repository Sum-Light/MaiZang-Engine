# Validation

## PowerShell Syntax

Parse every project script before committing workflow changes:

```powershell
$bad = @()
Get-ChildItem .\tools -Filter *.ps1 | ForEach-Object {
  $errors = $null
  $tokens = $null
  [Management.Automation.Language.Parser]::ParseFile(
    $_.FullName, [ref]$tokens, [ref]$errors
  ) | Out-Null
  if ($errors.Count) { $bad += $_.FullName }
}
if ($bad.Count) { throw "PowerShell syntax failures: $bad" }
```

Fast repository validation also runs the proprietary-data-free collision
parser test:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tools\test_dspre_collision_support.ps1

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tools\test_dspre_field_feature_support.ps1

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tools\test_dspre_map_animation_support.ps1

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tools\test_dspre_sync_incremental.ps1
```

It synthesizes a land-data file in memory and verifies exact Base64 retention
of `a.dat` collision/behavior bits and signed FX32 BDHC data. The focused test
rejects a truncated source, out-of-range plate indices, and zero-Y plate
normals. The same shared validator is used at every pipeline boundary to reject
inconsistent array counts, invalid hashes, missing cell references, and invalid
building scale/collision descriptors. The test also proves that the complete
DSPRE tree fingerprint is stable across absolute root relocation and file
creation order, while a same-length content edit or relative-path rename changes
it. Tool hashes ignore installation path but react to content changes. Area
resolution hashes ignore generated time and absolute source path while reacting
to semantic resolution changes. All-matrix export recomputes all seven source,
stage-tool, and semantic fingerprints after catalog aggregation and before
publication, detecting input changes made during a run.
The same focused test validates raw marker schema, exact raw file records, and
real manifest hashes,
proves that stale unselected raw output is rejected before a catalog sentinel
can change, and creates a real Windows junction to verify that recursive-delete
validation preserves an external sentinel. Static ordering checks require
partial preflight before catalog withdrawal or destination mutation and require
all three destructive pipeline consumers to call the shared safety helper. It
also injects same-length content replacement and same-count path replacement at
both raw and downstream boundaries, nested directory junctions, and a failure
during the second catalog promotion to prove exact stage records and
dual-catalog withdrawal. It additionally proves stale destination cleanup is
all-or-nothing around junctions and that direct batch reuse is wired to a
whole-destination contract; Godot `.import` sidecars remain an explicit
exception.

The focused incremental-sync test proves that direct sync retains its strict
source-record validation while the all-matrix caller can bind the already
validated dedupe marker by SHA-256. It verifies that forced reconciliation
retains unchanged GLB/PNG files and their `.import` sidecars, clears sidecars
for changed or deleted assets, uses the hard-link path without a redundant
destination hash, and recovers an interrupted `.sync-in-progress.json`
transaction. It also rejects a mutated trusted marker and unexpected managed
files before changing the destination. These focused checks optimize rebuilds;
complete matrix-catalog validation still hashes every managed stage file.

## Collision and Height Validation

The Godot collision subsystem has two asset-independent focused tests:

```powershell
& "D:\path\to\Godot_v4.7-stable_win64_console.exe" `
  --headless --path .\new-game-project `
  --script res://tests/platinum_collision_map_test.gd

& "D:\path\to\Godot_v4.7-stable_win64_console.exe" `
  --headless --path .\new-game-project `
  --script res://tests/player_collision_test.gd
```

The first decodes schema-4 Base64 payloads and covers static collision bit
`0x8000`, directional barriers, overlapping BDHC plate selection with explicit
bridge-layer context, and the exact 20-source-unit (`1.25` world-unit) height
discontinuity. It also verifies that walk movement fails closed on sea-water
behavior, a directional ledge can override bit 15 and report a two-grid landing,
unknown and ice behaviors report unsupported special actions, and map props are
indexed by global tile even when their anchors extend into another matrix cell.
These results only expose requirements to action executors. Static ordinary
Warp is implemented separately; Surf, ice movement, and ledge-jump animation
are not. The test additionally covers collision-cache pruning independent of
rendered chunks, including an ambiguous inner bridge that must return
`requires_bridge_context` until a trusted layer is supplied. The second test
verifies missing, incomplete, malformed, mid-step-lost, mid-step-replaced, and
callback-reentrant provider replacement or queued deletion fail closed. It also
proves a rejected provider cannot mutate the active context snapshot;
`ok` and `blocked` must be actual booleans,
`landing_target` must equal the normal target, and `next_context` must be
explicit and typed; special or named actions cannot enter the normal path;
invalid targets and height samples are rejected; and a
permitted 16-tick step resamples BDHC throughout a slope while committing the
final sampled height.

A generated destination can be checked directly without loading its GLBs:

```powershell
& "D:\path\to\Godot_v4.7-stable_win64_console.exe" `
  --headless --path .\new-game-project `
  --script res://tests/platinum_collision_map_test.gd -- `
  --real-manifest=res://assets/platinum/matrix_0049_area_0061/manifest.json
```

Real-data integration is also part of the matrix `0000` streaming smoke test:
it requires 176 source collision assets, at least one decoded retained asset,
zero decode failures, a known `a.dat` blocked step, and BDHC-derived spawn and
movement heights. Matrix altitude affects visual placement only; validation
explicitly rejects adding it to the absolute BDHC ground height.

## Warp and MapProp Animation Validation

The focused field-feature test decodes synthetic `zone_event` members, proves
Warp ID/order and source/destination coordinate resolution, exports no NPC
objects, and checks source-derived dynamic Warp metadata. The map-animation
support test validates all 590 descriptor members, 98 animation members, 20
door mappings, BCA/BTA/BTP identification, and atomic archive extraction.

Two asset-independent Godot tests cover the central 30 Hz map-animation clock,
weak-reference unload, automatic loop phase, door one-shots, unsupported
BTA/BTP slots, JSON-round-tripped exact integer fields with fractional rejection,
strict transition requests, reload rollback, and player signal validation. The
real OpenGL integration test starts below model-441's door in
matrix `0007`, walks into static Header `203` Warp `4`, and requires a complete
door/fade reload to matrix `0086` Header `295` Warp `4`. It then verifies the
arrival Header survives a shared destination context and the reciprocal Warp
resolves without a scene-tree scan.

Coordinate coverage also proves that an entered adjacent Warp is selected
instead of an unrelated Warp on the current tile, except when directional or
automatic current-tile behavior is the transition source. Collision/runtime
coverage fixes Platinum's east/west/south directional and north automatic
Warp behavior table and exercises automatic arrival behaviors `0x67` and
`0x6E`: the
one-step escape ignores only the current transition, preserves target special
rules, remains active on the arrival tile, and clears after the player leaves.

## Shared Material Validation

```powershell
& "D:\path\to\Godot_v4.7-stable_win64_console.exe" `
  --headless --path .\new-game-project `
  --script res://tools/validate_shared_materials.gd
```

The validator reads every runnable destination from `matrix_catalog.json`,
checks every GLB against its material catalog and raw GLB content, rejects null
material surfaces, verifies every material surface uses the expected external
`.tres`, and rejects unreferenced material resources. For a bounded
parser/import check, pass `-- --limit-assets=1`.

The synthetic material-signature and nonzero-altitude coordinate checks do not
depend on generated Platinum assets:

```powershell
& "D:\path\to\Godot_v4.7-stable_win64_console.exe" `
  --headless --path .\new-game-project `
  --script res://tests/material_catalog_support_test.gd

& "D:\path\to\Godot_v4.7-stable_win64_console.exe" `
  --headless --path .\new-game-project `
  --script res://tests/debug_coordinate_test.gd
```

The material-signature test also compares equivalent compressed and
uncompressed texture images, proving that shared-material reuse decompresses
before RGBA8 pixel comparison.

The focused `-SkipMaterialBuild` recovery path still finishes with a complete
mapping, texture-setting, and shared-material validation. During the Warp and
MapProp-animation rebuild, the initial Godot pass imported 45 changed assets;
focused recovery found 876 stale GLB mappings and 1,999 historical matrix
texture sidecars with invalid settings. It repaired mappings in batches of at
most 96, changed only the affected scene and texture caches, included the Dawn
global PNG, and converged to 2,042 external GLB mappings, 4,567 configured
textures, and 1,804 shared materials after one combined deferred import. These
measured counts describe that local rebuild; catalog-derived counts remain the
validation authority for later source revisions.

## Matrix Catalog Validation

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tools\validate_dspre_matrix_catalog.ps1 -RequireComplete
```

This validates all 289 matrix status records, all 278 expected destination
keys, their matrix/AreaData bindings, one-to-one matrix ownership, default
occupied cells, unique manifest-relative GLB paths, GLB headers, stage-complete
manifest hashes, current dedupe/sync tool hashes, exact marker-recorded file
sets and content, recomputed summary counts, and the 13 unresolved records with
no runnable destination. Complete mode first requires the generated and Godot
catalog files to exist and be byte-identical. It requires catalog schema `3`,
downstream marker schema `2`, material-catalog schema `1`, and destination
manifest schema `4`, then validates every embedded collision, Warp, Header,
and animation descriptor through the shared parsers. The collision count
contract is 637 globally unique and 647
destination-scoped collision assets, with exactly 1,024 terrain tiles and one
BDHC payload per destination-scoped asset. This yields 662,528
destination-scoped terrain tiles and 647 destination-scoped BDHC payloads.
Reused map IDs must retain identical terrain and BDHC hashes across AreaData
variants.

Complete mode also requires the actual `generated/dspre_glb` and
`generated/dspre_glb_dedup` roots to contain exactly the 278 expected
destination directories. It validates every raw and dedupe marker against the
current stage tools and exact file records, requires one DSPRE/apicula snapshot
across all raw destinations, and proves each generated dedupe marker and
payload is identical to its validated Godot sync counterpart. Reparse points
are rejected from the repository root through every stage ancestor and before
any catalog, destination manifest, or recursive stage file is read. Material
catalog validation also rejects non-object signatures, empty bindings,
unknown keys, and non-positive output material counts before Godot sees the
catalog. Repeated surface bindings may share one material key; the output count
tracks the unique bound keys, matching the Godot consumer.

`validate_repository.ps1 -Full` also requires every destination PNG import
sidecar plus the Dawn global PNG to retain lossless compression, disabled
mipmaps, and disabled 3D texture compression before it starts the Godot
material and runtime tests.
It runs the collision-map and player-collision tests before the real renderer
smoke tests.
The fast validation also guards the destructive sync ordering: an explicitly
requested cross-volume hard-link transfer must fail before an existing Godot
destination can be removed.

The field-texture support tests cover all 52 `fldtanime` records, 30 Hz
`delay + 1` timing, TEX0 texture formats and palette selection, content-pooled
frame output, the cross-format `sea` target-prefix transfer, exact stage reuse,
and fail-closed ambiguous palette variants. Transaction tests inject builder,
catalog publication, backup-cleanup, import, sidecar, and missing-cache failures
and require an atomic pair plus a resumable import boundary.
Complete catalog validation checks every pooled frame's path, length, SHA-256,
and generated/Godot byte identity. For a field-texture-only change, use the
focused path without rescanning unrelated destination GLBs, collision, or
materials:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tools\validate_dspre_matrix_catalog.ps1 `
  -ProjectRoot . `
  -FieldTextureAnimationsOnly
```

## Field Texture Animation Test

```powershell
& "D:\path\to\Godot_v4.7-stable_win64_console.exe" `
  --path .\new-game-project `
  --audio-driver Dummy `
  --rendering-method gl_compatibility `
  --rendering-driver opengl3 `
  --script res://tests/field_texture_animation_streaming_test.gd
```

The synthetic controller test proves lazy non-subthreaded loading, shared
runtime material copies, original first-hold timing, weak ownership, and
nonblocking pending-request handoff across controller replacement. The real
renderer test loads matrix `0000` cell `(3,27)` for the `lakep.1` water
timeline, cell `(27,5)` for the cross-format `sea` prefix transfer, and cell
`(6,20)` for `rhana`, then requires the
bound surface texture and controller switch count to advance with zero asset
failures. It also proves the catalog's `nhana` image hash remains unbound
because that texture is static in the original table.

## Streaming Smoke Test

Use a real OpenGL renderer so renderer cleanup is exercised:

```powershell
& "D:\path\to\Godot_v4.7-stable_win64_console.exe" `
  --path .\new-game-project `
  --audio-driver Dummy `
  --rendering-method gl_compatibility `
  --rendering-driver opengl3 `
  --script res://tests/world_streamer_smoke_test.gd
```

The test verifies:

- Explicit matrix `0000` startup independent of developer ProjectSettings.
- 468 manifest cells.
- Destination manifest schema `4` and 176 map-ID collision assets.
- Lazy Base64 collision decode with zero failures and retention independent of
  rendered `PackedScene` resources.
- A known real `a.dat` collision bit blocks its cardinal step.
- BDHC height sampling drives spawn, slopes, and the target Y of every step.
- Initial `3 x 3` chunk load.
- Dawn's ignored local walk/run atlas is loaded.
- Diagonal input resolves to one cardinal axis.
- A 16-pixel source tile maps to one world unit.
- Player positions stay on half-integer tile centers without the prior 8-pixel offset.
- The 32-pixel source sprite projects within one pixel of its native height at
  orthographic size `11.24` on the 192-pixel viewport.
- Platinum's 30 Hz walk/run actions map to 16/8 Godot physics ticks per tile.
- A stationary direction change uses six ticks and does not move the player.
- Walking and running preserve the 32-tick `neutral, foot A, neutral, foot B`
  gait timeline in atlas banks `0..3` and `4..7` respectively.
- Direction and `Z` changes during a step take effect only at the next tile.
- Held input starts walking immediately after a stationary turn; continuous
  walking changes direction without inserting another turn.
- Held movement chains cells without drift; teleports clear unfinished actions.
- The orthographic camera follows at distance `16`.
- The camera starts orthographic at size `11.24`.
- `F1` switches to distance-8, FOV-75 perspective and restores distance 16 at
  the unchanged test target and pitch.
- Default camera yaw `0`, downward pitch `50`, and wheel pitch steps of `5`.
- Mouse-wheel pitch changes preserve the follow distance.
- Correct floor-based cell boundaries.
- Long-distance load and origin unload.
- Zero failed assets and zero runtime material replacements.
- Loaded assets do not exceed the current retention set.

## Debug Destination Smoke Test

```powershell
& "D:\path\to\Godot_v4.7-stable_win64_console.exe" `
  --path .\new-game-project `
  --audio-driver Dummy `
  --rendering-method gl_compatibility `
  --rendering-driver opengl3 `
  --script res://tests/debug_destination_test.gd

& "D:\path\to\Godot_v4.7-stable_win64_console.exe" `
  --path .\new-game-project `
  --audio-driver Dummy `
  --rendering-method gl_compatibility `
  --rendering-driver opengl3 `
  --script res://tests/debug_destination_test.gd -- `
  --matrix=49 --area=4 --tile=7,9 --expect-runtime-cli
```

The focused test covers the explicit pre-tree API priority, command-line
selection, automatic catalog default cells, AreaData variant selection,
small-matrix chunk counts, and BDHC-aware tile-centered player placement. The
integration case verifies an absolute BDHC height independently of nonzero
matrix altitude; the synthetic coordinate test covers cross-cell height
selection and capture offsets.

## Runtime Debug Jump Test

```powershell
& "D:\path\to\Godot_v4.7-stable_win64_console.exe" `
  --path .\new-game-project `
  --audio-driver Dummy `
  --rendering-method gl_compatibility `
  --rendering-driver opengl3 `
  --script res://tests/runtime_debug_jump_test.gd -- `
  --capture-panel=res://captures/runtime_debug_jump_panel.png
```

The test injects `F2`, checks modal focus and paused movement, rejects an
ambiguous matrix `0049` request without reloading, then performs a real scene
reload to AreaData `61`, cell `(1,1)`, tile `(31,31)`. It verifies one-shot
request consumption, one live streamer, four loaded chunks, zero failed
assets, and the expected tile-centered player position. The optional panel
capture must be a nonblank native `256 x 192` image with no clipped controls.

## Render Capture

```powershell
& "D:\path\to\Godot_v4.7-stable_win64_console.exe" `
  --path .\new-game-project `
  --audio-driver Dummy `
  --rendering-method gl_compatibility `
  --rendering-driver opengl3 `
  --script res://tests/render_world_capture.gd -- `
  --cell=3,27 --output=res://captures/world_player_orthographic.png

& "D:\path\to\Godot_v4.7-stable_win64_console.exe" `
  --path .\new-game-project `
  --audio-driver Dummy `
  --rendering-method gl_compatibility `
  --rendering-driver opengl3 `
  --script res://tests/render_world_capture.gd -- `
  --matrix=49 --area=61 --tile=31,31 `
  --output=res://captures/matrix_0049_area_0061.png

& "D:\path\to\Godot_v4.7-stable_win64_console.exe" `
  --path .\new-game-project `
  --audio-driver Dummy `
  --rendering-method gl_compatibility `
  --rendering-driver opengl3 `
  --script res://tests/render_world_capture.gd -- `
  --cell=5,26 --offset=-4,-2 `
  --output=res://captures/building_regression_orthographic.png

& "D:\path\to\Godot_v4.7-stable_win64_console.exe" `
  --path .\new-game-project `
  --audio-driver Dummy `
  --rendering-method gl_compatibility `
  --rendering-driver opengl3 `
  --script res://tests/render_world_capture.gd -- `
  --cell=3,27 --output=res://captures/world_player_perspective.png --perspective
```

Inspect the image for nonblank output, terrain seams, incorrect axes, building
placement, player visibility, sprite transparency, nearest filtering, and
overlapping geometry. Small destinations are ready when their selected focus
chunk is loaded; they are not required to contain nine cells. The building
regression capture must show complete blue foreground roofs without V-shaped
camera-plane cuts. All PNGs must be exactly `256 x 192` pixels, and the
reported projection and camera distance must match the requested mode.

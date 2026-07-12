# HD-2D Visuals

## Target

MaiZang Engine uses an HD-2D Lite direction: native `256 x 192` pixel output,
nearest-filtered Platinum textures and sprites, stable orthographic rendering,
and restrained 3D depth cues. The Compatibility renderer remains the default.
Physical depth of field, volumetric fog, SSR, SSIL, and CompositorEffects are
outside this profile because Compatibility does not provide them.

## Visual Profiles

`Main/VisualProfile` owns environment, sun, camera-render stability, and the
player ground shadow. It never changes player simulation, streaming ownership,
GLB meshes, or shared `ArrayMesh` materials.

| Setting | Classic | HD2D preview |
|---|---:|---:|
| Orthographic pixel snap | Off | On |
| Player ground shadow | Hidden | Visible |
| Player texel size | 0.06 | 11.24 / 192 |
| Camera far | 2500 | 256 |
| Depth fog begin/end | No visible fog | 20 / 48 |
| Fog blend | 0.0001 | 0.22 |
| Dynamic sun shadows | Existing setting | Off until material classification |

Classic keeps the fog shader warm with a blend of `0.0001`. This is visually
identical to the previous fog-disabled baseline, but avoids a Godot 4.7 GLES3
shader leak when F2 disables a compiled fog variant. A decoded `256 x 192`
comparison must remain exactly zero changed pixels.

The project starts in Classic until the complete HD2D validation gates pass.
Use `F2` to switch profiles at runtime. The command line override is:

```text
-- --visual-profile=classic
-- --visual-profile=hd2d
```

`F1` remains the orthographic/perspective debug projection switch and does not
change the visual profile.

## Pixel Stability

HD2D orthographic rendering snaps only the camera-local right/up screen plane.
The grid step is:

```text
world units per output pixel = camera size / viewport height
                             = 11.24 / 192
                             = 0.0585416667
```

The view-depth coordinate is preserved. Each screen-plane correction is at
most half one output pixel, and Classic recalculates the exact unsnapped camera
transform when restored.

Moving only the camera made the billboard land at a fractional output-pixel
phase and visibly distorted some sprite columns. HD2D therefore sets each
source texel to exactly `11.24 / 192` world units and applies the same snap
offset to the Sprite3D render anchor. The physical player transform remains
untouched, while the 32-pixel source canvas stays exactly 32 output pixels and
at the same camera-relative center as Classic.

The player ground shadow is a prebuilt `12 x 6` `GradientTexture2D` on a
horizontal quad. It uses an unshaded nearest-filtered StandardMaterial, follows
the player's ground origin, and does not cast a shadow itself. It is prebuilt so
profile toggles allocate no nodes, meshes, materials, or shader resources.

## Capture and Metrics

`render_world_capture.gd` accepts:

```text
--visual-profile=classic|hd2d
--warmup-frames=<count>
--measure-frames=<count>
--metrics-output=res://captures/<name>.metrics.json
```

Performance measurement completes before PNG readback so synchronous GPU image
access does not pollute the samples. Reports include process, physics, render
CPU/GPU, frame setup, visible draw calls, objects, primitives, and streamer
state. Capture and report paths are restricted to the ignored
`res://captures/` tree.

Canonical locations are the start area `(3, 27)` and the foreground-building
regression at `(5, 26)` with offset `(-4, -2)`.

## Semantic Material Pilot

All 511 imported materials retain Platinum's unshaded material model. HD2D
lighting is implemented as separate external resources, so Classic never
changes the imported GLB materials or the shared base-material pool.

The local ignored profile at
`assets/platinum/hd2d/p3_city.profile.json` maps `(cell, asset key, material
key)` to the `lit_vertex` semantic variant. The tracked example profile contains
only placeholder keys. `generate_hd2d_p3_seed_profile.gd` deterministically
rebuilds the real seed from the manifest and catalog before
`configure_hd2d_material_variants.ps1` creates the local resources. The wrapper
proves that all 511 base-material SHA-256 hashes remain unchanged.

The first pilot is cell `(3, 27)`:

| Pilot metric | Count |
|---|---:|
| Shared `lit_vertex` variants | 8 |
| Terrain/building asset instances | 9 |
| Per-instance surface bindings | 22 |

The seed generator derives the instance and binding counts from the target cell
and GLB primitives, rejects legacy-shadow aliases, and may add only materials
classified as `ordinary_lit`. It cannot override water, foliage, emissive,
legacy-shadow, or ambiguous policy decisions.

Variants use per-vertex StandardMaterial lighting and reuse the original
nearest-filtered textures. The streamer prepares bindings only after base
material sharing, captures the exact Classic override, and switches with
`MeshInstance3D.set_surface_override_material()`. It never mutates an
`ArrayMesh`, duplicates a mesh, or keeps strong references to unloaded chunk
nodes. F2 therefore changes `0 -> 22 -> 0` active overrides without changing
the player, camera, chunk nodes, Mesh RIDs, or base-material RIDs.

The pilot keeps legacy `tshadow` and `h_kage` surfaces and leaves water and
foliage unshaded. Its `legacy_only` policy disables dynamic casting while HD2D
is active and restores the original setting in Classic, preventing duplicate
shadows. After leaving `(3, 27)`, registered bindings return to zero while the
bounded eight-resource variant cache remains available for a future return.

The pilot remains the explicit ordinary-lighting seed. The world profile below
adds conservative semantic handling without turning every unshaded surface into
a lit material.

## World Semantic Profile

`generate_hd2d_semantic_profile.gd` now derives a local ignored
`world_semantics.profile.json` from the manifest, global material catalog, and
every GLB JSON chunk. Classification uses normalized material aliases, the
actual material-to-image relationship, alpha mode, and emissive factor. Hashes
remain only in the generated ignored profile.

The rules form an exact, non-overlapping partition:

| Semantic | Materials | GLB surfaces | P4a behavior |
|---|---:|---:|---|
| Legacy shadow | 7 | 278 | Keep base; use `legacy_only` cast policy |
| Water | 32 | 287 | Keep static nearest-filtered base |
| Alpha foliage | 23 | 469 | Keep base transparency, cutoff, and culling |
| Emissive | 16 | 124 | Shared `emissive_window` variant |
| Ordinary | 432 | 2070 | Keep base unless explicitly seeded by P3 |
| Ambiguous | 1 | 21 | `manual_review`; never auto-modify |
| **Total** | **511** | **3249** | Exact catalog and primitive coverage |

Foliage classification requires a non-opaque alpha mode, preventing grass
ground tiles from being treated as cutout tree cards. Emissive classification
uses exact light/lamp tokens or a nonzero GLB emissive factor; image-only names
such as a generic `neon` atlas do not automatically light an unrelated
`lambert` surface. A material with multiple semantic signals is quarantined as
ambiguous.

P4a deliberately keeps water and foliage static and unshaded. It introduces no
`TIME` shader, UV scrolling, wind deformation, screen texture, refraction, or
glow pass. This preserves native nearest texels and stable alpha edges at
`256 x 192`. Dedicated emissive surfaces use per-vertex lighting plus their
original texture as a low-energy (`0.25`) additive emission mask.

The world profile contains 22 immutable variants: 6 retained P3 `lit_vertex`
resources and 16 `emissive_window` resources. Another 63 unique semantic
materials are explicitly preserved. The generator prunes stale variant files,
and validation rejects any count drift or uncovered surface.

P4b water animation remains optional. It can proceed only after individual
water surfaces are confirmed tileable and can move by whole source texels at a
low fixed cadence without changing buildings, foliage, or the player.

## Player Pixel Integrity

The local player atlas is `272 x 136`: 32 frames in an `8 x 4` layout, each
stored in a `34 x 34` cell around the original `32 x 32` sprite canvas. HD2D
maps one source texel to one orthographic screen pixel and moves the Sprite3D
anchor by the same camera snap offset, preventing the comparison image on the
right from squeezing a column when the camera rounds to its pixel grid.

The renderer regression draws every frame into a transparent `34 x 34`
SubViewport and requires an exact alpha-mask match. Directional world captures
can be produced with `--facing`; down, up, left, and right each remain stable for
16 frames at the canonical cell.

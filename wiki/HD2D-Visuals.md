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

## Material Roadmap

All 511 imported materials currently use Platinum's unshaded material model.
The profile infrastructure therefore establishes fog, pixel stability, and
player grounding first; it does not pretend that the world has full lighting.

The next phase generates external material variants alongside the existing
shared base materials. A local ignored profile maps `(asset key, material key)`
to semantic variants such as `lit_vertex`, while tracked tools and schemas stay
free of ROM-derived material keys. The streamer will apply shared variants with
per-instance surface overrides after base-material sharing. It must never call
`ArrayMesh.surface_set_material()`.

The first pilot is cell `(3, 27)`. It keeps legacy `tshadow` and `h_kage`
surfaces, leaves water and foliage unshaded, and disables dynamic casting on
pilot instances to prevent double shadows. Only after the pilot passes visual,
streaming, material, and lifecycle tests can coverage expand.

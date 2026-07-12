# Runtime Streaming

## Active Regions

The default streamer settings are:

| Setting | Value |
|---|---:|
| Active load radius | 1 cell (`3 x 3`) |
| Asset prefetch radius | 2 cells (`5 x 5`) |
| Chunk and asset retention radius | 3 cells |
| Stream refresh interval | 0.12 seconds |

Only cells present in the selected destination manifest are considered. A
small indoor matrix can therefore load fewer than nine chunks without being
treated as incomplete.

## Matrix Destinations

`assets/platinum/matrix_catalog.json` separates source matrix IDs from
runnable destinations. Most matrices have one destination. Matrices `0049`
and `0052` expose one destination per linked AreaData because the original
game chooses their environment through the entry MapHeader.

The streamer loads one destination manifest per process start. Terrain and
building paths remain relative to that manifest, so destination caches stay
isolated while external materials are shared globally. The debug selector does
not hot-swap an active streamer; this keeps outstanding threaded requests from
one matrix from crossing into another matrix lifecycle.

## Debug Destination

Project settings provide the default debug destination:

```text
maizang/debug/matrix_id
maizang/debug/area_data_id
maizang/debug/matrix_cell
maizang/debug/map_tile
```

Command-line user arguments override those settings:

```text
--matrix=0049 --area=61 --cell=0,0 --tile=16,16
```

`cell` is a matrix-block coordinate. `tile` is a `0..31` coordinate inside
that block. If a command-line matrix is selected without `--cell`, the catalog
default cell is used. AreaData may be omitted only when the matrix has one
destination. The spawn point is centered on the selected one-world-unit tile,
and its Y coordinate includes the manifest cell altitude.

Tests can call `configure_debug_destination()` before the streamer enters the
scene tree. Explicit test configuration takes precedence over command-line and
ProjectSettings values.

## In-Game Debug Jump

`F2` opens a compact destination panel over the native `256 x 192` viewport.
The panel pauses the active scene tree and accepts a matrix, optional AreaData,
catalog-default or explicit matrix cell, and an in-cell tile. `Enter` submits;
`Escape` or `F2` closes the panel and restores the prior pause state.

Submission uses the same catalog and manifest resolver as startup. Invalid,
ambiguous, unresolved, out-of-range, or unoccupied destinations remain in the
panel with a focused validation error. A valid selection is normalized into a
one-shot process-local request and reloads `main.tscn`. The new streamer
consumes and removes that request before it starts any threaded loads. This is
a complete streamer lifecycle boundary rather than an in-place world swap, so
old chunk nodes and strong `PackedScene` references are released first. The
panel never writes ProjectSettings or `project.godot`.

## Resource Lifecycle

1. A player-cell change computes active, prefetch, and retention regions.
2. Top-level `PackedScene` requests use `ResourceLoader.load_threaded_request`.
3. Sub-threaded loading stays disabled because it leaked renderer resources in
   Godot 4.7 during repeated command-line test shutdowns.
4. A chunk is instantiated only when all terrain and building scenes are ready.
5. Chunks outside radius 3 are queued for deletion.
6. Loaded `PackedScene` records outside radius 3 are removed so long-distance
   traversal does not accumulate the entire world in memory.

External texture and material resources remain shared through Godot's resource
cache. Static building nodes are currently ordinary scene instances. Repeated
buildings can move to per-chunk `MultiMeshInstance3D` only after profiling
shows draw-call pressure.

## Camera

The camera follows `Player` directly, while the streamer independently uses
the same player node as its focus:

- Fixed front orientation at yaw `0`.
- Default downward pitch `50` degrees.
- Default orthographic projection with size `11.24`, using the requested closer
  player and building composition at the native 192-pixel viewport height.
- `F1` toggles a perspective debug projection at FOV `75`.
- Orthographic follow distance `16`; perspective debug distance `8`.
- The longer orthographic distance keeps the reproduced city foreground roofs
  ahead of the camera plane without changing orthographic scale or composition.
- Target height `0.9` world units.
- Mouse wheel pitch steps of `5` degrees, clamped from `35` to `80` degrees.
- Pitch changes preserve the active distance. Projection toggles move only along
  the view ray and restore distance `16` at the current target and pitch.

Player movement and animation rules are documented in [Player Control](Player-Control).

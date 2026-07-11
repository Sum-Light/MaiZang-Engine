# Runtime Streaming

## Active Regions

The default streamer settings are:

| Setting | Value |
|---|---:|
| Active load radius | 1 cell (`3 x 3`) |
| Asset prefetch radius | 2 cells (`5 x 5`) |
| Chunk and asset retention radius | 3 cells |
| Stream refresh interval | 0.12 seconds |

Only cells present in the matrix manifest are considered. Small indoor maps
can later use whole-matrix loading instead of this overworld strategy.

## Resource Lifecycle

1. A focus-cell change computes active, prefetch, and retention regions.
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

The current viewer uses a free camera:

- Default orientation: front-facing yaw `0` with a `60` degree downward pitch.
- `WASD`: horizontal movement.
- `Q/E`: descend or ascend.
- Right mouse drag: look.
- Mouse wheel: adjust pitch in `5` degree steps.
- `Shift`: sprint.

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
- Default downward pitch `60` degrees.
- Default orthographic projection with size `8`.
- `F1` toggles a perspective debug projection at FOV `75`.
- Follow distance `8` world units and target height `0.9`.
- Mouse wheel pitch steps of `5` degrees, clamped from `35` to `80` degrees.
- Pitch and projection changes preserve the camera transform and follow distance.

Player movement and animation rules are documented in [Player Control](Player-Control).

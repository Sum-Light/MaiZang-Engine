# Runtime Streaming

## Active Regions

The default streamer settings are:

| Setting | Value |
|---|---:|
| Active load radius | 1 cell (`3 x 3`) |
| Asset prefetch radius | 2 cells (`5 x 5`) |
| Chunk and asset retention radius | 3 cells |
| Decoded collision retention radius | 3 cells |
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
isolated while external materials are shared globally. Manifest schema 4 also
contains the packed tile-attribute and BDHC collision assets plus Header-scoped
Warp events and MapProp animation descriptors for that destination. The debug
selector does not hot-swap an active streamer; this
keeps outstanding threaded requests and collision data from one matrix from
crossing into another matrix lifecycle.

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
destination. The default matrix `0000` tile is `(16,16)`. The spawn point is
centered on the selected one-world-unit tile, and its Y coordinate is resolved
from BDHC as an absolute field height. Matrix altitude is not added to that
height.

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

## Warp Transitions

Static ordinary Warp events are indexed once by `(Header ID, world tile)`.
When `a.dat` reports a transition behavior, the player emits a strict special
action; `PlatinumWarpController` resolves the source Warp, locks input, plays a
registered door-open animation when present, fades out, and queues a separate
one-shot world-transition request before reloading `main.tscn`. The new
streamer consumes that request and preserves destination Header, Warp, facing,
cell, and tile context. It fades in before playing the target door-close
animation and then releases input.

Warp lookup uses the same transition origin as collision resolution. A
directional or automatic transition owned by the current tile selects that
tile; otherwise lookup uses the adjacent tile being entered, even when the
current tile also contains a Warp event. This keeps adjacent door pairs from
incorrectly resolving back through the tile the player is leaving.
The direction table follows Platinum's tile behaviors: east/west/south
entrances and Warps (`0x62/0x63/0x65`, `0x6C/0x6D/0x6F`) require the matching
movement direction, while north entrance/Warp behaviors (`0x64`, `0x6E`) are
automatic current-tile transitions.

Header context is attached to the arrival cell so matrices reused by multiple
MapHeaders do not immediately fall back to the cell's default Header. Crossing
into another matrix cell adopts that cell's Header. Script-mutated Warps,
Turnback Cave state, special returns, missing targets, and unresolved
destinations fail closed. NPC/object events are not loaded by this system.

An arrival placed directly on automatic transition behavior `0x67` or `0x6E`
receives a scoped one-step escape: only that current-tile transition is ignored
while the player remains on the arrival tile, and all target-tile collision and
special behavior still applies. The exception clears after leaving the tile.
Arrival door-close playback waits for the initial chunks to settle; asset-load
failure or shutdown settles the wait as failed, skips the unavailable door
animation, and still completes fade/input release instead of trapping control.

## Resource Lifecycle

1. A player-cell change computes active, prefetch, and retention regions.
2. `PlatinumCollisionMap` decodes collision records for the radius-3 retention
   region and prunes decoded records outside it.
3. Top-level `PackedScene` requests use `ResourceLoader.load_threaded_request`.
4. Sub-threaded loading stays disabled because it leaked renderer resources in
   Godot 4.7 during repeated command-line test shutdowns.
5. A chunk is instantiated only when all terrain and building scenes are ready.
6. Animated MapProps register a stable destination/cell/building ID with one
   central 30 Hz controller; doors also enter a fixed tile index.
7. Terrain and building surfaces whose base texture hash has a `fldtanime`
   binding register with a separate central 30 Hz texture controller.
8. Chunks outside radius 3 explicitly unregister both animation ID sets before deletion.
9. Loaded `PackedScene` records outside radius 3 are removed so long-distance
   traversal does not accumulate the entire world in memory.

External texture and material resources remain shared through Godot's resource
cache. Collision source records and decoded arrays are owned by the independent
`PlatinumCollisionMap` `Resource`, not by `Chunk_*` nodes or the visual
`PackedScene` cache. Unloading a visual chunk therefore cannot remove collision
needed for a neighboring step; a pruned collision record can also be decoded
again on demand. A complete scene reload clears both source and decoded
collision state.

Static building nodes are ordinary visual scene instances. Their blocking
footprints come from the cell's terrain attributes rather than generated
physics meshes. Repeated buildings can move to per-chunk
`MultiMeshInstance3D` only after profiling shows draw-call pressure without
changing collision ownership.

MapProp interaction lookup also belongs to `PlatinumCollisionMap`. During
manifest configuration, every prop anchor is indexed by its global world tile
and retains both `owner_cell` and `world_position`. Lookup is O(1) and is not
restricted to the owner cell, which covers center-origin prop positions that
land in an adjacent matrix cell.

MapProp animation does not scan the scene tree per frame. Registration resolves
the imported `AnimationPlayer` once and stores weak instance references. The
controller advances loaded automatic NSBCA loops at the source 30 Hz phase and
runs door one-shots on demand. Chunk unload restores player state and drops all
animation/door indices. JSON numeric fields are normalized once at registration
only when they are finite exact integers; fractional or malformed descriptors
fail closed. Unsupported NSBTA/NSBTP descriptors remain inert.

Field texture animation does not mutate imported materials or shared
`ArrayMesh` resources. During the existing one-time material traversal for a
new chunk, the streamer resolves a binding from the base texture's content-hash
filename. The controller creates one runtime `StandardMaterial3D` duplicate per
binding and original material identity, shares it through surface overrides,
and keeps weak surface ownership plus explicit chunk unregister records.
Distinct alpha or unlit material signatures therefore never collapse together.

Frame textures use top-level `ResourceLoader.load_threaded_request` with
sub-threaded loading disabled and are requested only while at least one bound
surface is active. One global physics clock advances the Platinum 30 Hz
timeline; no surface owns a timer or `_process`, and the controller never scans
the scene tree. The imported static base remains visible for the first source
hold, then the controller changes only `albedo_texture` when the selected frame
actually changes. Removing the last surface restores its previous override and
drops runtime material and frame references.

Scene reload does not block on an in-flight frame request. `clear()` transfers
unfinished paths to a process-local handoff set; the next controller adopts a
matching request or drains it at terminal state before dropping the resource.
Warp and F2 reloads therefore neither wait for all animation frames nor abandon
threaded-loader ownership with the old scene.

## Collision Queries

Each exported `a.dat` terrain-attribute record is a row-major little-endian
`u16`. Bit 15 (`0x8000`) is static collision and the low byte is the complete
walking behavior input. A step result has a `disposition` of `allow`, `blocked`,
or `special`, plus `action`, `target`, `landing_target`, and `next_context`.
Normal allowed steps use `action = none`; hard failures have no landing target;
special results name the missing or deferred movement capability and remain
blocked until an executor handles them.

Special behavior is evaluated before bit 15. A directional ledge approached
correctly returns `jump` or `jump_two` and a BDHC-resolved landing two tiles
away; the wrong direction is blocked. Sea, water, and waterfall behaviors
return `requires_surf`. Static ordinary transitions and Warps are handed to
the Warp controller; ice or other forced movement,
dynamic mechanisms, Rock Climb, bicycle ramps and bridges, and explicitly
unsupported walking behaviors all return named `special` actions and fail
closed. If no special behavior applies, bit 15, directional barriers from both
sides, and the BDHC height threshold decide the normal step. Missing cells,
malformed assets, absent BDHC plates, and unavailable attributes also fail
closed.

BDHC exported from `h.bhc` is queried in its center-origin coordinate system and
returns an absolute world Y. Overlapping plates choose the height closest to the
caller's reference height. Player movement validates the destination tile
center before starting; a height difference of at least `1.25` world units
blocks the step. During an accepted step the height is sampled again every
physics tick so slopes remain attached to their source plane.

Walking queries also carry `bridge_layer` as `unknown`, `ground`, or
`elevated`. Bridge entry and exit behaviors update the returned `next_context`;
only a completed allowed step commits it. This prevents an elevated crossing
from being interpreted as water below, while an unknown or ground-level water
bridge still reports `requires_surf`. A player placed directly on an inner
bridge tile without a trusted layer receives `requires_bridge_context`; the
runtime does not infer `elevated` from behavior `0x71`. Normal movement also
requires a stable provider for the whole atomic action, and the final per-tick
BDHC sample remains authoritative when the step commits. Provider identity is
rechecked after every collision callback; synchronous replacement from inside
a preflight or height query fails closed before another collision world can be
used. The preflight receives a deep context snapshot, so a rejected provider
cannot mutate the player's active bridge layer through Dictionary aliasing.

Visual placement remains separate from collision coordinates. A `Chunk_*` root
sits at the matrix cell's top-left X/Z with Y zero. Its terrain child is offset
by `(16, matrix_altitude * 0.5, 16)`, while its `Buildings` child is offset by
`(16, 0, 16)` because MapProp Y is already absolute.

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

# Player Control

## Scene Contract

`main.tscn` owns a `CharacterBody3D` named `Player`. Its child `Sprite3D` is
unshaded, nearest-filtered, alpha-cut, and billboarded toward the camera. A
capsule shape preflights any existing Godot physics body, while authoritative
static map collision is queried from the destination manifest.

The default runtime spawn is matrix cell `(3,27)`, tile `(16,16)`, centered at
world X/Z `(112.5,880.5)`. Its Y is resolved from BDHC and is `1.0` for the
default map. The scene's authored transform is only a bootstrap value before
`PlatinumWorldStreamer` applies the selected destination.

## Input and Motion

| Input | Behavior |
|---|---|
| `WASD` or arrow keys | Walk in one of four cardinal directions |
| `Z` held | Run while moving |
| Mouse wheel | Adjust follow-camera pitch by 5 degrees |
| `F1` | Toggle orthographic and perspective debug projections |

The character never moves diagonally. A fresh two-axis input selects the
vertical direction, an unchanged combination preserves the last accepted
direction, and changing one component selects that component. This reproduces
the directional input history used by Platinum instead of applying a fixed
axis preference every frame. Left wins simultaneous left/right input and up
wins simultaneous up/down input, matching the original key polling order.

Each source-map tile is `16` pixels, which becomes exactly `1.0` world unit
after the `1 / 16` import scale.

Tile centers use half-integer X/Z coordinates (`n + 0.5`). Matrix chunk origins
land on tile boundaries, so centering the player removes the prior 8-pixel
half-tile offset.

Platinum runs its field logic at `30 Hz`; this project runs Godot physics at
`60 Hz`, so each original action update maps to two physics ticks. Movement
uses the resulting atomic grid actions:

| Action | Platinum 30 Hz updates | Godot 60 Hz ticks | Distance per Godot tick |
|---|---:|---:|---:|
| Walk one tile | 8 | 16 | 0.0625 world units |
| Run one tile (`Z`) | 4 | 8 | 0.125 world units |
| Turn while stationary | 3 | 6 | 0 |

Direction and run state are latched when a step begins. Releasing the key or
changing direction never leaves the player between cells; new input is sampled
at the next grid boundary. A direction held through the six-tick stationary
turn starts moving immediately afterward. A direction change between
continuous walk steps does not add another stationary turn. `teleport_to_grid()`
cancels any unfinished action and snaps external warps to the same one-unit X/Z
grid.

Before a step begins, the controller asks the streamer's independent
`PlatinumCollisionMap` to resolve the destination. Every result reports a
`disposition` (`allow`, `blocked`, or `special`), an `action`, and a
`landing_target`. The controller currently begins a normal grid step only for
`allow`; both other dispositions remain fail-closed.

The query applies these rules in order:

1. Both current and destination tiles must have collision data.
2. Current and destination low-byte behaviors are classified before bit 15.
   A correctly approached ledge returns `jump` or `jump_two` with a
   BDHC-resolved landing two tiles away.
3. Behaviors requiring Surf, transitions or warps, forced ice movement,
   dynamic mechanisms, Rock Climb, or a bicycle return `special` and remain
   blocked until those action executors exist.
4. If no special behavior applies, destination `a.dat` bit 15 (`0x8000`) must
   be clear and directional behavior must permit both exit and entry.
5. The destination `h.bhc` BDHC height must exist and differ from the current
   height by less than `20` source units (`1.25` world units).
6. The capsule must pass the existing Godot physics preflight.

Rejected input stops before movement and keeps the player on the original grid
center. Missing or malformed collision data also blocks the step. A dedicated
wall-bump animation is not implemented yet.

For an accepted step, X/Z still follow the fixed 16-tick walk or 8-tick run
timeline. BDHC is sampled again on every physics tick using the current Y as
the reference, so slopes and overlapping bridge levels remain continuous. If
height sampling or a physics move fails during the action, the atomic step is
cancelled back to its origin.

The player carries a collision context across completed steps. Its
`bridge_layer` is `unknown`, `ground`, or `elevated`, allowing the walking layer
to distinguish an upper bridge crossing from water at the same X/Z position.
The candidate `next_context` is committed only when the step reaches its target;
blocked, special, or cancelled steps cannot change the active layer.

BDHC heights are absolute field heights. Matrix altitude is used to place the
terrain visual and is never added to the player height. Static buildings and
other MapProps likewise do not create generic collision boxes: their blocking
footprints are encoded in the cell terrain attributes, while their manifest
records retain visual placement and interaction-anchor data. Those anchors are
indexed by global world tile during collision-map configuration, so an O(1)
query can find a MapProp whose anchor lies outside its owner matrix cell.

## Animation Atlas

The ignored local atlas is `272 x 136` pixels with `34 x 34` padded cells. Each
cell contains the original `32 x 32` visible sprite:

```text
columns 0-3: walking
columns 4-7: running
rows 0-3: down, up, left, right
```

Both banks follow the four-pose source loop `neutral, foot A, neutral, foot B`.
Columns `0` and `2` are identical walking neutral poses; columns `4` and `6`
are identical running neutral poses. Each pose lasts eight Godot physics ticks
(four Platinum field updates), making the complete gait cycle 32 ticks.

A 16-tick walk step advances half the cycle, so successive tiles alternate
feet. An 8-tick run step advances one pose, so four running tiles traverse
columns `4, 5, 6, 7`. Direction changes reset the gait phase. Walk/run
transitions align to a valid source pose, and stopping a run preserves the
source's short handoff before returning to the walking neutral pose. The
six-tick stationary turn uses walking columns `0, 1, 1, 2, 2, 2`. Idle keeps
the last facing direction.

The atlas is generated by `tools/import_player_sprite.ps1` and is never
committed to the public repository; a visible procedural fallback is used when
the local atlas is absent.

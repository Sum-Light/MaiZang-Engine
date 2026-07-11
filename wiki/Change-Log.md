# Change Log

## 2026-07-12 - Match orthographic camera scale

- Set the default orthographic size to 12.3 so the player appears at nearly the same scale as the FOV-75 perspective debug view.


## 2026-07-12 - Add orthographic camera debug toggle

- Start the player-follow camera in size-8 orthographic mode and let F1 toggle a transform-preserving FOV-75 perspective debug view.


## 2026-07-12 - Add playable Dawn character

- Add cardinal walking, Z-key running animations, a player-follow camera, local sprite-atlas import tooling, and focused runtime validation.


## 2026-07-12 - Set front-facing 60-degree camera

- Use a zero-yaw 60-degree downward default view and map mouse-wheel input to 5-degree pitch steps instead of movement speed.


## 2026-07-12 - Use native NDS screen resolution

- Set the Godot window, viewport, and render-capture contract to a fixed 256 by 192 single-screen layout.


## 2026-07-12 - Remove obsolete remote branches

- Deleted 17 superseded codex branches and documented master as the only long-lived project branch.


## 2026-07-12 - Handle initialized GitHub Wiki remotes

- Reset the disposable Wiki worktree to the initialized remote before publishing versioned pages.


## 2026-07-12 - Replace repository with the DSPRE-to-Godot pipeline

- Replaced the prior repository worktree with the current MaiZang Engine project.
- Added the matrix `0000` export, material dedupe, Godot import, and sync tools.
- Added streamed terrain and building placement with bounded asset retention.
- Added shared-material, streaming, and render-capture validation.
- Added a versioned Wiki, Codex Skill, repository hooks, and SSH-authenticated GitHub Wiki sync flow.
- Kept proprietary Pokemon and ROM-derived assets outside the public repository.

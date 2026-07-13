# Change Log

## 2026-07-14 - Add battle P1 protocol and command contracts

- Add fail-closed decision, request, step-input, command, batch, and step-result envelopes with typed construction failures and stable protocol diagnostics.
- Keep request number, battle progress, and command sequence independent; bind canonical catalog/action/view hashes, valid empty batches, and validated result field combinations without coupling the world runtime.
- Reject mutable copy aliases and post-seal mutation, add independent payload/empty/full-batch golden hashes plus 151 adversarial Godot assertions, and bind the slice to clean source evidence in a verified work item.

## 2026-07-14 - Establish battle P1 foundation contracts

- Add twelve isolated foundation types covering nine independent contract versions, stable IDs, diagnostic errors, and explicit operation/value results.
- Add checked signed-64 arithmetic, six centralized rounding modes, canonical fixed ratios, deterministic big-endian bytes, sticky atomic writer failure, and SHA-256 known-answer coverage.
- Add worktree/staged layer scanning to the battle commit gate, focused adversarial and 164-vector tests, and a quantified P1/mainline progress baseline without coupling the world runtime.

## 2026-07-14 - Complete battle P0 asset and generation gates

- Add a staged/index content gate that permits only reviewed battle source/contract paths and rejects local/generated data, production manifests, disguised catalogs, raw text/data/binaries, media, archives, absolute paths, and oversized JSON.
- Add a record-free project-owned synthetic generation manifest while making Production read only the ignored local licensed-source manifest and fail with a stable error when authorization is absent.
- Verify all four battle-local ignore roots, template emptiness, staged gate integration, Synthetic success, Production fail-closed behavior, and current repository/worktree asset safety; mark P0 complete and P1 next.

## 2026-07-14 - Seal battle P0 source audit baseline

- Seal the two source revisions, dirty-path sets, all 7,372 source hashes, input index counts/hashes, and scanner hashes without copying source payloads or machine-local paths.
- Generate an ignored canonical 6,559-entry disposition manifest covering every module, Section, handler, enum family, schema declaration, test, script candidate, and logic edge, with dirty and unverified evidence blocked from release.
- Add exact no-fallback module policy, a tracked reproducible audit seal, real source/schema/test evidence, and a full rebuild/strict-validation/tamper regression test.

## 2026-07-14 - Freeze battle P0 manifest contracts

- Freeze the independent battle module's target data generation, rule version, local modes/actions, source-use classes, network deferrals, and text-only presentation scope behind exact compatibility hashes.
- Add strict scope, licensed-source, source-audit, and implementation-work-item schemas plus empty public templates that cannot authorize production data.
- Add a battle-local strict JSON parser, fail-closed production license gate, real contract/evidence hash validation, and focused rejection tests without importing source data or coupling the world runtime.

## 2026-07-13 - Add isolated battle quick start

- Establish `new-game-project/battle/` as the only battle business root, with nested local-data and generated-artifact ignores.
- Add a Godot 4.7 Inspector tool button that validates and launches only the independent Q0 text smoke shell, without changing the existing project or world runtime.
- Add scene, native-resolution render, dependency-boundary, Git-scope, forced-local-data, and untracked-path validation plus Battle Wiki and Skill ownership memory.

## 2026-07-13 - Harden collision state and matrix publication

- Make normal player movement require a complete stable collision provider, strictly typed booleans, an explicit `allow`/`none` result and context, a finite adjacent target, and finite per-tick BDHC samples; reject or roll back when that provider disappears or is replaced before, during, or between its callbacks.
- Preserve the final sampled BDHC height, accept explicit teleport bridge context, clear stale context outside bridge tiles, and fail closed with `requires_bridge_context` instead of guessing that an unknown inner bridge tile is elevated.
- Validate every unselected raw, dedupe, and Godot-sync destination before a partial matrix export can mutate output; withdraw both published catalogs before destination changes and republish them only after stable-input validation succeeds.
- Reject recursive deletion through junctions or other reparse points in raw export, material dedupe, and Godot sync, with synthetic marker, mutation-order, and external-sentinel regression coverage.
- Bind schema-2 dedupe and sync markers to their current tool hashes and exact path/length/SHA-256 file records; validate exact downstream GLB, PNG, and material sets while excluding only editor-generated `.import` sidecars from the Godot destination post-check.
- Recheck all seven inputs after catalog aggregation and publish both catalogs through temporary files, withdrawing both on a controlled half-publication failure; validate generated roots before creation, catalog access, or publication.
- Bind raw reuse to exact path/length/SHA-256 file records; direct batch export now reuses only a wholly current destination and otherwise rebuilds its complete output and work slice instead of re-certifying individual old GLBs.
- Reject reparse points inside every recursively deleted, fingerprinted, or writable work tree without following them; constrain raw/work output roots and preserve external sentinels during nested-junction rejection.
- Remove obsolete matrix-shaped stage directories only after all three output trees pass complete safety preflight, revalidate all 278 raw/dedupe/sync marker identities before publication, and leave exact full-tree hashing to stage consumption/reuse and complete validation instead of repeating it after every successful child stage.
- Remove repeated whole-work-tree probes from each terrain model write; recursive deletion still rejects every reparse point, and each write still validates its exact ancestor path.
- Reuse the sync stage's exact file records for material-image verification and destination counts, avoiding a second PNG hash pass and redundant tree enumeration.
- Ignore only Godot's stable `.import` sidecars and transient `.import~*.TMP` atomic-write files when validating imported destinations, while keeping every managed asset and other extra file exact.
- Reject ancestor junctions and malformed schema-1 material catalogs before validation or publication, including non-object signatures, empty or unknown GLB bindings, and non-positive unique output counts.
- Decompress imported texture-image copies before shared-material pixel comparison, avoiding Godot compressed-format conversion failures during full catalog rebuilds.

## 2026-07-13 - Add Platinum terrain collision and height queries

- Export each map's exact `a.dat` terrain attributes and packed `BDHC` height data into every AreaData-aware destination manifest, with source hashes, map-level deduplication, completion markers, and catalog-wide contract validation.
- Preserve exact MapProp FX32 scale while defining static building footprints through the cell terrain attributes instead of generating mesh colliders that would block roofs, arches, and other walkable geometry.
- Add an independent, retention-bounded `PlatinumCollisionMap` resource that lazily decodes packed bytes, resolves row-major tile collision across matrix-cell boundaries, samples the nearest BDHC plate, and indexes MapProp anchors by global tile even when their visual owner cell unloads.
- Classify walking behavior as allowed, blocked, or special; preserve Surf, ledge landing, Warp, forced movement, dynamic-feature, climbing, and bicycle actions while failing closed until their gameplay states exist, and carry bridge-layer context across accepted player steps.
- Preflight each cardinal player step against terrain attributes and the 1.25-world-unit height threshold, then sample slopes on every physics tick while retaining `CharacterBody3D` collision for later dynamic bodies.
- Correct terrain/building center-origin placement, start matrix `0000` on open tile `(16,16)`, and add synthetic, real-manifest, player-integration, streaming, and full-catalog validation coverage.

## 2026-07-13 - Add in-game debug destination jumps

- Add an `F2` modal for selecting a matrix, AreaData variant, optional matrix cell, and in-cell tile while the game is running.
- Preflight requests through the shared catalog/manifest resolver, pause the active world while editing, and keep invalid or ambiguous selections in the panel with focused errors.
- Carry valid jumps through a one-shot `SceneTree` request and full scene reload so the old streamer's chunks and strong resource references are released before the new destination loads.
- Add a real OpenGL reload test and native `256 x 192` panel capture covering input isolation, multi-Area rejection, exact placement, and single-consumption behavior.

## 2026-07-12 - Export the multi-matrix catalog

- Inventory all 289 DSPRE matrix records and export 276 strict-ready matrices through 278 AreaData-aware destinations, including both linked variants of matrices `0049` and `0052`.
- Catalog 1,153 occupied cells, 3,041 building instances, 2,042 destination-scoped GLBs, 1,722 unique texture keys, and 1,804 unique material keys.
- Resolve unreferenced matrices only through duplicate-map or unique Nitro texture/palette evidence, and keep 13 ambiguous or inconsistent source records out of the runnable catalog.
- Add manifest-hash-bound resumable all-matrix export, per-destination dedupe and sync, strict catalog/path validation, and catalog-wide Godot material and texture configuration.
- Validate catalog-to-GLB material bindings and raw material content exactly, prune stale shared resources, preserve zero-texture destinations, and retry only sidecars whose external mappings are lost during editor import races.
- Add ProjectSettings, command-line, and test APIs for starting directly at a selected matrix, AreaData variant, cell, and in-cell tile.

## 2026-07-12 - Add grid movement and fix foreground clipping

- Center the player on half-integer tile coordinates and move one 16-pixel tile per atomic action, mapping Platinum's 30 Hz walk/run timing to 16/8 Godot physics ticks.
- Reproduce source-style six-tick stationary turns, grid-boundary direction/Z sampling, historical diagonal priority, and the continuous four-pose walk/run gait timeline.
- Move the orthographic camera to distance 16 while retaining distance 8 for perspective debug mode, preventing foreground roofs from crossing the camera plane.
- Repair render-capture argument parsing and add cell offsets for reproducible building regression captures.

## 2026-07-12 - Set 50-degree camera composition

- Set the default camera pitch to 50 degrees and use the requested orthographic size of 11.24 for a closer player and building composition.

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

---
name: maizang-engine-godot
description: Maintain the local MaiZang Engine Godot 4.7 project and its DSPRE-to-GLB Pokemon Platinum overworld pipeline. Use when working in D:/MaiZangEngine or Sum-Light/MaiZang-Engine, including DSPRE export and material dedupe scripts, Godot chunk streaming, building placement, asset import, validation, project Wiki updates, and Git/GitHub synchronization.
---

# MaiZang Engine Godot

## Start Every Task

1. Work from `D:\MaiZangEngine` unless the user provides another clone.
2. Read `AGENTS.md`, `wiki/Current-State.md`, and the relevant Wiki page.
3. Read `references/project-state.md` for the generated baseline.
4. Read `references/project-map.md` when changing architecture or ownership.
5. Read `references/workflow.md` when exporting assets, validating, or committing.
6. Run `git status --short --branch` before editing and preserve unrelated work.

## Engineering Rules

- Keep source conversion offline. Godot consumes generated GLBs, textures,
  materials, and manifests rather than parsing Nitro formats at runtime.
- Preserve the coordinate contract: cell size 32, altitude step 0.5, model
  scale `1 / 16`, and floor-based world-to-cell conversion.
- Keep the overworld streamed. Do not place the full matrix in one `.tscn`.
- Use top-level threaded loads with sub-threading disabled. Release distant
  `PackedScene` references as well as scene nodes.
- Share materials through external `.tres` resources or per-instance surface
  overrides. Never mutate a shared `ArrayMesh` at runtime.
- Keep ROM-derived data under ignored local paths. Never add proprietary GLB,
  PNG, map, text, audio, or DSPRE output to the public repository.

## Required Change Loop

For every functional change:

1. Implement the smallest coherent change.
2. Add or update focused validation.
3. Update the relevant page under `wiki/`.
4. Add a concise entry to `wiki/Change-Log.md`.
5. Refresh both Wiki and Skill state:

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\update_project_memory.ps1 -Stage
   ```

6. Run validation appropriate to the change.
7. Commit one completed change. Prefer `tools/commit_project_change.ps1`, which
   also pushes the branch and synchronizes the GitHub Wiki.

The pre-commit hook enforces the Change Log and asset boundary. Do not bypass it
unless the user explicitly requests a recovery operation.

## Validation Selection

- Documentation or Skill changes: run `tools/validate_repository.ps1`.
- PowerShell pipeline changes: parse all scripts and run the affected stage on
  a bounded sample before a full rebuild.
- Import/material changes: run the 398-asset shared-material validator.
- Streaming/runtime changes: run the real OpenGL smoke test.
- Visual changes: render desktop and representative captures, then inspect them.
- Broad pipeline changes: run `tools/validate_repository.ps1 -Full`.

## Git and Wiki

The main repository preserves published history. Do not force-push by default.
Treat `wiki/` as the Wiki source of truth and `.wiki-sync/` as disposable.
The repository Skill is canonical; the personal Codex Skill path must be a
junction created by `tools/setup_repository.ps1`.

Before finishing a task, verify:

- Git status contains only intended changes.
- Required Wiki and Skill state files are updated.
- No generated or proprietary path is staged.
- Tests completed without background Godot processes.
- The remote branch and GitHub Wiki are synchronized when a push was requested.

## References

- `references/project-map.md`: ownership, paths, constants, and local dependencies.
- `references/workflow.md`: exact asset, validation, documentation, and Git flow.
- `references/project-state.md`: generated current state; refresh every commit.

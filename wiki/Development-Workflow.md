# Development Workflow

## Before Editing

1. Read `AGENTS.md`.
2. Read `.codex/skills/maizang-engine-godot/SKILL.md`.
3. Read `wiki/Current-State.md` and the relevant topic page.
4. Run `git status --short --branch` and preserve unrelated work.

## During a Change

- Keep converter, manifest, and runtime ownership boundaries explicit.
- Preserve local generated assets unless the task is an intentional rebuild.
- Add focused validation for changed behavior.
- Update the relevant Wiki page while the implementation context is fresh.
- Add one concise entry to `wiki/Change-Log.md`.

For a complete local matrix refresh, use the catalog orchestrator instead of
looping the single-matrix tools manually:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tools\dspre_export_all_matrices.ps1 `
  -DspreContents "D:\path\to\game_DSPRE_contents" `
  -ApiculaPath "D:\path\to\apicula.exe" `
  -GodotPath "D:\path\to\Godot_v4.7-stable_win64_console.exe"
```

The command is resumable, preserves unresolved source records in the catalog,
and performs one initial Godot import plus one configured reimport. Resume
checks are content-bound: dedupe and sync completion markers must match their
upstream manifest hashes. Do not replace unresolved AreaData with a guessed
texture set in the normal pipeline.

## Before Commit

Refresh generated project memory:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\update_project_memory.ps1 -Stage
```

Use the project commit wrapper for normal changes:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\commit_project_change.ps1 `
  -Message "Add bounded terrain collision cache" `
  -Summary "Retain collision data only for streamed cells and cover cross-cell movement."
```

The wrapper updates the change log and project memory, commits, pushes the
current branch, and synchronizes `wiki/` to the GitHub Wiki.

Plain `git commit` remains available, but the pre-commit hook requires a staged
Wiki change for every functional commit and always refreshes the Skill state.

## Initial Setup After Clone

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\setup_repository.ps1
```

This configures the versioned Git hooks and installs the repository Skill into
the current user's Codex Skill directory through a directory junction.

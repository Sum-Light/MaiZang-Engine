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

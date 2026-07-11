# Repository Policy

## Public Source Boundary

`Sum-Light/MaiZang-Engine` is public. Commit only original project code,
automation, tests, documentation, and schemas.

Do not commit:

- Nintendo, Game Freak, Pokemon, or third-party ROM content.
- DSPRE unpacked project data.
- Exported GLB models or PNG textures.
- Reconstructed maps, building placements, text, audio, or animations.
- Generated Godot imports derived from those assets.

The root `.gitignore`, nested Godot `.gitignore`, and pre-commit hook enforce
the main path boundaries. This is an engineering guardrail, not a legal opinion.

## Remote History

The July 2026 repository replacement preserves the earlier Git history and
adds a new commit that deletes the previous worktree and introduces this
DSPRE-to-Godot pipeline. A bare mirror captured before replacement is stored
locally at:

```text
D:\MaiZangEngine-backups\20260712-main-before-replacement.git
```

Do not force-push or rewrite published history unless the repository owner
explicitly requests it.

## Wiki Source of Truth

The main repository's `wiki/` directory is authoritative. GitHub Wiki is a
published mirror. Always edit and commit `wiki/` first, then run the Wiki sync
tool.

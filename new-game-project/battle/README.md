# MaiZang Battle Module

`res://battle/` is the single owner of battle code, scenes, tests, tools,
schemas, fixtures, generated reports, and local battle data. Removing this
directory must leave the existing MaiZang world runtime unchanged.

## Current Status

Q0 provides only an editor quick-start surface and a synthetic text smoke
shell. P0 is in progress: the target data generation, ruleset/mode/action
scope, source-use classes, network deferrals, text-only policy, strict manifest
schemas, production license gate, and complete initial source-audit baseline
are frozen and tested. The module still does not contain a catalog,
`BattleEngine`, playable battle, world integration, network stack, model,
texture, animation, audio, or battle camera.

Open `res://battle/quick_start/battle_quick_start.tscn`, select its root node,
and use the `Quick Start Text Battle` Inspector tool button. The button only
starts `res://battle/scenes/battle_text_console.tscn`.

## Dependency Boundary

Allowed dependencies:

- Godot 4.7 standard APIs.
- Other files below `res://battle/`, following the documented inward
  dependency direction.
- Explicitly injected future catalog and application ports.

Forbidden dependencies:

- Existing MaiZang runtime scripts, scenes, tests, nodes, groups, signals,
  input actions, autoloads, or project settings.
- `main.tscn`, the world streamer, collision, player, camera, and debug
  destination modules.
- Runtime discovery through `get_tree().root`, `NodePath`, groups, or a global
  signal bus.
- Network transports and presentation assets during the current single-player
  text implementation.

Q0 is project-owned editor infrastructure. It does not close a gameplay
`ImplementationWorkItem` or claim source behavior coverage; P0 establishes the
evidence schemas before any battle behavior is implemented.

## Git Boundary

Review and stage battle business files with the battle pathspec:

```powershell
git status --short -- new-game-project/battle
git diff -- new-game-project/battle
git add -- new-game-project/battle
```

Repository-required Wiki and Skill memory files are the only permitted
attachments outside this directory. Validate the staged commit boundary with:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\new-game-project\battle\tools\check_battle_scope.ps1 `
  -Mode Staged
```

Add `-RunRepositoryValidator` to the staged audit when the root fast validator
should run in the same read-only gate.

Licensed inputs, normalized data, runtime catalogs, generated reports, and
temporary files remain ignored. Only schemas, reproducible tools, empty
templates, and wholly synthetic fixtures may be committed.

## P0 Manifest Gate

`manifests/battle_scope_manifest.json` is the tracked scope authority. The
licensed-source and source-audit template manifests contain no source records.
Validate them with:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\new-game-project\battle\tools\battle_catalog\validators\validate_p0_manifests.ps1
```

The strict parser rejects duplicate keys, non-integer numbers, nonstandard
literals, trailing commas, BOMs, unknown fields, stale evidence hashes, and
absolute or traversing paths. `-GenerationMode Production` fails with
`BATTLE_P0_LICENSED_SOURCE_REQUIRED` until an ignored, verified production
manifest is supplied; the public empty template is never accepted as
production authorization.

## P0 Source Audit

`manifests/source_audit/source_index_baseline.json` seals both source Git
revisions, dirty-path sets, source-file aggregates, scanner tools, and every
input index hash. `source_audit_policy.json` classifies each of the `183`
indexed modules exactly once; adding or removing a module fails instead of
falling through to a default rule.

Build the full local audit with:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\new-game-project\battle\tools\battle_catalog\importers\build_p0_source_audit.ps1
```

The ignored output contains `6,559` source-disposition entries: all Sections,
effect registrations, event/command/action/interrupt/protocol/mode enums,
schema declarations, tests, `2,555` logic edges, and `966` text candidates.
Two text candidates are documentation, so the executable scenario denominator
is `964`; both remain audited with `NOT_APPLICABLE` scenario disposition.
Dirty evidence is `BLOCKED_SOURCE`, Auction/Kodaigame and unverified binary
extensions are rejected, network-only entries are deferred to N0, and visual,
audio, model, camera, and command entries retain explicit presentation/text
dispositions. The tracked `source_audit_seal.json` contains only reproducible
hashes and counts, never source payloads or machine-local paths.

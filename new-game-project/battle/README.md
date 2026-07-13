# MaiZang Battle Module

`res://battle/` is the single owner of battle code, scenes, tests, tools,
schemas, fixtures, generated reports, and local battle data. Removing this
directory must leave the existing MaiZang world runtime unchanged.

## Current Status

Q0 and P0 are complete. P1 is in progress: its pure foundation and
protocol/command slices now define nine independent contract versions,
stable IDs and diagnostics, typed results, checked integer/fixed-ratio math,
canonical bytes and SHA-256, fail-closed step envelopes, ordered command
batches, a stable empty `BattleEngine`, local authority/session lifecycle,
and a staged dependency gate. The module still does not contain a catalog,
configured battle state, playable battle, world integration, network stack,
model, texture, animation, audio, or battle camera.

The final P1 slice adds the battle-local suite runner and optional repository
validation switch. It will not change the editor entry or connect the world.

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

## P0 Asset And Generation Gate

`tools/check_battle_assets.ps1` validates staged/index blobs rather than
trusting file extensions in the worktree. The scope checker invokes it for
every battle commit. P0 allows only the reviewed JSON contract paths and
public text/code types; local/generated paths, production manifests, unknown
JSON locations, non-empty public templates, catalog-like oversized JSON,
raw text/data/binaries, media, archives, and machine-local paths fail closed.

The tracked synthetic generation manifest is record-free, project-owned, and
test-only. Synthetic validation succeeds without licensed data. Production
validation reads only
`local_data/source/licensed_source_manifest.json`; it returns
`BATTLE_P0_LICENSED_SOURCE_REQUIRED` when the ignored local manifest is
missing, empty, a public template, or not explicitly production-authorized.

## P1 Foundation

`scripts/foundation/` contains one public `class_name` per file. Stable IDs
reserve zero and use the reviewed positive signed-32 range. Errors carry a
stable category/code plus mechanism, stage, source, target, and detail
diagnostics. Result objects always distinguish success from failure and never
use a false, zero, or empty payload as the error channel.

`BattleIntMath` checks signed-64 add, subtract, and multiply before mutation,
centralizes the six documented rounding modes, and rejects invalid
denominators or clamp ranges. `FixedRatio` reduces equivalent values and
canonicalizes zero to `0/1`. `CanonicalWriter` emits fixed big-endian
integers and bounded length-prefixed bytes, UTF-8 strings, and typed arrays.
Its first failure is sticky and `finish()` never exposes partial bytes.
`BattleHash` accepts only canonical bytes and produces a 32-byte SHA-256
digest.

`tools/check_battle_dependencies.ps1` reads either worktree files or staged
Git blobs. It enforces the documented layer direction and rejects Node,
SceneTree, UI, network, runtime resource loading, filesystem I/O, and
singleton lookup from the core directories. The battle scope gate invokes it
for every commit.

Run the focused foundation checks with:

```powershell
& "C:\path\to\Godot_v4.7-stable_win64_console.exe" --headless `
  --path .\new-game-project `
  --script res://battle/tests/foundation/p1_foundation_test.gd

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\new-game-project\battle\tests\foundation\p1_dependency_gate_test.ps1
```

## P1 Protocol And Command DTOs

`scripts/protocol/` owns immutable decision, request, step-input, and
step-result envelopes. `scripts/commands/` owns immutable command and batch
envelopes. The polymorphic payload, request, and command bases fail closed;
P8 and P16 will add their concrete gameplay variants without changing the P1
headers.

Request number, battle progress, and per-batch command sequence are distinct
axes. Published batches allow zero commands, require command sequence `1..N`,
and carry explicit catalog, source-action, audience, and before/after view
hash fields. The unpublished empty batch is a valid non-null sentinel for
failures before publication. Copies are canonical-equivalent snapshots;
self-aliasing subtype copies and post-seal mutation attempts are rejected.

`BattleStepResult` currently admits `COMPLETE`, `NEED_INPUT`, and `FAILED`
through validated factories. It is a sealed concrete envelope whose static
validator rejects forged subtypes and inconsistent fields. `BATTLE_ENDED` is
reserved until the later battle/outcome phases introduce the outcome
contract. Invalid field combinations normalize to a stable typed failure and
never use `null` as the error channel.

Run the focused protocol checks with:

```powershell
& "C:\path\to\Godot_v4.7-stable_win64_console.exe" --headless `
  --path .\new-game-project `
  --script res://battle/tests/protocol/p1_protocol_command_test.gd
```

The 151 checks include independent canonical/hash golden vectors, distinct
request/progress fields, ordered command hashes, empty and published batches,
typed mismatch errors, copy isolation, malicious self-alias rejection, and
the step-result truth table.

## P1 Empty Engine And Session

`BattleEngine.step()` is a synchronous RefCounted boundary with a guard that
remains active through result validation, canonical encoding, and copying.
The P1 engine has no placeholder setup, catalog, state, or outcome: `step(null)`
returns a repeatable `BATTLE_ENGINE_NOT_CONFIGURED` failure, a valid
unpublished empty batch, and independent golden authority/result hashes.
Non-null input without a pending request and calls after shutdown have their
own stable errors and do not mutate the empty state.

`LocalBattleAuthority` owns the engine reference, keeps its busy guard active
through synchronous signal publication, binds published results to its battle
ID, and validates every reply against the current copied request.
`BattleSession` is the only Node in this slice. It copies authority results
into a bounded FIFO and exposes an explicit `pump()` stable-batch entry. A
result callback may queue one valid reply, but that reply cannot call the
engine until a later pump; each pump submits at most one input.

Session start, pump, and authority-dispatch guards reject recursive start,
pump, close, duplicate reply, cross-battle result, forged terminal state, and
late terminal delivery without changing state. `close()` disconnects both
signal directions, clears results/inputs/pending requests, shuts down the
authority graph, and remains idempotent. `_exit_tree()` performs the same
cleanup when the scene is freed.

Run the focused lifecycle checks with:

```powershell
& "C:\path\to\Godot_v4.7-stable_win64_console.exe" --headless `
  --path .\new-game-project `
  --script res://battle/tests/application/p1_session_lifecycle_test.gd
```

The 282 checks include empty-state and full-result goldens, real `_step_impl`
and canonical-copy reentry, both signal listener orders during start, stable
FIFO injection, request gating, error category/code pairs, terminal exactly
once behavior, 100 advanced create/progress/close release graphs, and a real
SceneTree `queue_free()` release path.

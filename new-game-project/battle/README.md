# MaiZang Battle Module

`res://battle/` is the single owner of battle code, scenes, tests, tools,
schemas, fixtures, generated reports, and local battle data. Removing this
directory must leave the existing MaiZang world runtime unchanged.

## Current Status

Q0, P0, and P1 are complete. P2 is in progress (`10/16`). The pure foundation
and protocol/command contracts define nine independent contract versions,
stable IDs and diagnostics, typed results, checked integer/fixed-ratio math,
canonical bytes and SHA-256, fail-closed step envelopes, ordered command
batches, a stable empty `BattleEngine`, local authority/session lifecycle,
an isolated headless suite entry, and a staged dependency gate. The module
still does not contain a catalog, configured battle state, playable battle,
world integration, network stack, model, texture, animation, audio, or battle
camera.

The completed P2 slices establish append-only stable-ID/presentation
contracts, five strict spec schemas with validator-owned maturity, the
deterministic cross-file compiler, a bounded mechanism trace probe, a
non-runtime SourceEvidence/audit-disposition join, and a static release-target
reference-closure overlay. A
non-executable fixture-requirement preflight protects Todo 6 without claiming
it complete. The spec, fixture, and SourceEvidence authoring sets remain empty;
setup-bearing fixture compilation and coverage/orphan reports remain later
work. P2 does not change the editor entry or connect the world.

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
every battle commit. The gate allows only reviewed JSON contract paths and
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

## P1 Suite Runner

`tests/battle_suite_test.gd` is the battle-local SceneTree entry. It accepts
`all`, `p1_foundation`, `p1_protocol_command`, or
`p1_session_lifecycle`; no argument defaults to `all`. A single suite loads
its vectors directly. The aggregate runs the fixed three suites in isolated
headless child processes so GDScript test classes, signals, and references do
not cross suite boundaries. It requires exact success markers and check counts
of `164`, `151`, and `282`, for `597` total.

The runner exits `0` on success, `1` on assertion/count/load failure, and `2`
for invalid runner arguments. `tools/test_battle.ps1` preserves every child
exit code and supports individual suites, phase groups, or the default `All`
selection. Its default repository validation is `None`; `Fast` and `Full`
explicitly call the existing root validator without changing it. `Full` is
opt-in because the root validator may require local Platinum assets and
renderer-backed checks.

Run P1 in one command with:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\new-game-project\battle\tools\test_battle.ps1 `
  -GodotPath "C:\path\to\Godot_v4.7-stable_win64_console.exe" `
  -Suite P1
```

Use `-Suite P1Foundation`, `P1Protocol`, or `P1Session` for one Godot suite.
The default `All` also reruns Q0 and P0 battle checks and therefore retains
the explicit analysis/clean-source path parameters used by the P0 audit.
Add `-RepositoryValidation Fast` for the read-only root fast gate, or use
`Full` only when its local asset prerequisites are available.

The 64 runner-contract checks cover all P1 SceneTree selectors, exact counts,
success/assertion/usage exit codes, battle-only clean-cache execution without
Platinum assets, leak-free ordered aggregation, single-suite isolation,
missing-tool and non-Godot rejection, mandatory success markers, exact Godot
child-code propagation, duplicate-marker rejection at both aggregate layers,
the P2 trace selector/default-All ordering, and root `Full` argument plus
failure-code propagation. `-SourceRoot` is
forwarded to the P0 source-audit test when an explicit clean-source override
is needed. The verified work item records the clean source test-loop evidence
as structural context rather than a Godot CLI oracle.

## P2 Authoring Contracts

`specs/id_manifests/battle_stable_ids.json` owns the fixed 15-domain registry
for mechanism, scoped branch, event, handler, resolver, scoped phase, scoped
RNG draw, RNG stream/tag, state-op, command, action, interrupt, feature, and
test IDs. Zero is invalid, every allocated ID is a positive signed-32 integer,
and branch/draw/phase identities use their explicit owner scope. Authoring
order is historical: every scope owner must exist, an active scoped ID needs
an active owner, and existing entries cannot be deleted, reordered, reused, or
revived after tombstoning. A rename retains the prior key as an alias.

`specs/presentation/presentation_contracts.json` freezes the seven
`PRES_VISUAL` through `PRES_NONE` tags and separately owns append-only payload
schema and cue IDs. Cue tags are non-empty, `PRES_NONE` is exclusive, payloads
are restricted to bounded stable IDs/public integers/booleans, and active cues
must reference active tags and payload schemas. Cue records cannot contain
Node, Resource, Callable, asset-path, RNG, authority-state, or continuation
payloads.

The P2 validator reads strict UTF-8 JSON, checks exact properties and semantic
cross-references, emits independent canonical SHA-256 values, and compares
worktree or index candidates with `HEAD`. A semantic edit must advance the
manifest generation exactly once; unchanged content cannot advance it. The
scope gate invokes the same validator, including staged-blob validation, and
rejects an index/worktree split across the reviewed gate scripts and schemas.

`MechanismSpec`, `EventSchema`, `HandlerBinding`, `ResolverSpec`, and
`TestManifestEntry` each use one zero-padded ten-digit ID per file under their
dedicated `specs/` directory. Every root and nested object is closed, every
array is bounded, and authoring rejects floats, nulls, paths, expressions,
runtime objects, and `computed_status`. The current repository intentionally
contains no entries in these five directories.

Mechanisms separate stable identity from execution order. Typed input and
intermediate slots carry units, ranges, intermediate width, negative-value,
rounding, overflow, and divide-by-zero policy. One `execution_steps` plan
orders formula stages, repeatable event emissions, RNG draws, mutations, and
commands without reusing append-only IDs as positions. Events require a final
stable tie-break, explicit aggregation/short-circuit semantics, bounded recall,
rounding ownership, and trace policy. Handler RNG references, resolver phase
order/reentry/emission bounds, scenario fixture identity, and required test
oracles are checked locally; P2C closes their global ID/context/registry joins,
maturity-gated test requirements, and phase-local event ownership. Resolver
root `mechanism_ids` includes direct and indirect ownership; each phase is a
scheduled subset and need not make the root an exact phase union.

Authoring declares `target_maturity`; only the validator returns
`computed_status` through the continuous `DISCOVERED -> SPECIFIED ->
IMPLEMENTED -> VERIFIED -> RELEASED` gates. The current CLI can prove only
`DISCOVERED`; the P2C compiler promotes a mechanism to at most `SPECIFIED`
after every stable ID, scoped branch/draw/phase, cue, artifact, context,
capability, owner-qualified formula/event rounding link, resolver graph, and
test-coverage reference closes. Implementation
bindings, executed tests, evidence freshness, coverage, and release facts stay
false. Merely adding a handler or test file cannot promote maturity. All three
CLI views hash the complete five-set input deterministically; staged validation
reads captured index blobs and enforces the full reviewed execution surface.

`compile_p2_specs.ps1` emits an in-memory `COMPILED_SPEC_MANIFEST` index and a
compact `RUNTIME_RULE_CATALOG`. Primary tables sort by numeric stable ID;
resolver phases sort by `phase_order` then `phase_id`; semantic execution,
formula, RNG, event, mutation, and command arrays retain declaration order.
Canonical JSON uses ordinal object keys, strict UTF-8 without BOM, and exactly
one trailing LF. The runtime catalog is bound to the spec-manifest SHA-256 and
cannot represent paths, debug/owner metadata, evidence, tests, maturity,
timestamps, GUIDs, or runtime object instances.

The compiler performs no writes by default. All three views capture bounded
candidate bytes at construction: each file is at most 512 KiB, the candidate
path count is at most 65,535, and candidate plus baseline bytes are at most
64 MiB. Git blobs are size-checked before loading. No-follow handles verify
each final path beneath the captured root and hold artifact pairs against
write/delete races.

`-OutputDirectory` accepts only a child with an existing parent below the
system temp directory or the ignored `battle/generated/battle_specs/`
boundary. Staged mode also requires the indexed `.gitignore` to match the
worktree rule used by `git check-ignore`. The compiler creates both files with
exclusive new-file handles in a sibling staging directory and publishes them
with one directory rename. Output directories are immutable: an exact repeat
is idempotent and any different or incomplete pair is rejected. It never
deletes on failure; retained staging/output evidence is ignored and uses a new
GUID on retry. `-VerifyDirectory` compares both locked files byte-for-byte with
a fresh compile. The current empty five-set input
compiles to spec hash
`9f35401d489d6a0e55c2514fe8325850dc353c8b907f919fcd30dccfd6a87b57`
and runtime hash
`5d3971516b957d9f58986eba6d5b8e741dc8da8b609c234ffb8b7222e00b9d39`.

The separate P2D fixture-requirement preflight derives only `SCENARIO` test
identity, coverage targets, expected IDs, and required oracle kinds from the
already validated spec compilation. It re-hashes the canonical spec manifest,
authoring input set, and every test record before binding them, sorts
requirements by numeric `fixture_id`, and emits a closed manifest that never
enters the runtime catalog. The current empty requirement manifest hash is
`ab8ecfeb6a3c5ba0b1a7147ee06082b6cb174d6c9e95c917f034a74d1c836b59`.

P2 Todo 6 remains open. The fixture contract requires `CANONICAL_SETUP` to use
the production `BattleSetupValidator` and `LAUNCH_REQUEST` to use the
production `BattleSetupBuilder` plus that same validator; P7 owns those types.
Until then, any file below `fixtures/synthetic/scenarios/` fails with
`P2D_SETUP_COMPILER_UNAVAILABLE_P7`. This preflight does not accept a fixture
payload, create a setup DTO or digest, run a battle, or mark coverage as
observed or passed.

`MechanismTraceProbe` completes P2 Todo 7 and completion gate G03. Its six
documented observation methods remain `void`, so rule code cannot branch on a
trace result. The default constructor is a disabled null object that allocates
nothing, validates nothing, and never opens a scope. An explicitly enabled
probe allocates no trace-record capacity and accepts scenario scopes only when
`fixture_id == test_id`, unit scopes
only with fixture sentinel zero, and rejects branch, stage, RNG, or state-op
records outside a matching scope with `BATTLE_TRACE_SCOPE_REQUIRED`.

Enabled records use a preallocated 13-integer `PackedInt64Array` layout:
kind, sequence, test, fixture, mechanism, branch, stage, draw, stream, tag,
cursor-before, cursor-after, and opcode. Unused stable-ID fields are zero and
unused cursor fields are minus one. Stable IDs use the positive signed-32
contract; an RNG receipt requires nonnegative cursors with `after > before`.
Zero-consumption paths emit no RNG record. The bounded ring
returns chronological defensive snapshots. Overflow keeps the latest window,
increments `dropped_count`, and latches `BATTLE_TRACE_CAPACITY_EXCEEDED`, so an
incomplete window cannot be promoted as coverage evidence. `stage_id` is a
mechanism-local formula stage, never a resolver phase.

`specs/evidence/` now owns strict, ten-digit `SourceEvidence` authoring without
adding an evidence domain to the runtime stable-ID registry. Each ACTIVE record
selects exactly one sealed P0 `audit_id`, repeats its repository/category/path/
symbol/file hash and commit-or-tree revision, and carries sorted behavior claims
to exact `MechanismSpec` JSON Pointers. Claims use branch sentinel zero for a
mechanism-wide observation or a declared coverage branch. Evidence IDs and spec
back-references must close in both directions. History is append-only: new IDs
start at version 1 above the prior maximum, semantic edits advance one version,
and tombstones cannot be removed, changed, revived, or referenced.

The join verifies the tracked policy/baseline/seal chain. An empty evidence set
does not require the ignored 5.5 MB audit payload; a nonempty set reads only
`battle/generated/p0/source_audit_disposition_manifest.json` through a bounded
no-follow handle and requires its raw SHA-256 to equal the seal before indexing
it. Every selected audit ID is then re-derived from repository, category, path,
and symbol and all repeated identity fields must match. Unknown, forged, or
stale identity links fail compilation. Dirty, missing, stale-index, deferred,
rejected, insufficient-review, and insufficient-confidence evidence remains in
the deterministic join with sorted blockers so Todo 10 can report them and
Todo 11 can enforce the later release gate.

The closed `COMPILED_SOURCE_EVIDENCE_JOIN_MANIFEST` contains only stable IDs,
canonical hashes, currentness, and blocker codes. It excludes source paths,
symbols, observations, claims, source payloads, timestamps, GUIDs, runtime
objects, and machine paths, and never enters the runtime catalog. The current
empty evidence input hash is
`a07e6384acd2d662315e412856053b2c6b9404b0fc7083e262cefd8884572e33`;
the empty join hash is
`ac1277e109e28492a380656c8c39d783bfd464aca5251cd78d1edf30d99313fe`.
The 496-check focused suite also covers schema closure, history, exact audit
identity, bidirectional claim closure, JSON Pointer/branch failures, blocker
propagation, minimal output, and order-independent projection. Todo 8 is closed;
reports, stale-evidence release failure, and fixture execution remain open.

The P2F release-reference validator closes Todo 9 without weakening the
existing maturity gate. It selects the checked set only from validated
`MechanismSpec.target_maturity == RELEASED`; neither generated
`computed_status` nor work-item completion status can add or remove a mechanism.
For each selected mechanism, a Godot contract edge requires a validated
work-item `mechanism_ids` relation; `project_requirement_keys` keeps its
existing project-requirement meaning. P2F requires `GodotContractRoot` once the
release-target set is nonempty, then repeats the bounded no-follow
whole-document SHA-256 check and requires each mechanism-bound section to
exactly name a column-zero top-level ATX Markdown heading; the current empty
set remains portable. Historical unbound work-item section labels remain
descriptive. The
external evidence edge requires every
battlelogic/pokelib `SourceEvidence` identity declared by the mechanism to be
closed by the P2E join and exactly matched by a work-item source locator; a
partial match remains incomplete. A fixture edge requires a real
P2D `SCENARIO` requirement that covers the mechanism plus its work-item fixture
ID. Project decisions and work-item-only source or fixture claims cannot stand
in for the two generated joins.

The closed `COMPILED_RELEASE_MECHANISM_REFERENCE_MANIFEST` is a read-only,
non-runtime overlay. It contains stable IDs, canonical hashes, booleans, and
sorted blocker codes, but no contract path/section, source locator/observation,
fixture payload, timestamp, GUID, execution result, coverage result, or
`computed_status`. Noncurrent evidence remains a present reference with an
explicit blocker. A declared scenario reference can close the static triple,
while `SETUP_COMPILER_UNAVAILABLE_P7` remains explicit until the production
setup compiler exists. The diagnostic projection retains missing-leg details;
the public CLI and scope gate fail when any selected mechanism lacks the full
static triple, while noncurrent/P7 blockers do not masquerade as a missing leg.
The public validator returns only the closed manifest, canonical JSON/bytes/hash,
and summary counts; inspection-only compiler, raw evidence, fixture, and work-item
objects remain internal. Contract headings are accepted only at column zero and
outside fenced code and HTML blocks/comments; Setext and container headings are
intentionally unsupported so ambiguous Markdown cannot close a release edge.
Todo 10 generates traceability, coverage, and orphan
reports; Todo 11 owns later hard failures for stale evidence, unexecuted tests,
and coverage defects.

The public authoring sets contain no release-target mechanism, so the current
overlay is deterministically empty with hash
`bd30940a4c04452238c6f410df79da14a4755754ae5585a63c07fecd5de15439`.
The 181-check focused suite covers recursive schema closure, synthetic RELEASED-target
specs with complete static triples, target-only selection, each missing leg,
project-decision substitution, five-field identity mismatches, partial and
noncurrent evidence, mixed work-item review, evidence-only project requirements,
recomputed upstream joins/currentness, cross-artifact consistency failures,
minimal output, unchanged public maturity enforcement, CLI stability, and no
generated writes.

Run the focused checks with:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\new-game-project\battle\tests\specs\p2_id_presentation_contract_test.ps1

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\new-game-project\battle\tests\specs\p2_spec_contract_test.ps1

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\new-game-project\battle\tests\specs\p2_repository_view_test.ps1

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\new-game-project\battle\tests\specs\p2_spec_compiler_test.ps1

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\new-game-project\battle\tests\specs\p2_fixture_preflight_test.ps1

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\new-game-project\battle\tests\specs\p2_source_evidence_join_test.ps1

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\new-game-project\battle\tests\specs\p2_release_reference_test.ps1

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\new-game-project\battle\tools\test_battle.ps1 `
  -GodotPath "C:\path\to\Godot_v4.7-stable_win64_console.exe" `
  -Suite P2Trace

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\new-game-project\battle\tools\battle_specs\validators\validate_p2_id_manifests.ps1 `
  -Mode Repository

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\new-game-project\battle\tools\battle_specs\validators\validate_p2_spec_contracts.ps1 `
  -Mode Repository

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\new-game-project\battle\tools\battle_specs\compilers\compile_p2_specs.ps1 `
  -Mode Repository

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\new-game-project\battle\tools\battle_specs\compilers\compile_p2_fixture_requirements.ps1 `
  -Mode Repository

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\new-game-project\battle\tools\battle_specs\compilers\compile_p2_source_evidence_join.ps1 `
  -Mode Repository

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\new-game-project\battle\tools\battle_specs\compilers\validate_p2_release_references.ps1 `
  -Mode Repository
```

# Battle Development

## Isolation Boundary

All battle business code, scenes, tests, tools, fixtures, schemas, and local
artifacts live under `new-game-project/battle/` (`res://battle/`). The module
currently has no runtime reference to MaiZang's world streamer, collision,
player, camera, debug destination, main scene, project settings, autoloads, or
input map.

Repository-required Wiki and Skill memory updates are the only battle commit
attachments allowed outside that root. Licensed data, normalized data,
runtime catalogs, and generated reports remain ignored within the battle
directory.

## Implementation Status

| Phase | Status | Delivered behavior |
|---|---|---|
| Q0 | Complete | Inspector quick-start button, independent text smoke shell, nested asset ignores, scope gate, and scene/scope tests |
| P0 | Complete | Frozen scope/contracts, 6,559-entry source audit, staged asset gate, and explicit synthetic/production source boundary |
| P1 | In progress (7/17) | Foundation plus protocol/command envelopes are verified; empty engine, authority/session, and suite tooling remain |
| P2-P18 | Not started | Mechanism trace, data, engine, rules, AI, settlement, replay, and full text interaction |
| N0 | Deferred | Network admission work after the complete local implementation |

Q0 intentionally reports `Catalog: not implemented`, `Engine: not
implemented`, and `Battle: unavailable`. Its `SYNTHETIC_READY` bootstrap is a
development smoke state, not a playable battle or catalog completion claim.

## P0 Manifest Contracts

`res://battle/manifests/battle_scope_manifest.json` freezes scope ID
`MAIZANG_GEN9_SINGLE_PLAYER_TEXT_V1`, target data generation
`GENERATION_9_LICENSED_LOCAL_V1`, rule behavior version `1`, exact-hash
compatibility, required data domains, local ruleset/mode/action families,
network deferrals, and the text-only presentation boundary. Development does
not silently follow a newer data or source snapshot.

The tracked `LicensedSourceManifest` and `SourceAuditDispositionManifest`
templates contain zero source records. They are format examples, not data
authorization. Production validation fails with
`BATTLE_P0_LICENSED_SOURCE_REQUIRED` until an ignored local production
manifest contains at least one verified, hashed, count-bound source record.
Synthetic work remains allowed without substituting source-snapshot values.

Five JSON Schema draft 2020-12 contracts define the scope, licensed sources,
source-audit dispositions, and `ImplementationWorkItem`. The last contract
requires non-empty Godot contract and source evidence references; the local
validator resolves the referenced files and rejects stale hashes. Its
battle-local strict JSON parser rejects BOMs, duplicate keys, nonstandard
literals, floating-point P0 values, leading-zero integers, trailing commas,
unknown fields, absolute paths, and parent traversal.

The current external index still matches both dirty source worktrees byte for
byte. It has `966` battle-test text files, but two are build/readme documents;
the executable scripted-scenario denominator is `964`. P0 source-audit work
must retain the two documents in the test inventory while classifying them as
non-scenarios instead of silently claiming `966` executable fixtures.

## P0 Source Audit Baseline

The tracked source-index baseline seals both branch/commit/tree identities,
all `135` dirty paths, ordinal source aggregates for all `7,372` files, nine
input index hashes, and six scanner/validator tool hashes. A source payload or
dirty-path change blocks generation before an audit seal can be produced.

The exact module policy classifies all `183` modules once with no fallback:
non-network behavior/schema evidence remains in scope, host migration is
`DEFERRED_N0`, command/talk modules are `TEXT_ONLY`, presentation definitions
remain out of scope, and Auction, Kodaigame, runtime binaries, and unverified
root schema/data extensions are `REJECTED_UNVERIFIED`. Dirty evidence remains
`BLOCKED_SOURCE`; generated scope classification never promotes a mechanism to
implemented or released status.

The ignored canonical `SourceAuditDispositionManifest` contains `6,559`
entries and has SHA-256
`0e91976589d1eba3b9427ce893a63d5c2e670e1589530f95c8df3de1fe107593`.
It covers `257` Sections, `839` effect registrations, `246` events, `215`
commands, `16` actions, `10` interrupts, `83` protocol entries, `23` battle
modes, `102` schema declarations, `1,064` tests, `966` script-text candidates,
and `2,555` logic edges. The tracked seal contains only counts and hashes; the
5.5 MB entry manifest remains under ignored `res://battle/generated/p0/` and
contains no source payload or absolute path.

## P0 Asset And Generation Boundary

The content-level asset gate reads staged Git blobs and rejects local or
generated paths, blocked data/media/archive extensions, unknown JSON paths,
JSON over the P0 review limit, production manifests, non-empty public
templates, embedded records in the synthetic manifest, strict-JSON failures,
and machine-local absolute paths. It is called by the existing battle scope
gate, so a path-safe `.json` file cannot bypass the data boundary by name.

Repository and worktree scans cover every currently tracked/new battle file.
`git check-ignore` verifies source, normalized, runtime, and generated probes.
Only the two `.gdignore` sentinels may be tracked below local data. The 5.5 MB
source audit remains ignored and its tracked seal remains byte-identical.

The explicit synthetic generation manifest is project-owned, test-only, and
contains zero Pokemon/catalog records. Production mode never falls back to it
or to the public licensed-source template: only the ignored
`local_data/source/licensed_source_manifest.json` is accepted, and its absence
returns `BATTLE_P0_LICENSED_SOURCE_REQUIRED`. No production source currently
exists locally, so production catalog work remains correctly blocked for P4.

## P1 Foundation Contracts

The first P1 slice adds twelve public foundation types, each in its own
`class_name` file. `BattleContractVersions` freezes independent schema,
catalog, profile, handler, feature, snapshot, command, save, and fixture
versions at `1`. `BattleStableId` reserves `0` and accepts the explicit
positive signed-32 range; P2 remains responsible for domain manifests,
append-only IDs, and tombstones.

`BattleError` carries a stable category and string code plus mechanism,
stage, source, target, and detail diagnostics. Dedicated operation, integer,
byte, string, and fixed-ratio results keep the success bit, payload, and error
separate. A failed result cannot be confused with a valid false, zero, empty
string, or empty byte sequence.

`BattleIntMath` performs signed-64 overflow checks before add, subtract, or
multiply and owns all six specified rounding modes. Division requires a
positive denominator. `FixedRatio` rejects invalid denominators, reduces by
GCD, and canonicalizes every zero ratio to `0/1`. The synthetic vector suite
covers positive and negative ties, exact and non-exact division, signed
limits, overflow, reversed clamps, and ratio normalization.

`CanonicalWriter` uses fixed big-endian signed-64 integers, unsigned-32
length prefixes, UTF-8 strings, ordered typed arrays, and a one-mebibyte
sequence bound. It validates a whole field before appending, retains its first
error, seals once, and only returns bytes from a successful `finish()`.
`BattleHash` is limited to SHA-256 over those canonical bytes. Golden byte
vectors, standard empty/`abc` SHA-256 answers, repeat encoding, oversize
failure, result immutability, and sealed-writer behavior are covered by 164
Godot assertions.

The work item references clean source evidence for explicit IDs, fixed-point
helpers, typed result grouping, ordered binary writes, and schema field
typing. Those sources are not treated as behavioral oracles: their fixed
math uses float or unchecked multiplication with inconsistent tie behavior,
and their writer is unbounded native `memcpy` without a canonical byte
order. No source payload or licensed value is committed.

`check_battle_dependencies.ps1` validates either worktree scripts or exact
staged Git blobs. It maps public classes to layers, rejects outward
dependencies, and rejects Node/SceneTree, UI, networking, runtime `load()`,
filesystem I/O, and singleton discovery in foundation, catalog, domain,
engine, rules, and effects. The scope gate calls this check after its content
asset gate; synthetic tests prove valid inward dependencies and rejection of
Node, runtime load, outward foundation references, and unknown layers.

## P1 Protocol And Command Contracts

Eight additional public types establish the protocol boundary without adding
gameplay behavior. `BattleDecisionPayload`, `BattleInputRequest`, and
`BattleCommand` are fail-closed polymorphic bases. `BattleStepInput`,
`BattleCommandBatch`, and `BattleStepResult` are concrete immutable envelopes,
with dedicated typed build results for the two validated constructors.
Concrete decision variants remain P8 work; concrete state, message, control,
and presentation command payloads and codecs remain P16 work.

Request number, battle progress, and command sequence are encoded as separate
fields. Published batches may be empty but require every present command to
use the contiguous sequence `1..N`. They also bind the catalog version/hash,
optional accepted-action digest, audience, and before/after view hashes. A
valid unpublished empty batch is the non-null sentinel for failures produced
before a publishable transaction exists.

All constructors copy at the boundary and compare canonical bytes. A subtype
that returns itself from `copy_payload`, `copy_request`, or `copy_command` is
rejected, successful typed build results retain independent snapshots, and a
valid object cannot be reconfigured or invalidated after sealing.
`BattleStepResult` validates the `COMPLETE`, `NEED_INPUT`, and `FAILED` field
truth table; `BATTLE_ENDED` is reserved until the outcome contract lands in
the next P1 slice.

The focused Godot suite runs 151 assertions. It includes independent payload,
empty-batch, and full published-batch golden hashes; the full vector uses
request `17` and progress `3` so an axis swap cannot pass. It also covers
sequence gaps, oversize batches, hash-presence rules, mismatch-specific error
codes, deep-copy isolation, malicious subtype aliases, and deterministic
result copies. The verified work item binds six Godot documents and clean
source code/test hashes while recording that no sealed source test defines
the project's canonical encoding or typed error truth table.

## Quantified Progress

The local implementation mainline contains `465` checklist items across Q0
and P0-P18. The separately deferred N0 network phase and nine shared preamble
items are excluded from this denominator. Q0 is `23/23`, P0 is `22/22`,
and the currently verified P1 slice is `7/17`. Current mainline progress is
therefore `52/465` items (`11.2%`), with `2/20` phases complete and P1
active. This count advances only after a checklist item has implementation,
focused verification, Wiki/Skill memory, and a focused commit.

The protocol/command slice completes part of P1's already-counted public-type
contract item, so it intentionally does not increment the conservative
checklist numerator. The next count change requires closing one of the
remaining engine, session, suite, or completion-gate items in full.

## Editor Entry

Open `res://battle/quick_start/battle_quick_start.tscn`, select
`BattleQuickStart`, and use the `Quick Start Text Battle` Inspector button.
The `@tool` callback validates and starts only
`res://battle/scenes/battle_text_console.tscn`. It returns immediately outside
the editor and never changes the current edited scene, world pause state, or
project configuration.

The Q0 target accepts the explicit synthetic bootstrap while no catalog exists.
When a later phase selects catalog bootstrap, a missing or unready catalog is
an editor error and the target is not launched.

## Validation

```powershell
& "C:\path\to\Godot_v4.7-stable_win64_console.exe" `
  --headless --path .\new-game-project `
  --script res://battle/tests/q0_scene_smoke_test.gd

& "C:\path\to\Godot_v4.7-stable_win64_console.exe" `
  --path .\new-game-project --audio-driver Dummy `
  --rendering-method gl_compatibility --rendering-driver opengl3 `
  --script res://battle/tests/q0_console_render_test.gd

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\new-game-project\battle\tests\check_battle_scope_test.ps1

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\new-game-project\battle\tests\catalog\p0_manifest_contract_test.ps1

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\new-game-project\battle\tests\catalog\p0_source_audit_test.ps1

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\new-game-project\battle\tests\catalog\p0_asset_boundary_test.ps1

& "C:\path\to\Godot_v4.7-stable_win64_console.exe" `
  --headless --path .\new-game-project `
  --script res://battle/tests/foundation/p1_foundation_test.gd

& "C:\path\to\Godot_v4.7-stable_win64_console.exe" `
  --headless --path .\new-game-project `
  --script res://battle/tests/protocol/p1_protocol_command_test.gd

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\new-game-project\battle\tests\foundation\p1_dependency_gate_test.ps1

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\new-game-project\battle\tools\battle_catalog\importers\build_p0_source_audit.ps1

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\new-game-project\battle\tools\battle_catalog\validators\validate_p0_manifests.ps1 `
  -WorkItemPaths .\new-game-project\battle\manifests\work_items\P0_MANIFEST_CONTRACTS.json `
  -GodotContractRoot D:\PokemonSV-Battle-Architecture\docs\godot

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\new-game-project\battle\tools\check_battle_scope.ps1 `
  -Mode Staged -RunRepositoryValidator
```

The scene smoke test loads and instantiates both scenes, verifies the Inspector
Callable and tool-button hint, checks the fixed `256 x 192` status surface,
confirms the Exit control is local, and scans the two Q0 runtime scripts for
forbidden MaiZang dependencies. The scope test proves allowed governance files
pass while project runtime paths, forced local data/assets, symbolic-link Git
modes, and untracked root tools fail. The renderer test captures a nonblank
native-resolution frame and proves scene cleanup preserves the prior pause
state. The P0 contract test parses all battle-local PowerShell, exercises
strict JSON rejection cases, validates the frozen scope and empty public
templates, proves missing production authorization fails, and checks actual
contract/evidence hashes for a valid and stale work item. The source-audit
test re-hashes every current source payload, regenerates the canonical audit,
compares it with the reviewed seal, validates every disposition entry, and
proves an altered input-index hash fails closed.
The asset-boundary test scans tracked/worktree content, verifies all four
ignore roots, exercises disguised data and production-manifest rejection, and
proves Synthetic succeeds while missing/template Production fails.
The P1 foundation vector test executes 164 checks across version, ID, error,
result immutability, int64, rounding, ratio, canonical byte, writer failure,
and SHA-256 contracts. The dependency test runs the real worktree scan plus
adversarial worktree/staged fixtures; the existing scope test proves All mode
cannot hide a forbidden staged blob behind a clean worktree copy.
The P1 protocol/command test executes 151 checks across fail-closed base
types, canonical golden hashes, independent request/progress/sequence axes,
typed mismatch errors, empty/published batches, copy sealing, alias rejection,
and step-result field combinations.

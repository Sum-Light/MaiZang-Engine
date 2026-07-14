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
| P1 | Complete (17/17) | Foundation, protocol/command envelopes, empty engine, authority/session lifecycle, aggregate runner, and no-asset headless gate |
| P2 | In progress (8/16) | ID/presentation, strict authoring, deterministic spec compiler, fixture-requirement preflight, and mechanism trace scope enforcement; production setup compilation, coverage, and fixtures remain |
| P3-P18 | Not started | Data, engine, rules, AI, settlement, replay, and full text interaction |
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
truth table through a sealed concrete envelope and static validator that
rejects scripted subtypes. `BATTLE_ENDED` is reserved until the later
battle/outcome phases introduce the outcome contract.

The focused Godot suite runs 151 assertions. It includes independent payload,
empty-batch, and full published-batch golden hashes; the full vector uses
request `17` and progress `3` so an axis swap cannot pass. It also covers
sequence gaps, oversize batches, hash-presence rules, mismatch-specific error
codes, deep-copy isolation, malicious subtype aliases, and deterministic
result copies. The verified work item binds six Godot documents and clean
source code/test hashes while recording that no sealed source test defines
the project's canonical encoding or typed error truth table.

## P1 Empty Engine And Session Lifecycle

`BattleEngine.step()` is a synchronous RefCounted boundary whose guard remains
active through implementation dispatch, static result validation, canonical
encoding, and copying. P1 deliberately has no placeholder setup, catalog,
state, or outcome. An empty step returns the stable
`BATTLE_ENGINE_NOT_CONFIGURED` failure, a valid unpublished empty batch, and
independent golden authority/result hashes; unexpected input and post-shutdown
calls have separate stable failures without mutating empty state.

`LocalBattleAuthority` owns the engine graph, keeps its busy guard active
through synchronous result publication, binds every published result to the
battle ID, and validates a reply against the copied pending request.
`BattleSession` is the only Node in this slice. It copies authority results
into a bounded FIFO and exposes an explicit `pump()` stable-snapshot boundary.
A callback may queue one valid reply, but each pump submits at most one input
and callback input cannot reenter the engine until a later pump.

Start, pump, dispatch, and terminal guards reject recursive lifecycle calls,
duplicate replies, cross-battle results, forged result subtypes, and late
terminal delivery without corrupting state. `close()` disconnects both signal
directions, clears result/input/request references, shuts down the authority
graph, and stays idempotent even if authority shutdown reports a failure.
`_exit_tree()` applies the same cleanup when a scene-owned Session is freed.

The focused lifecycle suite runs 282 checks. It covers empty/full-result
goldens, implementation and canonical-copy reentry, both signal-listener
orders during start, stable FIFO injection, request and error contracts,
terminal exactly-once behavior, 100 advanced create/progress/close WeakRef
graphs, and a real SceneTree `queue_free()` release path. The verified work
item binds the contract to clean lifecycle and request/command source evidence
without treating the source's frame loop or intrusive pointers as a Godot
lifecycle oracle.

## P1 Suite Runner And Completion Gate

`res://battle/tests/battle_suite_test.gd` is the SceneTree aggregate entry.
It accepts `all`, `p1_foundation`, `p1_protocol_command`, and
`p1_session_lifecycle`, with no argument defaulting to `all`. Each selected
suite has a fixed expected count: `164`, `151`, or `282`; aggregate success
requires all `597`. The Session count includes the awaited 12-check real-tree
release probe in addition to its 270 synchronous vectors.

A single selection loads its vector script directly. Godot 4.7 retains cyclic
GDScript resources if all three inner-class vector scripts share one process,
so `all` launches the three fixed headless child selections in order and
checks each exit code, final marker, and exact count. This keeps test state and
references isolated and exits without the resource-leak diagnostics produced
by a multi-preload runner.

`res://battle/tools/test_battle.ps1` provides individual, phase, and default
`All` selections. The PowerShell `All` path runs the independent P2 mechanism
trace after the fixed 597-check P1 aggregate and before Q0/P0 checks; the Godot
P1 aggregate itself remains unchanged. The tool captures `$LASTEXITCODE`
immediately after every native
call and exits with the same nonzero code. `RepositoryValidation` defaults to
`None`; `Fast` and `Full` forward to the existing root validator, and `Full`
also forwards the selected Godot executable. The P0 audit receives explicit
`AnalysisRoot`, `SourceRoot`, and `GodotContractRoot` overrides. The tool never
modifies the root validator. Default battle checks omit the OpenGL Q0 render
test and root Full gate; opting into Full may require local Platinum assets.

The 64-check runner contract proves `0/1/2` Godot success/assertion/usage
semantics, ordered single/aggregate selectors, absence of success markers on
failure, leak-free exits, single-suite isolation, missing project/Godot
configuration errors, rejection of a non-Godot executable that returns zero,
mandatory unique success markers at the Godot aggregate and PowerShell
layers, fake-child code `37`, root Full code `41`, and exact Full arguments.
It also proves the real P2 trace selector/unique marker and its default-All
position, then performs a fresh headless script scan and all `597` P1 checks in a
temporary project containing only a minimal `project.godot`, battle scripts,
and battle tests. No Platinum assets, world scripts, renderer arguments, or
existing import cache are present. The verified work item binds the test-loop
shape to clean source evidence without treating that source as the CLI/process
oracle.

## P2 Stable ID And Presentation Contracts

The first two P2 checklist items are complete. The authoring registry fixes 15
domains in reviewed order: mechanism, mechanism-scoped branch, event, handler,
resolver, resolver-scoped phase, mechanism-scoped RNG draw, RNG stream/tag,
state-op, command, action, interrupt, feature, and test. Zero remains the
invalid sentinel and every allocatable value is a positive signed-32 integer.
The initial entries are intentionally empty: this slice establishes ownership
and history rules without inventing gameplay IDs or importing catalog values.

Each domain preserves authoring history rather than sorting changes before
validation. Existing `(scope_id, id)` entries cannot be deleted, inserted
ahead of history, reordered, replaced, reused from an old gap, or revived from
a tombstone. New IDs append above the prior maximum within their scope. A
debug-key rename retains the old key as an appended alias, and aliases cannot
be removed or reordered. This lets branch and RNG draw ID `1` legitimately
exist under different mechanism scopes while preventing accidental global-ID
semantics. Every scoped owner must exist in the mechanism or resolver domain;
an active scoped ID cannot remain below a tombstoned owner, while tombstoned
children retain their historical owner identity.

The separate presentation contract fixes IDs `1..7` as `PRES_VISUAL`,
`PRES_AUDIO`, `PRES_CAMERA`, `PRES_UI`, `PRES_TEXT`, `PRES_TIMING`, and
`PRES_NONE`. Payload schemas admit only bounded stable entity/effect/item/move/
message IDs, public signed integers, and booleans with explicit cardinality.
Cues require at least one active tag and an active payload schema;
`PRES_NONE` is exclusive. Their phase, information class, fallback text key,
and local-only barrier are authoring data, while Node, Resource, Callable,
asset paths, authority state, rule RNG, and continuation state have no field
in the contract.

The strict validator computes independent canonical SHA-256 values for the
stable-ID and presentation manifests. Repository mode validates explicit
authoring files; Worktree compares them with `HEAD`; Staged reads exact index
blobs and cannot be redirected to a clean worktree copy. A semantic change
must increment generation exactly once, while unchanged content cannot bump
generation. The scope gate invokes this check whenever either manifest exists
in the candidate or baseline, so deleting a registry cannot bypass it.
Staged validation also compares the reviewed gate scripts, schemas, and tests
with their index blobs, preventing a clean worktree tool from certifying a
different staged implementation.

The 75-check PowerShell suite covers schema headers, canonical repeatability,
scoped local-ID reuse, range/order/name collisions, valid append/tombstone/
rename transitions, every forbidden history mutation, the seven presentation
tags, payload field kinds and ordering, cue cross-references, `PRES_NONE`, and
presentation semantic immutability. Temporary Git repositories prove first
staged introduction, index/worktree isolation, semantic scope rejection,
core-manifest deletion rejection, and one-sided baseline rejection. The
verified work item uses a clean typed-ID/invalid-sentinel source only as
structural evidence; append-only history and cue semantics remain Godot
contracts and project decisions.

## P2 Strict Spec And Maturity Contracts

P2 checklist items three and four are complete. Five strict Draft 2020-12
schemas define `MechanismSpec`, `EventSchema`, `HandlerBinding`,
`ResolverSpec`, and `TestManifestEntry`. Future authoring uses exactly one
zero-padded ten-digit primary ID per file under `specs/mechanisms/`,
`specs/events/`, `specs/handlers/`, `specs/resolvers/`, or `specs/tests/`.
All roots and nested objects are closed, arrays are bounded, values are strict
UTF-8 integers/booleans/strings, and null, float, path, expression, runtime
object, unknown field, and authored `computed_status` values fail closed. The
five authoring sets remain intentionally empty in this slice.

Mechanism authoring separates append-only identity from behavior order.
Inputs and formula outputs have typed local slots; every formula declares
operand/result units, result range, 32/64-bit intermediate width, negative
handling, exact rounding point, clamp, overflow, divide-by-zero, parameter,
trace, and optional modifier-event semantics. A unified ordered plan places
formula stages, repeatable event emissions, RNG draws, state mutations, and
commands. Stable stage/draw/opcode IDs may be appended without forcing their
execution position. Local validation also closes branch/oracle requirements,
RNG sample/bounds/count combinations, mutation/command references, error
semantics, atomicity, and test obligations.

Event schemas require PascalCase typed contexts, narrow reads/writes,
aggregation and compatible short-circuit rules, a final `INSTANCE_ID ASC`
stable tie-break, bounded same-instance recall, explicit rounding ownership,
and trace policy. Handler bindings use registry keys rather than paths and
constrain queries, mutations, mechanisms, and scoped RNG draws. Resolver
phases use independent `phase_id` and `phase_order`, bounded reentry/nesting,
local emission and interruption phases, errors, termination, and covered
mechanisms. Resolver-level `mechanism_ids` owns direct and indirect links;
phase arrays are scheduled subsets and are not required to form an exact root
union. Scenario tests alone use `fixture_id == test_id` in P2B; all other
test kinds use zero until the P2 fixture compiler defines their later binding
contract.

`target_maturity` is authoring; `computed_status` is validator output only.
Promotion is continuous through `DISCOVERED`, `SPECIFIED`, `IMPLEMENTED`,
`VERIFIED`, and `RELEASED`, with deterministic blocker codes and a hard target
failure. The P2B CLI intentionally supplies only discovery facts: global
cross-references, implementation bindings, evidence joins, execution results,
and release gates belong to later P2 slices. A source/handler filename alone
cannot promote a mechanism. Repository and Worktree enumerate the complete
five authoring sets; Staged reads exact index blobs and first enforces P2A
review-surface parity. The current empty-set canonical input hash is
`32857c87d8e374886c91e9a65a2eed546478930d640d5ba4ecf006c18a1fa821`.

The 508-check PowerShell suite executes all five valid synthetic contracts,
recursive internal-schema references and nested closure, local semantic
contradictions, the complete maturity lattice, ID/order independence,
repeatable event emission, formula unit flow, runtime-type boundaries,
Repository/Worktree/Staged isolation, ACTIVE filename/debug identity, staged
review parity, read-only behavior, and Windows reparse rejection. The work
item binds clean Section, event-handler-table, and source-test evidence as
structural context without treating source code as a Godot schema oracle.

## P2 Deterministic Spec Compiler

P2 checklist item five and deterministic completion gate G01 are complete.
The compiler consumes one immutable Repository, Worktree, or Staged view and
validates the stable registry, presentation contracts, and all five authoring
sets exactly once. All modes capture the bounded candidate path set and bytes
when the view is constructed; Worktree and Staged also retain captured `HEAD`
baseline bytes for history checks. A file is limited to 512 KiB, a candidate
set to 65,535 paths, and candidate plus baseline storage to 64 MiB. Staged
checks each blob size before reading its exact OID. Git metadata is pathspec-
limited and output-bounded. No-follow handles reject reparse objects and any
final path that differs from the captured repository root plus lexical
relative path. The shared execution surface, including `battle/.gitignore`,
rejects untracked, deleted, nonregular, reparse, unmerged, or index/worktree-
split compiler inputs. Ordinal path enumeration is explicit on PowerShell 5.1.

Global compilation closes ACTIVE global and scoped IDs, required authoring
artifacts, presentation cues, mechanism/resolver/phase/subphase membership,
event and handler context/capability links, bidirectional owner-qualified
formula/event rounding, scoped RNG draws, mutation
services, command contracts, resolver emission/interruption/nesting graphs,
test branch/oracle/expected-ID ownership, maturity-gated distinct test cases,
and emission-phase event ownership. Handler, resolver, phase, event, and
mechanism back-references are bidirectional. Resolver cycles and missing
versioned ruleset providers fail closed. Diagnostics collect before failure
and sort by pass, artifact, primary ID, field, target scope/ID, code, and
detail. Successful closure promotes a mechanism only through requirements it
actually satisfies and never beyond `SPECIFIED`; implementation, dependency,
executed-test, coverage, evidence, and release facts remain false.

`spec_manifest.json` is a closed canonical index of artifact IDs, behavior/
schema versions, source hashes, and mechanism maturity, not a second copy of
authoring truth. `runtime_manifest.json` contains only operational mechanism,
event, handler, and resolver tables, binds the spec-manifest hash, and excludes
paths, debug/owner labels, evidence, project requirements, tests, maturity,
timestamps, GUIDs, definition values, and object instances. Primary tables
sort by numeric ID, resolver phases by `phase_order` then `phase_id`, and
semantic arrays retain declared order. Canonical output is compact ordinal-key
UTF-8 without BOM and with exactly one trailing LF.

The CLI is read-only by default and its public action accepts only project
root, view mode, and output/verify directory, never an injected view, spec set,
or compilation object. Explicit output and verification are confined to
immutable child directories with existing parents below the system temp
directory or ignored `battle/generated/battle_specs/`. Project-local directory
and file targets must all pass `git check-ignore --no-index`. Both files use
exclusive create-new handles, stable two-file reads, and a sibling staging
directory published with one directory rename; exact repeats are idempotent
and different or incomplete existing pairs are never overwritten. The
compiler has no deletion path: failures retain evidence for diagnosis and a
retry uses a new GUID. Project-local paths cannot be reclassified as temp
output even when a CI clone lives below `%TEMP%`. The current empty input hash
remains
`32857c87d8e374886c91e9a65a2eed546478930d640d5ba4ecf006c18a1fa821`;
its compiled spec/runtime hashes are respectively
`9f35401d489d6a0e55c2514fe8325850dc353c8b907f919fcd30dccfd6a87b57`
and
`5d3971516b957d9f58986eba6d5b8e741dc8da8b609c234ffb8b7222e00b9d39`.
The 69-check repository-view suite covers captured/cloned worktree, HEAD, and
index bytes; per-file/path/aggregate/Git-output limits; ordinal paths; invalid
UTF-8; no-follow final-path containment; reparse/nonregular/unmerged states;
and reviewed surface/ignore parity. The 632-check compiler suite covers both
output schemas and all cross-schema pointers, a complete synthetic graph,
schema projections, maturity threshold independence, test-requirement and
phase-event ownership, semantic ordering, deterministic diagnostics, closed
public actions, no-write operation, byte-identical double output, stable
locked verification, tamper/oversize detection, immutable publication, output
boundaries, ignored-path enforcement, and all major reference failures.

## P2 Fixture Requirement Preflight

P2 Todo 6 remains open because its two setup paths require production types
that the ordered roadmap assigns to P7. `CANONICAL_SETUP` must decode the exact
production `BattleSetup` and pass `BattleSetupValidator`; `LAUNCH_REQUEST` must
use the exact production `BattleLaunchRequest`, `BattleSetupBuilder`, synthetic
source ports, and the same validator. This slice therefore does not introduce
a fixture-only setup DTO, default expansion, setup digest, executable
`BattleFixture`, runner, or coverage observation.

The battle-local P2D preflight instead derives a closed fixture-requirement
manifest from already validated `SCENARIO TestManifestEntry` records. It
requires `fixture_id == test_id`, copies only coverage targets, expected
event/handler/state-op/command IDs, and required oracle kinds, and sorts rows
by numeric fixture ID. Before projection it independently canonicalizes and
re-hashes the compiled spec manifest and input set, revalidates each test
authoring record, and joins the same authoring hash through the input index and
compiled test index. A caller cannot bind substituted test declarations to an
unrelated spec hash.

The requirement artifact is separate from the runtime catalog. Its source spec
compiler version, preflight version, spec hash, and stable-ID hash are explicit;
it contains no paths, fixture payload, setup data, execution status, or
coverage result. The current empty manifest hash is
`ab8ecfeb6a3c5ba0b1a7147ee06082b6cb174d6c9e95c917f034a74d1c836b59`.
Any path below `res://battle/fixtures/synthetic/scenarios/` fails in Repository,
Worktree, and Staged views with `P2D_SETUP_COMPILER_UNAVAILABLE_P7` and produces
no artifact. The scope gate now runs this preflight after the spec compiler.

The 118-check focused suite covers the recursively closed output schema,
byte-identical empty and synthetic projections, numeric fixture ordering,
non-scenario exclusion, exact field projections, canonical spec/input/test
hash binding, post-compilation forgery and noncanonical JSON rejection, and
read-only fixture-path rejection in all three Git views. The clean source
script container, parser, and tester are structural evidence only; their text
syntax, payloads, identifiers, values, and permissive parsing are not copied.

## P2 Mechanism Trace Probe

P2 Todo 7 and completion gate G03 are complete. `MechanismTraceProbe` retains
the six contract methods `begin_test`, `enter_branch`, `enter_stage`,
`record_rng`, `record_state_op`, and `end_test` as `void` observation calls.
The default instance is a disabled null object: it allocates no trace-record
capacity, ignores
malformed calls, maintains no scope, and cannot alter rule ordering, RNG, or
mutation. Enabled instances are explicitly bounded from 1 through 65,536
records and preallocate only fixed-width integer storage.

Scenario records require a positive `test_id` with `fixture_id == test_id`;
unit records require a positive test ID and fixture sentinel zero. Nested begin,
missing/mismatched end, invalid stable IDs, negative or reversed RNG cursors,
and all four observation calls outside a scope are rejected without appending.
The first typed error is latched and copied to callers while later rejection
and dropped counters remain diagnostic only. A mismatched end clears its scope
so teardown cannot leak it into the next run.

Every accepted record has exactly 13 signed integers: kind, one-based sequence,
test, fixture, mechanism, branch, stage, draw, stream, tag, cursor before,
cursor after, and opcode. Zero marks an unused stable-ID field and minus one an
unused cursor field. `records()` returns the retained window in chronological
order as a defensive packed-array snapshot. When the ring overwrites its oldest
entry it increments `dropped_count` and latches
`BATTLE_TRACE_CAPACITY_EXCEEDED`; consumers must require a valid, closed probe
before treating any window as coverage evidence. An RNG record requires
`cursor_after > cursor_before`; zero-consumption paths emit no RNG record and
later fixture cursor/oracle assertions must prove that absence.

The probe lives in the local foundation layer so future rules, effects, and
engine code can share one observer without reversing the dependency graph. It
remains RefCounted-only and has no Node, SceneTree, runtime resource load,
filesystem, network, world, or presentation dependency. Its `stage_id` is the
mechanism-local formula stage defined by the P2 spec; resolver `phase_id` and
`subphase_id` are deliberately not folded into this API. The 227-check headless
suite proves exact layouts, scenario/unit inheritance, before/after-scope G03
rejection for every observation method, lifecycle errors, ID/cursor boundaries,
bounded overflow, first-error and snapshot isolation, disabled behavior, and
byte-identical repeated traces. It does not execute a fixture or claim coverage.

## Quantified Progress

The local implementation mainline contains `465` checklist items across Q0
and P0-P18. The separately deferred N0 network phase and nine shared preamble
items are excluded from this denominator. Q0 is `23/23`, P0 is `22/22`, P1 is
`17/17`, and P2 is `8/16`. Current mainline progress is therefore `70/465`
items (`15.1%`), with `3/20` phases complete and P2 in progress. This count
advances only after a checklist item has implementation, focused verification,
Wiki/Skill memory, and a focused commit.

P2 Todo1-5, Todo7, deterministic gate G01, and scope gate G03 are now closed:
append-only/
tombstone-safe mechanism and runtime ID domains, the presentation cue/payload/
tag manifest, five strict authoring schemas, validator-owned maturity, the
deterministic spec compiler, byte-identical spec/runtime manifest output, and
bounded in-scope mechanism trace records. Todo6 has a deterministic requirement
preflight but cannot close until the ordered P7 production setup contracts
exist. Todo8, the source-evidence/audit-disposition join, is the next independent
P2 item. No world-runtime coupling has been introduced.

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

& "C:\path\to\Godot_v4.7-stable_win64_console.exe" `
  --headless --path .\new-game-project `
  --script res://battle/tests/application/p1_session_lifecycle_test.gd

& "C:\path\to\Godot_v4.7-stable_win64_console.exe" `
  --no-header --headless --path .\new-game-project `
  --script res://battle/tests/battle_suite_test.gd

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\new-game-project\battle\tools\test_battle.ps1 `
  -GodotPath "C:\path\to\Godot_v4.7-stable_win64_console.exe" `
  -Suite P1 -RepositoryValidation Fast

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\new-game-project\battle\tests\foundation\p1_dependency_gate_test.ps1

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
  -File .\new-game-project\battle\tools\test_battle.ps1 `
  -GodotPath "C:\path\to\Godot_v4.7-stable_win64_console.exe" `
  -Suite P2Trace

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\new-game-project\battle\tools\battle_specs\compilers\compile_p2_specs.ps1 `
  -Mode Repository

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\new-game-project\battle\tools\battle_specs\compilers\compile_p2_fixture_requirements.ps1 `
  -Mode Repository

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
The P1 Session lifecycle test executes 282 checks across stable empty-engine
hashes and failures, static result sealing, authority/session reentry guards,
battle binding, bounded FIFO and request gates, exact terminal publication,
shutdown cleanup, 100 WeakRef graphs, and real SceneTree release.
The P1 aggregate requires all 597 focused vectors in three isolated headless
child suites. Its 64-check tool contract proves selector parsing, clean-cache
battle-only execution, assertion and usage failures, exact child/root exit
propagation, and optional root Full arguments. The one-command P1 selection
also runs the dependency gate; `RepositoryValidation Fast` adds the current
read-only root gate without requiring Platinum assets.
The P2 ID/presentation suite executes 75 checks across strict structure,
canonical hashes, append-only evolution, tombstones, scoped IDs, cue/payload
cross-references, staged-index isolation, and semantic scope-gate integration.
The P2 strict-spec suite executes 508 checks across all five authoring shapes,
recursive schema closure, local topology and ordering, maturity promotion,
three Git views, ACTIVE identity, read-only validation, and reparse rejection.
The P2 repository-view suite executes 69 checks across captured and cloned
worktree/HEAD/index bytes, bounded allocation, ordinal paths, invalid
encodings, no-follow redirects, reparse points, review/ignore surface parity,
Git modes, and unmerged indexes without mutating Git.
The P2 compiler suite executes 632 checks across recursive output-schema
closure and cross-schema pointers, a closed synthetic graph, runtime
projection, canonical double output, deterministic errors, global/scoped/test
and phase-event references, maturity thresholds, closed no-write/write/verify
actions, stable locked pairs, immutable ignored output, tamper/oversize
detection, and pair preflight.
The P2 fixture-preflight suite executes 118 checks across the closed requirement
schema, canonical source/input/test hash binding, deterministic SCENARIO-only
projection, forged-compilation rejection, no-write CLI behavior, and explicit
Repository/Worktree/Staged refusal of setup-bearing fixture files before P7.
The P2 mechanism-trace suite executes 227 Godot checks across its fixed 13-field
records, scenario/unit scope inheritance, all eight before/after-scope record
rejections, lifecycle and input failures, capacity-one and repeated ring wraps, defensive
diagnostics/snapshots, disabled null behavior, and deterministic repeated bytes.

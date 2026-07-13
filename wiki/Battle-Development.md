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
| P0 | In progress | Frozen scope and authorization/evidence schemas are complete; source-audit generation and the staged asset gate remain |
| P1-P18 | Not started | Battle contracts, data, engine, rules, AI, settlement, replay, and full text interaction |
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

Four JSON Schema draft 2020-12 contracts define the scope, licensed sources,
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
contract/evidence hashes for a valid and stale work item.

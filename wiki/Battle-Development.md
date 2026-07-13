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
| P0 | Next | Source audit, authorization, evidence schema, and asset-boundary validation |
| P1-P18 | Not started | Battle contracts, data, engine, rules, AI, settlement, replay, and full text interaction |
| N0 | Deferred | Network admission work after the complete local implementation |

Q0 intentionally reports `Catalog: not implemented`, `Engine: not
implemented`, and `Battle: unavailable`. Its `SYNTHETIC_READY` bootstrap is a
development smoke state, not a playable battle or catalog completion claim.

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
state.

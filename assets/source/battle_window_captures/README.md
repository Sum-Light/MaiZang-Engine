# Battle Window Source Captures

This directory is reserved for exact source-derived transparent battle
window-layer captures:

- `action.png`
- `message.png`
- `move.png`

These files must be 240x160 non-interlaced 8-bit RGBA PNGs with transparent
pixels outside the source battle windows. Do not place full-scene emulator
screenshots here; those belong under `assets/source/battle_scene_captures/`.

Import and validate captures with:

```powershell
python tools\importer\import_battle_window_captures.py --source-dir <capture-dir>
```

Use `--dry-run` to validate without copying, and `--self-test` to verify the
import contract.

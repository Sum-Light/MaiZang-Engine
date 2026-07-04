#!/usr/bin/env python3
"""Export source-traced overworld field-door coverage."""

import argparse
import json
import re
import sys
from pathlib import Path

from export_map import write_json, write_manifest
from source_probe import load_config, to_project_path


GENERATED_BY = "tools/importer/export_overworld_field_door_trace.py"
REPORT_PATH = Path("overworld/field_door_trace.json")
REPO_ROOT = Path(__file__).resolve().parents[2]

SOURCE_FILES = [
    "include/field_door.h",
    "src/field_door.c",
    "src/scrcmd.c",
    "include/script.h",
    "src/script.c",
    "include/sound.h",
    "src/field_screen_effect.c",
    "src/follower_npc.c",
    "include/fieldmap.h",
    "src/fieldmap.c",
    "include/global.fieldmap.h",
    "include/field_camera.h",
    "src/field_camera.c",
    "include/metatile_behavior.h",
    "src/metatile_behavior.c",
    "include/task.h",
    "src/task.c",
    "include/event_data.h",
    "src/event_data.c",
    "include/global.h",
    "include/save.h",
    "include/constants/metatile_labels.h",
    "include/constants/metatile_behaviors.h",
    "include/constants/songs.h",
    "include/constants/flags.h",
    "include/constants/maps.h",
]

REQUIRED_SYMBOLS = [
    "DOOR_SOUND_NORMAL",
    "DOOR_SOUND_SLIDING",
    "DOOR_SOUND_ARENA",
    "DoorGraphics",
    "DoorAnimFrame",
    "sDoorAnimTiles_General",
    "sDoorAnimPalettes_General",
    "sDoorOpenAnimFrames",
    "sDoorCloseAnimFrames",
    "sBigDoorOpenAnimFrames",
    "sBigDoorCloseAnimFrames",
    "sDoorAnimFrames_OpenSmallFrlg",
    "sDoorAnimFrames_CloseSmallFrlg",
    "sDoorAnimFrames_OpenLargeFrlg",
    "sDoorAnimFrames_CloseLargeFrlg",
    "sDoorAnimGraphicsTable",
    "DOOR_TILE_START_SIZE1",
    "DOOR_TILE_START_SIZE2",
    "CopyDoorTilesToVram",
    "BuildDoorTiles",
    "DrawCurrentDoorAnimFrameFrlg",
    "DrawCurrentDoorAnimFrame",
    "DrawClosedDoorTilesFrlg",
    "DrawClosedDoorTiles",
    "DrawDoor",
    "AnimateDoorFrame",
    "Task_AnimateDoor",
    "GetLastDoorFrame",
    "GetDoorGraphics",
    "StartDoorAnimationTask",
    "DrawClosedDoor",
    "DrawOpenedDoor",
    "StartDoorOpenAnimation",
    "StartDoorCloseAnimation",
    "GetDoorSoundType",
    "Debug_FieldAnimateDoorOpen",
    "FieldSetDoorOpened",
    "FieldSetDoorClosed",
    "FieldAnimateDoorClose",
    "FieldAnimateDoorOpen",
    "FieldIsDoorAnimationRunning",
    "GetDoorSoundEffect",
    "ShouldUseMultiCorridorDoor",
    "MetatileBehavior_IsDoor",
    "MapGridGetMetatileBehaviorAt",
    "MapGridGetMetatileIdAt",
    "CurrentMapDrawMetatileAt",
    "DrawDoorMetatileAt",
    "DrawMetatile",
    "CreateTask",
    "DestroyTask",
    "FuncIsActiveTask",
    "gTasks",
    "Script_RequestEffects",
    "SCREFF_V1",
    "SCREFF_SAVE",
    "SCREFF_HARDWARE",
    "ScriptReadHalfword",
    "VarGet",
    "PlaySE",
    "SetupNativeScript",
    "ScrCmd_opendoor",
    "ScrCmd_closedoor",
    "IsDoorAnimationStopped",
    "ScrCmd_waitdooranim",
    "ScrCmd_setdooropen",
    "ScrCmd_setdoorclosed",
    "MAP_OFFSET",
    "gMapHeader",
    "gSpecialVar_0x8004",
    "gSpecialVar_0x8005",
    "FlagGet",
    "FLAG_ENABLE_MULTI_CORRIDOR_DOOR",
    "MAP_BATTLE_FRONTIER_BATTLE_TOWER_MULTI_CORRIDOR",
    "MAP_GROUP",
    "MAP_NUM",
    "gSaveBlock1Ptr",
    "SE_DOOR",
    "SE_SLIDING_DOOR",
    "SE_REPEL",
    "Task_DoDoorWarp",
    "DoDoorWarp",
    "Task_ExitDoor",
    "Task_ExitNonAnimDoor",
    "FieldCB_DefaultWarpExit",
    "SetUpWarpExitTask",
]

FRAME_TABLE_NAMES = [
    "sDoorOpenAnimFrames",
    "sDoorCloseAnimFrames",
    "sBigDoorOpenAnimFrames",
    "sBigDoorCloseAnimFrames",
    "sDoorAnimFrames_OpenSmallFrlg",
    "sDoorAnimFrames_CloseSmallFrlg",
    "sDoorAnimFrames_OpenLargeFrlg",
    "sDoorAnimFrames_CloseLargeFrlg",
]

SOUND_EFFECT_MAP = {
    "DOOR_SOUND_NORMAL": "SE_DOOR",
    "DOOR_SOUND_SLIDING": "SE_SLIDING_DOOR",
    "DOOR_SOUND_ARENA": "SE_REPEL",
}

DOOR_GRAPHICS_TABLE_RULES = [
    "sDoorAnimGraphicsTable rows map a metatile id plus active primary/secondary tileset pointer to a sound category, size, tile source, and palette selector array.",
    "The active Emerald branch is the #if !IS_FRLG table; the FRLG branch is still recorded as metadata for cross-game parity but is not a target runtime branch for this port.",
    "GetDoorGraphics only matches rows whose metatile number equals the current map grid metatile and whose tileset pointer equals the current primary or secondary tileset.",
    "The unused Emerald Battle Frontier row uses NULL for tileset, so it documents a resource but does not match ordinary GetDoorGraphics runtime lookup.",
    "A size 1 Emerald door draws one 1x2 metatile column; a size 2 Emerald door draws a 2x2 metatile area.",
]

DOOR_FRAME_RULES = [
    "Emerald small open frames are closed sentinel -1, then source offsets 0, 0x100, 0x200 with time 4 for each visible step.",
    "Emerald small close frames reverse that order: 0x200, 0x100, 0, closed sentinel -1.",
    "Emerald big doors use the same order but frame offsets are -1/0/0x200/0x400 for 16-tile frame copies.",
    "FRLG frame tables use TILE_SIZE_4BPP expressions and size-specific large/small frame tables; these stay metadata-only for the Emerald target.",
    "AnimateDoorFrame draws only when tCounter is zero, advances when tCounter equals the frame time, and stops when the next frame has terminal time 0.",
]

DOOR_DRAW_RULES = [
    "A frame offset of 0xFFFF means closed-door redraw, implemented by CurrentMapDrawMetatileAt on the source map metatiles.",
    "A non-closed frame copies the selected animation tiles into the source VRAM door tile range, then builds temporary 8-entry metatile tile arrays.",
    "DrawDoorMetatileAt forces the rendered door animation metatile through METATILE_LAYER_TYPE_COVERED rather than using the source metatile attribute layer.",
    "Emerald size 1 draws top at (x, y - 1) and bottom at (x, y); Emerald size 2 also draws (x + 1, y - 1) and (x + 1, y).",
    "Godot should not recreate the GBA VRAM slot limit; the visible effect should be implemented with normal images, TileMap layers, overlays, or renderer primitives.",
]

DOOR_SCRIPT_RULES = [
    "ScrCmd_opendoor reads x/y through VarGet(ScriptReadHalfword), requests SCREFF_V1 | SCREFF_SAVE | SCREFF_HARDWARE, applies MAP_OFFSET, plays GetDoorSoundEffect, and starts FieldAnimateDoorOpen.",
    "ScrCmd_closedoor uses the same coordinate/effect setup but starts FieldAnimateDoorClose and does not play a close sound itself.",
    "ScrCmd_waitdooranim requests SCREFF_V1 | SCREFF_HARDWARE and installs IsDoorAnimationStopped through SetupNativeScript.",
    "IsDoorAnimationStopped keeps the script in native mode until FieldIsDoorAnimationRunning reports that Task_AnimateDoor is gone.",
    "ScrCmd_setdooropen and ScrCmd_setdoorclosed immediately draw the opened/closed visual state after applying MAP_OFFSET.",
]

DOOR_TRANSITION_RULES = [
    "Task_DoDoorWarp stops dash state, clears follower door state, freezes object events, resolves PlayerGetDestCoords, plays GetDoorSoundEffect at (x, y - 1), and starts FieldAnimateDoorOpen.",
    "After the open task finishes, Task_DoDoorWarp queues MOVEMENT_ACTION_WALK_NORMAL_UP for the player and then hides the player before the close animation.",
    "If a visible follower exists, the close animation is skipped while follower door handling takes over; otherwise FieldAnimateDoorClose runs before the fade/load path.",
    "Task_ExitDoor hides player/follower, opens the destination door state with FieldSetDoorOpened, waits for weather fade-in, steps the player down, then starts FieldAnimateDoorClose.",
    "SetUpWarpExitTask selects Task_ExitDoor, Task_ExitStairs, Task_ExitNonAnimDoor, or Task_ExitNonDoor based on destination metatile behavior.",
]

MULTI_CORRIDOR_RULES = [
    "ShouldUseMultiCorridorDoor requires FLAG_ENABLE_MULTI_CORRIDOR_DOOR and the current map to be MAP_BATTLE_FRONTIER_BATTLE_TOWER_MULTI_CORRIDOR.",
    "When enabled, DrawDoor mirrors every open/close/current-frame draw to gSpecialVar_0x8004/gSpecialVar_0x8005 plus MAP_OFFSET.",
    "This synchronized partner door path is independent of the primary door coordinates passed to FieldAnimateDoorOpen/Close.",
]

GODOT_CURRENT_RULES = [
    "export_tilesets.py parses src/field_door.c and bakes used size 1 door animation strips into RGBA atlases under assets/generated/door_anims.",
    "Generated tileset JSON stores door_animations metadata with frame_time 4, frame_count 4, open frame indices [-1, 0, 1, 2], close frame indices [2, 1, 0, -1], and source sound-effect symbols.",
    "MapRuntime indexes generated door animations by metatile id and exposes get_door_animation_at(cell).",
    "EventManager includes generated door animation metadata in first-pass door warp transition sequences.",
    "TransitionSequencePlayer draws door frames through DebugMapPlane overlay calls, while ScriptVM only records standalone opendoor/closedoor/waitdooranim as field-effect metadata.",
]

UNSUPPORTED = [
    {
        "code": "full_door_graphics_table_import_pending",
        "status": "first_pass",
        "source": "src/field_door.c:sDoorAnimGraphicsTable",
        "detail": "The importer can parse the source table and currently bakes only generated-map, used, size 1 door animations; full table export and runtime lookup for every map is pending.",
    },
    {
        "code": "door_layer_redraw_runtime_pending",
        "status": "unsupported",
        "source": "src/field_door.c:DrawDoor + src/field_camera.c:DrawDoorMetatileAt",
        "detail": "Door frames are presented as overlays rather than source-shaped CurrentMapDrawMetatileAt/DrawDoorMetatileAt redraws through layer-aware map rendering.",
    },
    {
        "code": "door_animation_task_runtime_pending",
        "status": "unsupported",
        "source": "src/field_door.c:Task_AnimateDoor/AnimateDoorFrame",
        "detail": "Godot does not yet own a source-equivalent per-frame door task with active-task ids, counter semantics, and FuncIsActiveTask polling.",
    },
    {
        "code": "script_waitdooranim_async_pending",
        "status": "unsupported",
        "source": "src/scrcmd.c:ScrCmd_waitdooranim",
        "detail": "ScriptVM records waitdooranim metadata but does not suspend and resume script execution through a native wait callback.",
    },
    {
        "code": "standalone_script_door_animation_pending",
        "status": "unsupported",
        "source": "src/scrcmd.c:ScrCmd_opendoor/ScrCmd_closedoor/ScrCmd_setdooropen/ScrCmd_setdoorclosed",
        "detail": "Door presentation currently runs only for transition sequences; standalone script-driven door commands are not rendered as source-equivalent map mutations.",
    },
    {
        "code": "big_door_size2_runtime_pending",
        "status": "unsupported",
        "source": "src/field_door.c:sBigDoorOpenAnimFrames/DrawCurrentDoorAnimFrame",
        "detail": "Size 2 door animation resources and 2x2 draw rules are traced, but the current atlas baking and presentation path only supports size 1 doors.",
    },
    {
        "code": "multi_corridor_partner_door_pending",
        "status": "unsupported",
        "source": "src/field_door.c:ShouldUseMultiCorridorDoor",
        "detail": "The Battle Tower Multi Corridor partner door mirror path is traced but not implemented in Godot runtime or generated sequence data.",
    },
    {
        "code": "frlg_door_branch_metadata_only",
        "status": "metadata_only",
        "source": "src/field_door.c:#if IS_FRLG frame/table branches",
        "detail": "FRLG-specific frame offsets, large-door rules, and table rows are recorded for reference but are not a runtime target for the Emerald port slice.",
    },
    {
        "code": "door_vram_copy_godot_native",
        "status": "metadata_only",
        "source": "src/field_door.c:CopyDoorTilesToVram",
        "detail": "GBA VRAM tile-copy addresses are source metadata only; Godot should use normal textures or TileMap/renderer resources while preserving visible frame order.",
    },
    {
        "code": "door_palette_slots_godot_native",
        "status": "metadata_only",
        "source": "src/field_door.c:sDoorAnimPalettes_*",
        "detail": "Palette selector arrays are decoded at import time; Godot should not recreate runtime palette bank limits, but palette/tint effects must preserve visible source timing/result where practical.",
    },
    {
        "code": "door_sound_audio_metadata_only",
        "status": "metadata_only",
        "source": "src/field_door.c:GetDoorSoundEffect + src/field_screen_effect.c:Task_DoDoorWarp",
        "detail": "Door sound symbols and timing intent are preserved, but real audio playback remains intentionally out of scope for now.",
    },
    {
        "code": "follower_door_handoff_pending",
        "status": "unsupported",
        "source": "src/field_screen_effect.c:Task_DoDoorWarp + src/follower_npc.c",
        "detail": "Follower enter/exit-door animation and close-door skip rules are traced but not source-equivalent in current Godot presentation.",
    },
]


def read_text(path):
    with path.open("r", encoding="utf-8") as handle:
        return handle.read()


def line_occurrences(text, symbol):
    pattern = re.compile(r"\b%s\b" % re.escape(symbol))
    return [
        index
        for index, line in enumerate(text.splitlines(), start=1)
        if pattern.search(line)
    ]


def source_file_presence(source_root):
    return [
        {
            "path": path,
            "exists": (source_root / path).exists(),
        }
        for path in SOURCE_FILES
    ]


def symbol_locations(source_root):
    result = {}
    file_texts = {}
    for path in SOURCE_FILES:
        full_path = source_root / path
        file_texts[path] = read_text(full_path) if full_path.exists() else ""

    for symbol in REQUIRED_SYMBOLS:
        occurrences = []
        for path, text in file_texts.items():
            for line in line_occurrences(text, symbol):
                occurrences.append({"file": path, "line": line})
        result[symbol] = occurrences
    return result


def _parse_numeric_token(value):
    value = value.strip()
    if value == "-1":
        return -1
    if re.fullmatch(r"0x[0-9A-Fa-f]+|\d+", value):
        return int(value, 0)
    return None


def _normalized_u16_offset(raw_offset):
    parsed = _parse_numeric_token(raw_offset)
    if parsed is None:
        return None
    return parsed & 0xFFFF


def _extract_initializer(text, symbol):
    start_match = re.search(r"\b%s\b\s*\[\]\s*=\s*\{" % re.escape(symbol), text)
    if start_match is None:
        return ""
    start = start_match.end() - 1
    depth = 0
    for index in range(start, len(text)):
        char = text[index]
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return text[start + 1:index]
    return ""


def parse_frame_tables(field_door_text):
    tables = {}
    for name in FRAME_TABLE_NAMES:
        body = _extract_initializer(field_door_text, name)
        frames = []
        for match in re.finditer(r"\{([^{}]*)\}", body):
            row = match.group(1).strip()
            if not row:
                frames.append({
                    "time": 0,
                    "raw_offset": "0",
                    "normalized_offset": 0,
                    "terminal": True,
                })
                continue
            parts = [part.strip() for part in row.split(",", 1)]
            if len(parts) != 2:
                continue
            time_value = _parse_numeric_token(parts[0])
            frames.append({
                "time": time_value,
                "raw_offset": parts[1],
                "normalized_offset": _normalized_u16_offset(parts[1]),
                "closed_sentinel": parts[1] == "-1",
                "terminal": time_value == 0,
            })
        tables[name] = {
            "frames": frames,
            "non_terminal_count": sum(1 for frame in frames if not frame.get("terminal", False)),
            "terminal_count": sum(1 for frame in frames if frame.get("terminal", False)),
        }
    return tables


def _strip_c_comments(text):
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    text = re.sub(r"//.*", "", text)
    return text


def _door_table_sections(field_door_text):
    body = _extract_initializer(field_door_text, "sDoorAnimGraphicsTable")
    sections = {
        "emerald": body,
        "frlg": "",
    }
    if "#if !IS_FRLG" in body and "#else" in body:
        after_if = body.split("#if !IS_FRLG", 1)[1]
        emerald, rest = after_if.split("#else", 1)
        frlg = rest.split("#endif", 1)[0]
        sections["emerald"] = emerald
        sections["frlg"] = frlg
    return sections


def parse_door_graphics_table(field_door_text):
    pattern = re.compile(
        r"\{\s*(METATILE_[A-Za-z0-9_]+|0x[0-9A-Fa-f]+|\d+)\s*,"
        r"\s*(?:&(gTileset_[A-Za-z0-9_]+)|NULL)\s*,"
        r"\s*(DOOR_SOUND_[A-Z_]+)\s*,"
        r"\s*(\d+)\s*,"
        r"\s*(sDoorAnimTiles_[A-Za-z0-9_]+)\s*,"
        r"\s*(sDoorAnimPalettes_[A-Za-z0-9_]+)\s*\},"
    )
    result = {}
    for branch, section in _door_table_sections(field_door_text).items():
        rows = []
        for match in pattern.finditer(_strip_c_comments(section)):
            metatile_token = match.group(1)
            rows.append({
                "branch": branch,
                "metatile": metatile_token,
                "metatile_numeric": int(metatile_token, 0) if not metatile_token.startswith("METATILE_") else None,
                "tileset": match.group(2) or "",
                "runtime_matchable": bool(match.group(2)),
                "sound_type": match.group(3),
                "sound_effect": SOUND_EFFECT_MAP.get(match.group(3), "SE_DOOR"),
                "size": int(match.group(4)),
                "tiles_symbol": match.group(5),
                "palettes_symbol": match.group(6),
            })
        result[branch] = rows
    return result


def parse_asset_declarations(field_door_text):
    tile_decls = [
        {"symbol": match.group(1), "image_source": "%s.png" % match.group(2)}
        for match in re.finditer(
            r'static const u8 (sDoorAnimTiles_[A-Za-z0-9_]+)\[\] = INCBIN_U8\("([^"]+)\.4bpp"\);',
            field_door_text,
        )
    ]
    palette_decls = []
    for match in re.finditer(
        r"static const u8 (sDoorAnimPalettes_[A-Za-z0-9_]+)\[\] = \{([^}]*)\};",
        field_door_text,
    ):
        values = [
            int(part.strip(), 0)
            for part in match.group(2).split(",")
            if part.strip()
        ]
        palette_decls.append({
            "symbol": match.group(1),
            "values": values,
            "value_count": len(values),
        })
    return {
        "tile_declarations": tile_decls,
        "palette_declarations": palette_decls,
        "tile_declaration_count": len(tile_decls),
        "palette_declaration_count": len(palette_decls),
    }


def build_door_stats(frame_tables, graphics_table, assets):
    emerald_rows = graphics_table.get("emerald", [])
    frlg_rows = graphics_table.get("frlg", [])
    all_rows = emerald_rows + frlg_rows
    sound_counts = {}
    size_counts = {}
    for row in emerald_rows:
        sound_counts[row["sound_type"]] = sound_counts.get(row["sound_type"], 0) + 1
        size_key = str(row["size"])
        size_counts[size_key] = size_counts.get(size_key, 0) + 1
    return {
        "frame_table_count": len(frame_tables),
        "active_emerald_graphics_entry_count": len(emerald_rows),
        "frlg_graphics_entry_count": len(frlg_rows),
        "graphics_entry_count_all_branches": len(all_rows),
        "active_emerald_runtime_matchable_entry_count": sum(1 for row in emerald_rows if row["runtime_matchable"]),
        "active_emerald_size_counts": size_counts,
        "active_emerald_sound_counts": sound_counts,
        "tile_declaration_count": assets["tile_declaration_count"],
        "palette_declaration_count": assets["palette_declaration_count"],
    }


def current_godot_door_summary():
    tileset_dir = REPO_ROOT / "data" / "generated" / "tilesets"
    records = []
    warning_count = 0
    if tileset_dir.exists():
        for path in sorted(tileset_dir.glob("*.json")):
            try:
                data = json.loads(path.read_text(encoding="utf-8"))
            except json.JSONDecodeError:
                continue
            door_animations = data.get("door_animations", {})
            if not isinstance(door_animations, dict):
                continue
            animations = door_animations.get("animations", [])
            warnings = door_animations.get("warnings", [])
            if isinstance(warnings, list):
                warning_count += len(warnings)
            if not isinstance(animations, list):
                continue
            for animation in animations:
                if not isinstance(animation, dict):
                    continue
                records.append({
                    "tileset_json": to_project_path(path.relative_to(REPO_ROOT)),
                    "metatile_label": animation.get("metatile_label", ""),
                    "metatile_id": animation.get("metatile_id"),
                    "tileset": animation.get("tileset", ""),
                    "size": animation.get("size"),
                    "image": animation.get("image_project_path", ""),
                    "sound_effect": animation.get("sound_effect", ""),
                    "open_frame_indices": animation.get("open_frame_indices", []),
                    "close_frame_indices": animation.get("close_frame_indices", []),
                })
    return {
        "generated_door_animation_count": len(records),
        "generated_door_animation_warning_count": warning_count,
        "generated_door_animations": records,
        "current_runtime_shape": GODOT_CURRENT_RULES,
    }


def source_flow_rows():
    return [
        {
            "id": "door_graphics_table_lookup",
            "source_entry": "src/field_door.c:sDoorAnimGraphicsTable/GetDoorGraphics",
            "status": "first_pass",
            "critical_order": DOOR_GRAPHICS_TABLE_RULES,
            "godot_current": [
                "export_tilesets.py parses the same table but filters to currently exported maps and size 1 doors.",
            ],
            "gaps": [
                "All map tilesets, the full active Emerald table, and size 2 runtime lookup are not generated as complete runtime data yet.",
            ],
        },
        {
            "id": "door_frame_tables_and_task_timing",
            "source_entry": "src/field_door.c:sDoorOpenAnimFrames/sDoorCloseAnimFrames/AnimateDoorFrame",
            "status": "metadata_only",
            "critical_order": DOOR_FRAME_RULES,
            "godot_current": [
                "EventManager stores frame_time 4, frame_count 4, and source order in transition sequence metadata.",
            ],
            "gaps": [
                "There is no Task_AnimateDoor owner with source active-task ids and counter polling yet.",
            ],
        },
        {
            "id": "door_tiles_palette_and_layer_draw",
            "source_entry": "src/field_door.c:CopyDoorTilesToVram/DrawCurrentDoorAnimFrame + src/field_camera.c:DrawDoorMetatileAt",
            "status": "metadata_only",
            "critical_order": DOOR_DRAW_RULES,
            "godot_current": [
                "Door resources are baked into ordinary RGBA atlases and drawn as DebugMapPlane overlays.",
            ],
            "gaps": [
                "Layer-aware door redraw through source-equivalent covered metatile placement is pending.",
            ],
        },
        {
            "id": "public_door_api_behavior_gate",
            "source_entry": "include/field_door.h + src/field_door.c:FieldSetDoor*/FieldAnimateDoor*",
            "status": "metadata_only",
            "critical_order": [
                "FieldSetDoorOpened/Closed first require MetatileBehavior_IsDoor at the target map cell.",
                "FieldAnimateDoorOpen/Close return -1 when the target behavior is not a door.",
                "Successful animation starts return the Task_AnimateDoor id, unless another door task is already active.",
                "FieldIsDoorAnimationRunning is exactly FuncIsActiveTask(Task_AnimateDoor).",
            ],
            "godot_current": [
                "MapRuntime exposes metatile behavior and door animation metadata, but no source-equivalent public field-door API exists.",
            ],
            "gaps": [
                "Door command, transition, follower, and debug paths need one shared Godot door-runtime owner.",
            ],
        },
        {
            "id": "script_door_commands_and_wait",
            "source_entry": "src/scrcmd.c:ScrCmd_opendoor/ScrCmd_closedoor/ScrCmd_waitdooranim/ScrCmd_setdooropen/ScrCmd_setdoorclosed",
            "status": "metadata_only",
            "critical_order": DOOR_SCRIPT_RULES,
            "godot_current": [
                "ScriptVM records opendoor, closedoor, waitdooranim, setdooropen, and setdoorclosed intent as field-effect metadata when present in scripts.",
            ],
            "gaps": [
                "ScriptVM does not start door animation tasks, play presentation, or block on native waitdooranim completion.",
            ],
        },
        {
            "id": "door_sound_resolution",
            "source_entry": "src/field_door.c:GetDoorSoundEffect",
            "status": "metadata_only",
            "critical_order": [
                "DOOR_SOUND_NORMAL resolves to SE_DOOR.",
                "DOOR_SOUND_SLIDING resolves to SE_SLIDING_DOOR.",
                "DOOR_SOUND_ARENA resolves to SE_REPEL.",
                "Unknown or missing door graphics fall back to SE_DOOR.",
                "Audio playback is triggered by script opendoor and door-warp entry points, but audio is out of scope for current Godot runtime.",
            ],
            "godot_current": [
                "Generated door animation metadata carries the resolved sound_effect symbol; TransitionSequencePlayer keeps play_se steps metadata-only.",
            ],
            "gaps": [
                "No real audio playback or mixer timing is implemented for door sounds yet.",
            ],
        },
        {
            "id": "door_warp_transition_usage",
            "source_entry": "src/field_screen_effect.c:Task_DoDoorWarp/Task_ExitDoor/SetUpWarpExitTask",
            "status": "first_pass",
            "critical_order": DOOR_TRANSITION_RULES,
            "godot_current": [
                "EventManager and TransitionSequencePlayer play a first-pass source-ordered door warp sequence with generated door overlays.",
            ],
            "gaps": [
                "Exact door task ownership, follower handoff, weather fade, audio, and layer redraw semantics remain incomplete.",
            ],
        },
        {
            "id": "battle_tower_multi_corridor_partner_door",
            "source_entry": "src/field_door.c:ShouldUseMultiCorridorDoor/DrawDoor",
            "status": "unsupported",
            "critical_order": MULTI_CORRIDOR_RULES,
            "godot_current": [
                "No generated map sequence or door runtime mirrors a second door from special vars yet.",
            ],
            "gaps": [
                "Needs flag/var-aware door-runtime support and Battle Tower Multi Corridor map coverage.",
            ],
        },
        {
            "id": "follower_door_interaction",
            "source_entry": "src/field_screen_effect.c:Task_DoDoorWarp + src/follower_npc.c",
            "status": "metadata_only",
            "critical_order": [
                "Task_DoDoorWarp may place a visible follower into a pokeball-style movement before the player enters.",
                "A visible follower can prevent the normal close-door animation during entry.",
                "Task_ExitDoor sets follower come-out-door indicators after destination close animation finishes.",
                "follower_npc.c can independently request FieldAnimateDoorOpen/Close and GetDoorSoundEffect during follower door handling.",
            ],
            "godot_current": [
                "Follower NPC behavior is not source-equivalent in current overworld runtime.",
            ],
            "gaps": [
                "Follower-specific door state, movements, sound intent, and close-skip behavior are pending.",
            ],
        },
        {
            "id": "godot_current_door_mapping",
            "source_entry": "Godot importer/runtime owner map",
            "status": "first_pass",
            "critical_order": GODOT_CURRENT_RULES,
            "godot_current": [
                "The current slice is useful for Littleroot door transition playback, but intentionally below source-equivalent field_door runtime behavior.",
            ],
            "gaps": [
                "Promote generated metadata into a shared door-runtime and layer-aware renderer before marking door animation parity as ported.",
            ],
        },
    ]


def manifest_entry_for(exported, output_path):
    stats = exported["stats"]
    return {
        "category": "overworld_field_door_trace",
        "path": to_project_path(output_path),
        "entry_count": stats["flow_count"],
        "source_file_count": stats["source_file_count"],
        "missing_source_file_count": stats["missing_source_file_count"],
        "required_symbol_count": stats["required_symbol_count"],
        "missing_symbol_count": stats["missing_symbol_count"],
        "unsupported_count": stats["unsupported_count"],
    }


def build_export(source_root):
    source_root = Path(source_root)
    field_door_text = read_text(source_root / "src/field_door.c")
    presence = source_file_presence(source_root)
    locations = symbol_locations(source_root)
    missing_symbols = sorted(
        symbol
        for symbol, occurrences in locations.items()
        if not occurrences
    )
    frame_tables = parse_frame_tables(field_door_text)
    graphics_table = parse_door_graphics_table(field_door_text)
    assets = parse_asset_declarations(field_door_text)
    door_stats = build_door_stats(frame_tables, graphics_table, assets)
    flow_rows = source_flow_rows()
    status_counts = {}
    for row in flow_rows:
        status = row["status"]
        status_counts[status] = status_counts.get(status, 0) + 1
    unsupported_status_counts = {}
    for row in UNSUPPORTED:
        status = row["status"]
        unsupported_status_counts[status] = unsupported_status_counts.get(status, 0) + 1

    stats = {
        "flow_count": len(flow_rows),
        "source_file_count": len(SOURCE_FILES),
        "missing_source_file_count": sum(1 for item in presence if not item["exists"]),
        "required_symbol_count": len(REQUIRED_SYMBOLS),
        "missing_symbol_count": len(missing_symbols),
        "missing_symbols": missing_symbols,
        "status_counts": status_counts,
        "unsupported_count": len(UNSUPPORTED),
        "unsupported_status_counts": unsupported_status_counts,
    }
    stats.update(door_stats)
    return {
        "schema_version": 1,
        "generated_by": GENERATED_BY,
        "source_root": str(source_root),
        "source_files": presence,
        "required_symbols": locations,
        "door_frame_tables": frame_tables,
        "door_graphics_table": graphics_table,
        "door_assets": assets,
        "door_graphics_table_rules": DOOR_GRAPHICS_TABLE_RULES,
        "door_frame_rules": DOOR_FRAME_RULES,
        "door_draw_rules": DOOR_DRAW_RULES,
        "door_script_rules": DOOR_SCRIPT_RULES,
        "door_transition_rules": DOOR_TRANSITION_RULES,
        "multi_corridor_rules": MULTI_CORRIDOR_RULES,
        "sound_effect_map": SOUND_EFFECT_MAP,
        "source_flows": flow_rows,
        "godot_current": current_godot_door_summary(),
        "godot_trace_owners": {
            "importer": [
                "tools/importer/export_tilesets.py",
                GENERATED_BY,
            ],
            "runtime": [
                "scripts/autoload/script_vm.gd",
                "scripts/autoload/map_runtime.gd",
                "scripts/autoload/event_manager.gd",
            ],
            "presentation": [
                "scripts/overworld/transition_sequence_player.gd",
                "scripts/overworld/debug_map_plane.gd",
            ],
            "generated_data": [
                "data/generated/tilesets/*.json",
                "assets/generated/door_anims/*.png",
                "data/generated/overworld/field_door_trace.json",
            ],
            "tests": [
                "tools/importer/export_overworld_field_door_trace_smoke.py",
                "tools/godot_smoke/transition_sequence_player_smoke.gd",
                "tools/godot_smoke/map_runtime_smoke.gd",
            ],
        },
        "visual_effect_policy": {
            "palette_and_affine": "Use Godot-native textures, materials, shaders, animation tracks, or renderer primitives for palette, tint, scale, rotation, affine, and animation effects while preserving source timing and visible result where practical.",
            "gba_runtime_limits": "Do not recreate GBA palette-bank, VRAM, OAM, or binary tile memory limits at runtime unless a gameplay rule explicitly depends on them.",
            "audio": "Door sound/music/fanfare symbols stay metadata_only/unsupported until audio scope is reopened.",
        },
        "unsupported": UNSUPPORTED,
        "stats": stats,
    }


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, help="JSON config with source and output roots.")
    parser.add_argument("--source", type=Path, help="pokeemerald-expansion source root.")
    parser.add_argument("--output-root", type=Path, help="Generated data output root.")
    args = parser.parse_args(argv)

    config = load_config(args.config)
    source_root = args.source or Path(config.get("source_root", ""))
    output_root = args.output_root or Path(config.get("generated_data_root", "data/generated"))
    output_path = output_root / REPORT_PATH

    exported = build_export(source_root)
    write_json(output_path, exported)
    manifest_entry = manifest_entry_for(exported, output_path)
    write_manifest(
        output_root / "import_manifest.json",
        exported_overworld_reports=[manifest_entry],
        generator=GENERATED_BY,
    )

    print(json.dumps({"exported": manifest_entry, "stats": exported["stats"]}, ensure_ascii=False, indent=2))
    return 0 if exported["stats"]["missing_source_file_count"] == 0 and exported["stats"]["missing_symbol_count"] == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

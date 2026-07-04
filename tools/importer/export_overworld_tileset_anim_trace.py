#!/usr/bin/env python3
"""Export source-traced overworld tileset-animation coverage."""

import argparse
import json
import re
import sys
from pathlib import Path

from export_map import write_json, write_manifest
from source_probe import load_config, to_project_path


GENERATED_BY = "tools/importer/export_overworld_tileset_anim_trace.py"
REPORT_PATH = Path("overworld/tileset_anim_trace.json")
REPO_ROOT = Path(__file__).resolve().parents[2]

SOURCE_FILES = [
    "include/tileset_anims.h",
    "src/tileset_anims.c",
    "src/data/tilesets/headers.h",
    "include/global.fieldmap.h",
    "include/fieldmap.h",
    "src/fieldmap.c",
    "src/overworld.c",
    "include/overworld.h",
    "include/graphics.h",
    "include/palette.h",
    "src/palette.c",
    "include/util.h",
    "src/util.c",
    "include/battle_transition.h",
    "src/battle_transition.c",
    "include/task.h",
    "src/task.c",
    "include/gba/defines.h",
    "include/gba/macro.h",
]

REQUIRED_SYMBOLS = [
    "InitTilesetAnimations",
    "InitSecondaryTilesetAnimation",
    "UpdateTilesetAnimations",
    "TransferTilesetAnimsBuffer",
    "_InitPrimaryTilesetAnimation",
    "_InitSecondaryTilesetAnimation",
    "ResetTilesetAnimBuffer",
    "AppendTilesetAnimToBuffer",
    "sTilesetDMA3TransferBuffer",
    "sTilesetDMA3TransferBufferSize",
    "sPrimaryTilesetAnimCounter",
    "sPrimaryTilesetAnimCounterMax",
    "sSecondaryTilesetAnimCounter",
    "sSecondaryTilesetAnimCounterMax",
    "sPrimaryTilesetAnimCallback",
    "sSecondaryTilesetAnimCallback",
    "TilesetAnim_General",
    "TilesetAnim_Building",
    "TilesetAnim_Rustboro",
    "TilesetAnim_Dewford",
    "TilesetAnim_Slateport",
    "TilesetAnim_Mauville",
    "TilesetAnim_Lavaridge",
    "TilesetAnim_EverGrande",
    "TilesetAnim_Pacifidlog",
    "TilesetAnim_Sootopolis",
    "TilesetAnim_BattleFrontierOutsideWest",
    "TilesetAnim_BattleFrontierOutsideEast",
    "TilesetAnim_Underwater",
    "TilesetAnim_SootopolisGym",
    "TilesetAnim_Cave",
    "TilesetAnim_EliteFour",
    "TilesetAnim_MauvilleGym",
    "TilesetAnim_BikeShop",
    "TilesetAnim_BattlePyramid",
    "TilesetAnim_BattleDome",
    "TilesetAnim_BattleDome2",
    "TilesetAnim_General_Frlg",
    "TilesetAnim_CeladonCity",
    "TilesetAnim_VermilionGym",
    "TilesetAnim_CeladonGym",
    "TilesetAnim_SilphCo",
    "TilesetAnim_MtEmber",
    "QueueAnimTiles_General_Flower",
    "QueueAnimTiles_General_Water",
    "QueueAnimTiles_General_SandWaterEdge",
    "QueueAnimTiles_General_Waterfall",
    "QueueAnimTiles_General_LandWaterEdge",
    "QueueAnimTiles_Building_TVTurnedOn",
    "QueueAnimTiles_Rustboro_WindyWater",
    "QueueAnimTiles_Rustboro_Fountain",
    "QueueAnimTiles_Dewford_Flag",
    "QueueAnimTiles_Slateport_Balloons",
    "QueueAnimTiles_Mauville_Flowers",
    "QueueAnimTiles_Lavaridge_Steam",
    "QueueAnimTiles_Lavaridge_Lava",
    "QueueAnimTiles_EverGrande_Flowers",
    "QueueAnimTiles_Pacifidlog_LogBridges",
    "QueueAnimTiles_Pacifidlog_WaterCurrents",
    "QueueAnimTiles_Sootopolis_StormyWater",
    "QueueAnimTiles_Underwater_Seaweed",
    "QueueAnimTiles_Cave_Lava",
    "QueueAnimTiles_BattleFrontierOutsideWest_Flag",
    "QueueAnimTiles_BattleFrontierOutsideEast_Flag",
    "QueueAnimTiles_SootopolisGym_Waterfalls",
    "QueueAnimTiles_EliteFour_WallLights",
    "QueueAnimTiles_EliteFour_GroundLights",
    "QueueAnimTiles_MauvilleGym_ElectricGates",
    "QueueAnimTiles_BikeShop_BlinkingLights",
    "QueueAnimTiles_BattlePyramid_Torch",
    "QueueAnimTiles_BattlePyramid_StatueShadow",
    "BlendAnimPalette_BattleDome_FloorLights",
    "BlendAnimPalette_BattleDome_FloorLightsNoBlend",
    "InitTilesetAnim_General",
    "InitTilesetAnim_Petalburg",
    "InitTilesetAnim_Rustboro",
    "InitTilesetAnim_Dewford",
    "InitTilesetAnim_Slateport",
    "InitTilesetAnim_Mauville",
    "InitTilesetAnim_Lavaridge",
    "InitTilesetAnim_Fallarbor",
    "InitTilesetAnim_Fortree",
    "InitTilesetAnim_Lilycove",
    "InitTilesetAnim_Mossdeep",
    "InitTilesetAnim_EverGrande",
    "InitTilesetAnim_Pacifidlog",
    "InitTilesetAnim_Sootopolis",
    "InitTilesetAnim_BattleFrontierOutsideWest",
    "InitTilesetAnim_BattleFrontierOutsideEast",
    "InitTilesetAnim_Building",
    "InitTilesetAnim_Cave",
    "InitTilesetAnim_BikeShop",
    "InitTilesetAnim_Underwater",
    "InitTilesetAnim_SootopolisGym",
    "InitTilesetAnim_MauvilleGym",
    "InitTilesetAnim_EliteFour",
    "InitTilesetAnim_BattleDome",
    "InitTilesetAnim_BattlePyramid",
    "InitTilesetAnim_General_Frlg",
    "InitTilesetAnim_CeladonCity",
    "InitTilesetAnim_VermilionGym",
    "InitTilesetAnim_CeladonGym",
    "InitTilesetAnim_SilphCo",
    "InitTilesetAnim_MtEmber",
    "DmaCopy16",
    "CpuFill32",
    "CpuCopy16",
    "BG_VRAM",
    "TILE_OFFSET_4BPP",
    "TILE_SIZE_4BPP",
    "NUM_TILES_IN_PRIMARY",
    "NUM_TILES_IN_PRIMARY_FRLG",
    "NUM_TILES_TOTAL",
    "gMapHeader",
    "struct Tileset",
    "struct MapLayout",
    "TilesetCB",
    "CopyMapTilesetsToVram",
    "CopyPrimaryTilesetToVram",
    "CopySecondaryTilesetToVram",
    "CopySecondaryTilesetToVramUsingHeap",
    "LoadMapTilesetPalettes",
    "LoadSecondaryTilesetPalette",
    "LoadTilesetPalette",
    "GetNumTilesInPrimary",
    "GetNumPalsInPrimary",
    "LoadPaletteFast",
    "gPlttBufferUnfaded",
    "gPaletteFade",
    "BlendPalette",
    "BG_PLTT_ID",
    "PLTT_SIZE_4BPP",
    "FindTaskIdByFunc",
    "TASK_NONE",
    "Task_BattleTransition_Intro",
]

FRLG_INIT_FUNCTIONS = {
    "InitTilesetAnim_General_Frlg",
    "InitTilesetAnim_CeladonCity",
    "InitTilesetAnim_VermilionGym",
    "InitTilesetAnim_CeladonGym",
    "InitTilesetAnim_SilphCo",
    "InitTilesetAnim_MtEmber",
}

TILESET_CALLBACK_FLOW_RULES = [
    "Each struct Tileset row in src/data/tilesets/headers.h binds a callback symbol or NULL to the active primary/secondary tileset.",
    "The target port uses the #if !IS_FRLG branch as active Emerald data; FRLG rows are kept as metadata-only reference rows.",
    "InitTilesetAnimations resets the 20-slot transfer buffer, initializes the primary callback through gMapHeader.mapLayout->primaryTileset->callback(), then initializes the secondary callback the same way.",
    "InitSecondaryTilesetAnimation reinitializes only the secondary callback path during camera/connection map transitions after the secondary tileset graphics and palettes are loaded.",
]

COUNTER_AND_TRANSFER_RULES = [
    "UpdateTilesetAnimations clears the pending transfer buffer before incrementing both primary and secondary counters.",
    "Each counter wraps to zero when it reaches its configured max; callbacks receive the post-increment/wrapped timer value.",
    "AppendTilesetAnimToBuffer records at most 20 pending src/dest/size rows; excess appends are silently ignored by the source.",
    "TransferTilesetAnimsBuffer performs DmaCopy16 for each queued row during the VBlank-style field graphics transfer path, then clears the buffer size.",
    "Godot should not emulate BG_VRAM or DMA as runtime storage; the report preserves source destination tiles and sizes so a Godot renderer can play equivalent visible frames.",
]

MAP_LOAD_RULES = [
    "InitMapView copies map tilesets to VRAM, loads map tileset palettes, draws the whole map view, then calls InitTilesetAnimations.",
    "Camera-transition map loading copies and palette-loads only the new secondary tileset, applies weather palette maps, then calls InitSecondaryTilesetAnimation.",
    "The field main callback runs UpdateTilesetAnimations after UpdatePaletteFade and before scheduled BG tilemap copies.",
    "The field VBlank callback transfers OAM/sprite/palette work first, then calls TransferTilesetAnimsBuffer.",
    "Other staged load loops reload tilesets/palettes and call InitTilesetAnimations before map reveal tasks continue.",
]

PALETTE_EFFECT_RULES = [
    "Battle Dome floor lights are palette animation, not tile copy: the source copies 16 BG palette entries into gPlttBufferUnfaded at BG_PLTT_ID(8).",
    "The normal Battle Dome callback blends those entries with gPaletteFade.y and gPaletteFade.blendColor.",
    "If Task_BattleTransition_Intro is active, the callback switches to TilesetAnim_BattleDome2 and uses a 32-frame countdown path without immediate blending on every copy.",
    "Godot should implement this as a material/shader/color-track effect or equivalent palette-independent animation while preserving source frame rhythm.",
]

GODOT_CURRENT_RULES = [
    "export_tilesets.py bakes normal RGBA metatile atlases and used door animation atlases; it does not yet emit tileset animation records.",
    "Generated overworld import summary currently reports tileset_animation_count = 0 and tileset_animation_callbacks coverage at 0 percent.",
    "MapRuntime/DebugMapPlane draw static generated metatile atlases plus first-pass door overlays, not source-timed dynamic tile copy regions.",
    "The new trace report is data/metadata only and is meant to drive the future Godot-native animated-tile renderer.",
]

UNSUPPORTED = [
    {
        "code": "tileset_animation_runtime_pending",
        "status": "unsupported",
        "source": "src/tileset_anims.c:UpdateTilesetAnimations/TransferTilesetAnimsBuffer",
        "detail": "Godot does not yet run source-equivalent per-frame primary/secondary tileset animation callbacks.",
    },
    {
        "code": "animated_tile_atlas_import_pending",
        "status": "unsupported",
        "source": "src/tileset_anims.c:INCBIN_U16 animation frame declarations",
        "detail": "Animation frame tile blobs are traced but not yet converted into Godot-friendly frame atlases or TileSet animations.",
    },
    {
        "code": "tile_copy_region_renderer_pending",
        "status": "unsupported",
        "source": "src/tileset_anims.c:AppendTilesetAnimToBuffer + BG_VRAM destinations",
        "detail": "Source tile-copy destinations/sizes are metadata only; no Godot renderer remaps visible metatile textures by those tile regions yet.",
    },
    {
        "code": "primary_secondary_counter_runtime_pending",
        "status": "unsupported",
        "source": "src/tileset_anims.c:sPrimaryTilesetAnimCounter/sSecondaryTilesetAnimCounter",
        "detail": "Primary and secondary counters, wrap intervals, and callback interleave order are not yet represented by a runtime scheduler.",
    },
    {
        "code": "battle_dome_palette_animation_pending",
        "status": "unsupported",
        "source": "src/tileset_anims.c:BlendAnimPalette_BattleDome_FloorLights",
        "detail": "Battle Dome palette cycling is traced but not implemented through a Godot material/shader/color-track path.",
    },
    {
        "code": "frlg_tileset_animation_metadata_only",
        "status": "metadata_only",
        "source": "src/tileset_anims.c:#if IS_FRLG-style callbacks and headers.h #else branch",
        "detail": "FRLG callback bindings, frame sources, and copy regions are recorded for reference but are not active Emerald runtime data for this port slice.",
    },
    {
        "code": "gba_vram_dma_godot_native",
        "status": "metadata_only",
        "source": "include/gba/defines.h + include/gba/macro.h",
        "detail": "BG_VRAM, TILE_OFFSET_4BPP, DmaCopy16, CpuCopy16, and CpuFill32 are source trace metadata only; Godot should use normal resources/textures rather than recreating GBA hardware limits.",
    },
    {
        "code": "palette_bank_runtime_godot_native",
        "status": "metadata_only",
        "source": "include/palette.h + src/tileset_anims.c",
        "detail": "Palette-slot writes are preserved as metadata; visible tint/cycle/blend effects should be implemented with Godot-native materials, shaders, animations, or generated resources.",
    },
    {
        "code": "audio_playback_metadata_only",
        "status": "metadata_only",
        "source": "project-wide audio scope",
        "detail": "This tileset-animation trace has no direct sound playback; any later linked field effects must keep sound/music/fanfare symbols metadata_only until audio scope is reopened.",
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


def normalize_ws(value):
    return re.sub(r"\s+", " ", value.strip())


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


def strip_c_comments(text):
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"//.*", "", text)


def extract_function_body(text, function_name):
    match = re.search(r"\b%s\s*\([^)]*\)\s*\{" % re.escape(function_name), text)
    if not match:
        return ""
    start = match.end() - 1
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


def find_calls(text, function_name):
    calls = []
    marker = function_name + "("
    offset = 0
    while True:
        start = text.find(marker, offset)
        if start < 0:
            break
        args_start = start + len(marker)
        depth = 1
        index = args_start
        while index < len(text) and depth > 0:
            char = text[index]
            if char == "(":
                depth += 1
            elif char == ")":
                depth -= 1
            index += 1
        if depth == 0:
            calls.append(text[args_start:index - 1])
            offset = index
        else:
            break
    return calls


def split_top_level_args(value):
    args = []
    depth = 0
    start = 0
    for index, char in enumerate(value):
        if char in "([{":
            depth += 1
        elif char in ")]}":
            depth -= 1
        elif char == "," and depth == 0:
            args.append(value[start:index].strip())
            start = index + 1
    args.append(value[start:].strip())
    return args


def parse_assignment(body, variable):
    match = re.search(r"\b%s\s*=\s*([^;]+);" % re.escape(variable), body)
    return normalize_ws(match.group(1)) if match else ""


def parse_init_functions(tileset_text):
    rows = []
    for name in sorted(set(re.findall(r"\bvoid\s+(InitTilesetAnim_[A-Za-z0-9_]+)\s*\(", tileset_text))):
        body = extract_function_body(tileset_text, name)
        target = "secondary" if re.search(r"\bsSecondaryTilesetAnim(?:Counter|CounterMax|Callback)\s*=", body) else "primary"
        counter_prefix = "sPrimary" if target == "primary" else "sSecondary"
        callback_expr = parse_assignment(body, "%sTilesetAnimCallback" % counter_prefix)
        rows.append({
            "function": name,
            "branch": "frlg_metadata" if name in FRLG_INIT_FUNCTIONS else "emerald",
            "target": target,
            "counter_init_expr": parse_assignment(body, "%sTilesetAnimCounter" % counter_prefix),
            "counter_max_expr": parse_assignment(body, "%sTilesetAnimCounterMax" % counter_prefix),
            "callback": callback_expr,
            "runtime_callback_enabled": callback_expr not in ("", "NULL"),
        })
    return rows


def parse_frame_declarations(tileset_text):
    rows = []
    pattern = re.compile(
        r"(?:static\s+)?const\s+u16\s+((?:g|s)TilesetAnims_[A-Za-z0-9_]+)\[\]\s*=\s*INCBIN_U16\((.*?)\);"
    )
    for match in pattern.finditer(tileset_text):
        source_bins = re.findall(r'"([^"]+)"', match.group(2))
        rows.append({
            "symbol": match.group(1),
            "source_bins": source_bins,
            "source_bin_count": len(source_bins),
        })
    return rows


def parse_pointer_tables(tileset_text):
    rows = []
    pattern = re.compile(
        r"(?:static\s+)?const\s+u16\s+\*const\s+((?:g|s)TilesetAnims_[A-Za-z0-9_]+)\[\]\s*=\s*\{(.*?)\};",
        re.S,
    )
    for match in pattern.finditer(tileset_text):
        raw_items = split_top_level_args(match.group(2).replace("\n", " "))
        items = [item.strip() for item in raw_items if item.strip()]
        rows.append({
            "symbol": match.group(1),
            "item_count": len(items),
            "items": items,
        })
    return rows


def parse_queue_functions(tileset_text):
    queue_names = sorted(set(re.findall(r"\bstatic\s+void\s+(QueueAnimTiles_[A-Za-z0-9_]+)\s*\(", tileset_text)))
    rows = []
    for name in queue_names:
        body = extract_function_body(tileset_text, name)
        append_rows = []
        for call in find_calls(body, "AppendTilesetAnimToBuffer"):
            args = split_top_level_args(call)
            if len(args) != 3:
                continue
            dest_expr = normalize_ws(args[1])
            tile_match = re.search(r"TILE_OFFSET_4BPP\((.*)\)", dest_expr)
            destination_tile_expr = normalize_ws(tile_match.group(1)) if tile_match else ""
            while destination_tile_expr.endswith(")") and destination_tile_expr.count("(") < destination_tile_expr.count(")"):
                destination_tile_expr = destination_tile_expr[:-1].rstrip()
            append_rows.append({
                "frame_source": normalize_ws(args[0]),
                "destination": dest_expr,
                "destination_tile_expr": destination_tile_expr,
                "size_expr": normalize_ws(args[2]),
            })
        rows.append({
            "function": name,
            "append_count": len(append_rows),
            "append_calls": append_rows,
        })
    return rows


def parse_palette_functions(tileset_text):
    rows = []
    for name in sorted(set(re.findall(r"\bstatic\s+void\s+(BlendAnimPalette_[A-Za-z0-9_]+)\s*\(", tileset_text))):
        body = extract_function_body(tileset_text, name)
        rows.append({
            "function": name,
            "cpu_copy_calls": [normalize_ws(call) for call in find_calls(body, "CpuCopy16")],
            "blend_palette_calls": [normalize_ws(call) for call in find_calls(body, "BlendPalette")],
            "find_task_id_calls": [normalize_ws(call) for call in find_calls(body, "FindTaskIdByFunc")],
            "switches_callback": "sSecondaryTilesetAnimCallback" in body,
            "changes_counter_max": "sSecondaryTilesetAnimCounterMax" in body,
        })
    return rows


def parse_tileset_callbacks(tileset_text):
    rows = []
    callback_names = sorted(set(re.findall(r"\bstatic\s+void\s+(TilesetAnim_[A-Za-z0-9_]+)\s*\(", tileset_text)))
    call_pattern = re.compile(r"\b((?:QueueAnimTiles|BlendAnimPalette)_[A-Za-z0-9_]+)\s*\(([^;]*)\)")
    for name in callback_names:
        body = extract_function_body(tileset_text, name)
        calls = []
        last_condition = ""
        for raw_line in body.splitlines():
            line = normalize_ws(raw_line)
            if line.startswith("if "):
                last_condition = line
            for match in call_pattern.finditer(line):
                condition = last_condition
                modulus = None
                equals = None
                timer_match = re.search(r"timer\s*%\s*(\d+)\s*==\s*(\d+)", condition)
                if timer_match:
                    modulus = int(timer_match.group(1))
                    equals = int(timer_match.group(2))
                calls.append({
                    "function": match.group(1),
                    "args": normalize_ws(match.group(2)),
                    "condition": condition,
                    "timer_modulus": modulus,
                    "timer_equals": equals,
                })
        rows.append({
            "function": name,
            "branch": "frlg_metadata" if name.endswith("_Frlg") or name in {
                "TilesetAnim_CeladonCity",
                "TilesetAnim_VermilionGym",
                "TilesetAnim_CeladonGym",
                "TilesetAnim_SilphCo",
                "TilesetAnim_MtEmber",
            } else "emerald",
            "call_count": len(calls),
            "calls": calls,
        })
    return rows


def parse_tileset_header_bindings(headers_text):
    sections = split_header_sections(headers_text)
    result = {}
    for branch, section in sections.items():
        rows = []
        for match in re.finditer(r"const\s+struct\s+Tileset\s+(gTileset_[A-Za-z0-9_]+)\s*=\s*\{(.*?)\};", section, re.S):
            body = match.group(2)
            callback = _field_expr(body, "callback") or "NULL"
            rows.append({
                "tileset": match.group(1),
                "is_secondary": _field_expr(body, "isSecondary"),
                "tiles": _field_expr(body, "tiles"),
                "palettes": _field_expr(body, "palettes"),
                "metatiles": _field_expr(body, "metatiles"),
                "metatile_attributes": _field_expr(body, "metatileAttributes"),
                "callback": callback,
                "has_callback": callback != "NULL",
            })
        result[branch] = rows
    active_emerald_rows = result.get("preprocessor_shared", []) + result.get("emerald_active", [])
    result["active_emerald"] = active_emerald_rows
    return result


def split_header_sections(text):
    start = text.find("#if !IS_FRLG")
    else_index = text.find("#else", start) if start >= 0 else -1
    endif = text.find("#endif", else_index) if else_index >= 0 else -1
    if start < 0 or else_index < 0 or endif < 0:
        return {"active_emerald": text, "frlg_metadata": "", "preprocessor_shared": ""}
    return {
        "preprocessor_shared": text[:start],
        "emerald_active": text[start + len("#if !IS_FRLG"):else_index],
        "frlg_metadata": text[else_index + len("#else"):endif],
    }


def _field_expr(body, field_name):
    match = re.search(r"\.%s\s*=\s*([^,]+)" % re.escape(field_name), body)
    return normalize_ws(match.group(1)) if match else ""


def source_flow_rows():
    return [
        {
            "id": "tileset_header_callback_binding",
            "source_entry": "src/data/tilesets/headers.h:struct Tileset .callback",
            "status": "metadata_only",
            "critical_order": TILESET_CALLBACK_FLOW_RULES,
            "godot_current": [
                "Generated tileset JSON records primary/secondary source tileset symbols.",
                "No generated runtime callback binding table exists yet.",
            ],
            "gaps": [
                "A Godot tileset animation registry must map current primary/secondary tileset symbols to generated callback schedules.",
            ],
        },
        {
            "id": "init_primary_secondary_callbacks",
            "source_entry": "src/tileset_anims.c:InitTilesetAnimations/_InitPrimaryTilesetAnimation/_InitSecondaryTilesetAnimation",
            "status": "unsupported",
            "critical_order": [
                "ResetTilesetAnimBuffer",
                "_InitPrimaryTilesetAnimation clears primary counter/max/callback",
                "Call primary tileset callback if gMapHeader.mapLayout->primaryTileset->callback is not NULL",
                "_InitSecondaryTilesetAnimation clears secondary counter/max/callback",
                "Call secondary tileset callback if gMapHeader.mapLayout->secondaryTileset->callback is not NULL",
            ],
            "godot_current": [
                "MapRuntime configures generated maps and tilesets, but no tileset animation counters are created.",
            ],
            "gaps": [
                "Primary/secondary callback lifecycle must be represented as Godot-native animation state.",
            ],
        },
        {
            "id": "per_frame_counter_and_callback_order",
            "source_entry": "src/tileset_anims.c:UpdateTilesetAnimations",
            "status": "unsupported",
            "critical_order": COUNTER_AND_TRANSFER_RULES[:3],
            "godot_current": [
                "No current Godot per-frame tileset animation scheduler exists.",
            ],
            "gaps": [
                "Counter wrap, callback ordering, and the 20-transfer cap must be preserved or explicitly deviated.",
            ],
        },
        {
            "id": "transfer_buffer_and_vblank_copy",
            "source_entry": "src/tileset_anims.c:AppendTilesetAnimToBuffer/TransferTilesetAnimsBuffer",
            "status": "metadata_only",
            "critical_order": COUNTER_AND_TRANSFER_RULES[3:],
            "godot_current": [
                "Godot uses palette-baked atlases and does not expose BG_VRAM.",
            ],
            "gaps": [
                "Tile destination ranges need translation into generated atlas regions or renderer animation channels.",
            ],
        },
        {
            "id": "map_load_and_secondary_reload_hooks",
            "source_entry": "src/overworld.c + src/fieldmap.c",
            "status": "metadata_only",
            "critical_order": MAP_LOAD_RULES,
            "godot_current": [
                "EventManager/MapRuntime can switch generated maps; tileset animation hooks are still debug metadata.",
            ],
            "gaps": [
                "InitTilesetAnimations/InitSecondaryTilesetAnimation lifecycle integration is pending.",
            ],
        },
        {
            "id": "emerald_tile_copy_callbacks",
            "source_entry": "src/tileset_anims.c:TilesetAnim_* and QueueAnimTiles_*",
            "status": "metadata_only",
            "critical_order": [
                "General primary updates flower/water/edge/waterfall regions on timer % 16 phases 0..4.",
                "Building primary updates TV tiles on timer % 8 phase 0.",
                "Secondary Emerald callbacks cover town water, flowers, lava, flags, seaweed, gym gates/lights, pyramid torch/shadow, and similar tile regions.",
                "Several callbacks use NUM_TILES_IN_PRIMARY plus secondary-local offsets, so Godot translation must respect primary-vs-secondary tile origin.",
            ],
            "godot_current": [
                "Generated first-slice maps using General/Petalburg have static tileset atlases only.",
            ],
            "gaps": [
                "General/Petalburg visible animations are the first likely runtime target after this trace.",
            ],
        },
        {
            "id": "battle_dome_palette_animation",
            "source_entry": "src/tileset_anims.c:BlendAnimPalette_BattleDome_FloorLights",
            "status": "unsupported",
            "critical_order": PALETTE_EFFECT_RULES,
            "godot_current": [
                "No current overworld material/shader path handles palette cycling.",
            ],
            "gaps": [
                "Palette changes should become Godot-native visual effects, not runtime GBA palette banks.",
            ],
        },
        {
            "id": "frlg_tileset_animation_branch",
            "source_entry": "src/tileset_anims.c:InitTilesetAnim_*_Frlg and headers.h #else",
            "status": "metadata_only",
            "critical_order": [
                "General_Frlg runs a 640-frame primary counter and different water/flower phases.",
                "Celadon/Vermilion/CeladonGym/SilphCo/MtEmber callbacks bind only in the FRLG headers branch.",
                "These rows are not active for the current Emerald target but should stay traceable.",
            ],
            "godot_current": [
                "Current import summary treats Emerald IS_FRLG = false as active.",
            ],
            "gaps": [
                "FRLG branch playback stays metadata-only unless the project adds an FRLG target mode.",
            ],
        },
        {
            "id": "godot_current_tileset_animation_gap",
            "source_entry": "data/generated/overworld/import_summary.json",
            "status": "first_pass",
            "critical_order": GODOT_CURRENT_RULES,
            "godot_current": [
                "This trace report becomes the first machine-readable source coverage for tileset animation callbacks.",
            ],
            "gaps": [
                "Runtime animation records and presentation playback are still future work.",
            ],
        },
        {
            "id": "visual_effect_policy_for_godot",
            "source_entry": "project skill front-loaded porting constraints",
            "status": "metadata_only",
            "critical_order": [
                "Palette/tint/blend/affine-style visible effects should be Godot-native while preserving source timing and visible rhythm.",
                "GBA palette-bank, VRAM, OAM, and DMA constraints should not become runtime limits.",
                "Audio remains metadata_only/unsupported unless the scope is explicitly reopened.",
            ],
            "godot_current": [
                "Door animations already use generated RGBA atlases rather than runtime GBA VRAM slots.",
            ],
            "gaps": [
                "Future dynamic-tile and palette effects must carry explicit unsupported/deviation metadata when approximate.",
            ],
        },
    ]


def current_godot_tileset_anim_summary():
    summary_path = REPO_ROOT / "data" / "generated" / "overworld" / "import_summary.json"
    generated_counts = {}
    coverage = {}
    unsupported = []
    if summary_path.exists():
        try:
            data = json.loads(summary_path.read_text(encoding="utf-8"))
            generated_counts = data.get("generated_counts", {})
            coverage = data.get("coverage", {})
            unsupported = data.get("unsupported", [])
        except json.JSONDecodeError:
            generated_counts = {}
            coverage = {}
            unsupported = []

    tileset_records = []
    tileset_dir = REPO_ROOT / "data" / "generated" / "tilesets"
    if tileset_dir.exists():
        for path in sorted(tileset_dir.glob("*.json")):
            try:
                data = json.loads(path.read_text(encoding="utf-8"))
            except json.JSONDecodeError:
                continue
            source = data.get("source", {}) if isinstance(data.get("source", {}), dict) else {}
            tilesets = data.get("tilesets", {}) if isinstance(data.get("tilesets", {}), dict) else {}
            primary = tilesets.get("primary", {}) if isinstance(tilesets.get("primary", {}), dict) else {}
            secondary = tilesets.get("secondary", {}) if isinstance(tilesets.get("secondary", {}), dict) else {}
            tileset_records.append({
                "path": to_project_path(path.relative_to(REPO_ROOT)),
                "map": source.get("map_folder", data.get("map", data.get("name", ""))),
                "primary_tileset": primary.get("symbol", data.get("primary_tileset", "")),
                "secondary_tileset": secondary.get("symbol", data.get("secondary_tileset", "")),
                "door_animation_count": len(data.get("door_animations", {}).get("animations", []))
                if isinstance(data.get("door_animations", {}), dict)
                else 0,
                "tileset_animation_count": len(data.get("tileset_animations", []))
                if isinstance(data.get("tileset_animations", []), list)
                else 0,
            })

    return {
        "import_summary_path": to_project_path(summary_path.relative_to(REPO_ROOT)) if summary_path.exists() else "",
        "generated_tileset_animation_count": generated_counts.get("tileset_animation_count", 0),
        "source_tileset_animation_callback_count": coverage.get("tileset_animation_callbacks", {}).get("source"),
        "tileset_animation_callback_coverage_percent": coverage.get("tileset_animation_callbacks", {}).get("percent"),
        "summary_unsupported_tileset_animation": [
            entry for entry in unsupported if entry.get("code") == "tileset_animation_runtime_pending"
        ],
        "generated_tileset_records": tileset_records,
    }


def build_stats(presence, locations, init_rows, frame_rows, pointer_rows, queue_rows, palette_rows, callback_rows, header_bindings, flow_rows):
    missing_symbols = [symbol for symbol, occurrences in locations.items() if not occurrences]
    status_counts = {}
    for row in flow_rows:
        status = row["status"]
        status_counts[status] = status_counts.get(status, 0) + 1
    unsupported_status_counts = {}
    for row in UNSUPPORTED:
        status = row["status"]
        unsupported_status_counts[status] = unsupported_status_counts.get(status, 0) + 1

    active_emerald_headers = header_bindings.get("active_emerald", [])
    frlg_headers = header_bindings.get("frlg_metadata", [])
    emerald_non_null = [row for row in active_emerald_headers if row["has_callback"]]
    frlg_non_null = [row for row in frlg_headers if row["has_callback"]]
    append_count = sum(row["append_count"] for row in queue_rows)

    return {
        "flow_count": len(flow_rows),
        "source_file_count": len(SOURCE_FILES),
        "missing_source_file_count": sum(1 for item in presence if not item["exists"]),
        "required_symbol_count": len(REQUIRED_SYMBOLS),
        "missing_symbol_count": len(missing_symbols),
        "missing_symbols": missing_symbols,
        "status_counts": status_counts,
        "unsupported_count": len(UNSUPPORTED),
        "unsupported_status_counts": unsupported_status_counts,
        "init_function_count": len(init_rows),
        "emerald_init_function_count": sum(1 for row in init_rows if row["branch"] == "emerald"),
        "frlg_init_function_count": sum(1 for row in init_rows if row["branch"] == "frlg_metadata"),
        "runtime_enabled_init_function_count": sum(1 for row in init_rows if row["runtime_callback_enabled"]),
        "null_callback_init_function_count": sum(1 for row in init_rows if not row["runtime_callback_enabled"]),
        "frame_declaration_count": len(frame_rows),
        "frame_source_bin_count": sum(row["source_bin_count"] for row in frame_rows),
        "pointer_table_count": len(pointer_rows),
        "queue_function_count": len(queue_rows),
        "append_call_count": append_count,
        "palette_function_count": len(palette_rows),
        "tileset_callback_function_count": len(callback_rows),
        "active_emerald_header_count": len(active_emerald_headers),
        "active_emerald_header_callback_count": len(emerald_non_null),
        "frlg_header_count": len(frlg_headers),
        "frlg_header_callback_count": len(frlg_non_null),
        "header_callback_symbol_count_all_branches": len({
            row["callback"]
            for branch_rows in header_bindings.values()
            for row in branch_rows
            if isinstance(row, dict) and row.get("has_callback")
        }),
    }


def manifest_entry_for(exported, output_path):
    stats = exported["stats"]
    return {
        "category": "overworld_tileset_anim_trace",
        "path": to_project_path(output_path),
        "source_file_count": stats["source_file_count"],
        "flow_count": stats["flow_count"],
        "init_function_count": stats["init_function_count"],
        "tileset_callback_function_count": stats["tileset_callback_function_count"],
        "queue_function_count": stats["queue_function_count"],
        "append_call_count": stats["append_call_count"],
        "frame_declaration_count": stats["frame_declaration_count"],
        "frame_source_bin_count": stats["frame_source_bin_count"],
        "active_emerald_header_callback_count": stats["active_emerald_header_callback_count"],
        "unsupported_count": stats["unsupported_count"],
    }


def build_export(source_root):
    source_root = Path(source_root)
    tileset_text = read_text(source_root / "src/tileset_anims.c")
    headers_text = read_text(source_root / "src/data/tilesets/headers.h")
    presence = source_file_presence(source_root)
    locations = symbol_locations(source_root)
    init_rows = parse_init_functions(tileset_text)
    frame_rows = parse_frame_declarations(tileset_text)
    pointer_rows = parse_pointer_tables(tileset_text)
    queue_rows = parse_queue_functions(tileset_text)
    palette_rows = parse_palette_functions(tileset_text)
    callback_rows = parse_tileset_callbacks(tileset_text)
    header_bindings = parse_tileset_header_bindings(headers_text)
    flow_rows = source_flow_rows()
    stats = build_stats(
        presence,
        locations,
        init_rows,
        frame_rows,
        pointer_rows,
        queue_rows,
        palette_rows,
        callback_rows,
        header_bindings,
        flow_rows,
    )

    return {
        "schema_version": 1,
        "generated_by": GENERATED_BY,
        "source_root": str(source_root),
        "source_files": presence,
        "required_symbols": locations,
        "init_functions": init_rows,
        "tileset_header_bindings": header_bindings,
        "tileset_animation_frame_declarations": frame_rows,
        "tileset_animation_pointer_tables": pointer_rows,
        "queue_functions": queue_rows,
        "palette_functions": palette_rows,
        "tileset_callbacks": callback_rows,
        "tileset_callback_flow_rules": TILESET_CALLBACK_FLOW_RULES,
        "counter_and_transfer_rules": COUNTER_AND_TRANSFER_RULES,
        "map_load_rules": MAP_LOAD_RULES,
        "palette_effect_rules": PALETTE_EFFECT_RULES,
        "source_flows": flow_rows,
        "godot_current": current_godot_tileset_anim_summary(),
        "godot_trace_owners": {
            "importer": [
                "tools/importer/export_tilesets.py",
                GENERATED_BY,
            ],
            "runtime": [
                "scripts/autoload/map_runtime.gd",
                "scripts/overworld/debug_map_plane.gd",
            ],
            "presentation": [
                "scripts/overworld/debug_map_plane.gd",
                "scripts/overworld/transition_sequence_player.gd",
            ],
            "generated_data": [
                "data/generated/tilesets/*.json",
                "data/generated/overworld/import_summary.json",
                "data/generated/overworld/tileset_anim_trace.json",
            ],
            "tests": [
                "tools/importer/export_overworld_tileset_anim_trace_smoke.py",
            ],
        },
        "visual_effect_policy": {
            "palette_and_affine": "Use Godot-native textures, materials, shaders, animation tracks, resources, and renderer state for palette, tint, scale, rotation, affine, and animation effects while preserving source timing, ordering, rhythm, and visible result where practical.",
            "gba_runtime_limits": "Do not recreate GBA palette-bank, VRAM, OAM, DMA, or binary tile memory limits at runtime unless a gameplay rule explicitly depends on them.",
            "audio": "Audio playback remains out of scope; sound/music/fanfare symbols and timing intent stay metadata_only/unsupported until audio scope is reopened.",
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

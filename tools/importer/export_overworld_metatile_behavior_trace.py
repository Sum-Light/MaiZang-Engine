#!/usr/bin/env python3
"""Export source-traced overworld metatile-behavior coverage."""

import argparse
import json
import re
import sys
from pathlib import Path

from export_map import write_json, write_manifest
from source_probe import load_config, to_project_path


GENERATED_BY = "tools/importer/export_overworld_metatile_behavior_trace.py"
REPORT_PATH = Path("overworld/metatile_behavior_trace.json")
REPO_ROOT = Path(__file__).resolve().parents[2]

SOURCE_FILES = [
    "include/constants/metatile_behaviors.h",
    "include/metatile_behavior.h",
    "src/metatile_behavior.c",
    "include/overworld.h",
    "src/overworld.c",
    "include/constants/global.h",
    "include/global.fieldmap.h",
    "src/field_control_avatar.c",
    "src/field_player_avatar.c",
    "src/event_object_movement.c",
    "src/field_tasks.c",
    "src/bike.c",
    "src/decoration.c",
    "src/field_screen_effect.c",
    "src/battle_setup.c",
    "src/dexnav.c",
    "src/field_effect_helpers.c",
    "src/field_effect.c",
    "src/fldeff_cut.c",
    "src/secret_base.c",
    "src/item_use.c",
    "src/wild_encounter.c",
    "src/follower_npc.c",
    "src/field_door.c",
    "src/fldeff_misc.c",
    "src/party_menu.c",
    "src/faraway_island.c",
    "src/field_specials.c",
    "src/fishing.c",
]

REQUIRED_SYMBOLS = [
    "MB_NORMAL",
    "MB_TALL_GRASS",
    "MB_LONG_GRASS",
    "MB_CYCLING_ROAD_PULL_DOWN_GRASS",
    "MB_POND_WATER",
    "MB_OCEAN_WATER",
    "MB_WATERFALL",
    "MB_ANIMATED_DOOR",
    "MB_NON_ANIMATED_DOOR",
    "MB_WATER_DOOR",
    "MB_DEEP_SOUTH_WARP",
    "MB_BRIDGE_OVER_OCEAN",
    "MB_BRIDGE_OVER_POND_HIGH_EDGE_2",
    "MB_BIKE_BRIDGE_OVER_BARRIER",
    "MB_SECRET_BASE_JUMP_MAT",
    "MB_SECRET_BASE_SPIN_MAT",
    "MB_SECRET_BASE_BREAKABLE_DOOR",
    "MB_MUDDY_SLOPE",
    "MB_CRACKED_FLOOR",
    "MB_ROCK_CLIMB",
    "NUM_METATILE_BEHAVIORS",
    "MB_INVALID",
    "TILE_FLAG_HAS_ENCOUNTERS",
    "TILE_FLAG_SURFABLE",
    "TILE_FLAG_UNUSED",
    "sTileBitAttributes",
    "MetatileBehavior_IsEncounterTile",
    "MetatileBehavior_IsSurfableWaterOrUnderwater",
    "MetatileBehavior_IsLandWildEncounter",
    "MetatileBehavior_IsWaterWildEncounter",
    "MetatileBehavior_IsPokeGrass",
    "MetatileBehavior_IsTallGrass",
    "MetatileBehavior_IsLongGrass",
    "MetatileBehavior_IsSandOrDeepSand",
    "MetatileBehavior_IsBridgeOverWater",
    "MetatileBehavior_GetBridgeType",
    "MetatileBehavior_IsBridgeOverWaterNoEdge",
    "MetatileBehavior_IsDiveable",
    "MetatileBehavior_IsUnableToEmerge",
    "MetatileBehavior_IsForcedMovementTile",
    "MetatileBehavior_IsEastBlocked",
    "MetatileBehavior_IsWestBlocked",
    "MetatileBehavior_IsNorthBlocked",
    "MetatileBehavior_IsSouthBlocked",
    "MetatileBehavior_IsWarpDoor",
    "MetatileBehavior_IsDoor",
    "MetatileBehavior_IsNonAnimDoor",
    "MetatileBehavior_IsDirectionalStairWarp",
    "MetatileBehavior_IsSurfableFishableWater",
    "MetatileBehavior_IsRunningDisallowed",
    "MetatileBehavior_IsCuttableGrass",
    "MetatileBehavior_IsPlayerFacingTVScreen",
    "MetatileBehavior_IsPlayerFacingCableClubWirelessMonitor",
    "MetatileBehavior_IsPlayerFacingBattleRecords",
    "MetatileBehavior_IsRockClimbable",
    "MetatileBehavior_IsSpinTile",
    "MetatileBehavior_IsSurfableInSeafoamIslands",
    "BRIDGE_TYPE_OCEAN",
    "BRIDGE_TYPE_POND_MED",
    "BRIDGE_TYPE_POND_HIGH",
    "DIR_NORTH",
    "CONNECTION_NORTH",
    "PLAYER_AVATAR_FLAG_SURFING",
    "MAP_SEAFOAM_ISLANDS_B3F",
    "MAP_SEAFOAM_ISLANDS_B4F",
    "BUGFIX",
    "StandardWildEncounter",
    "ProcessPlayerFieldInput",
]

CORE_HELPERS = [
    "MetatileBehavior_IsEncounterTile",
    "MetatileBehavior_IsSurfableWaterOrUnderwater",
    "MetatileBehavior_IsLandWildEncounter",
    "MetatileBehavior_IsWaterWildEncounter",
    "MetatileBehavior_IsForcedMovementTile",
    "MetatileBehavior_IsDoor",
    "MetatileBehavior_IsNonAnimDoor",
    "MetatileBehavior_IsDirectionalStairWarp",
    "MetatileBehavior_IsBridgeOverWater",
    "MetatileBehavior_GetBridgeType",
    "MetatileBehavior_IsSurfableInSeafoamIslands",
]

UNSUPPORTED = [
    {
        "code": "metatile_behavior_runtime_table_pending",
        "status": "unsupported",
        "source": "src/metatile_behavior.c:MetatileBehavior_Is*",
        "detail": "Godot does not yet expose a generated runtime helper table for every source MetatileBehavior_Is* predicate.",
    },
    {
        "code": "directional_blocking_runtime_pending",
        "status": "unsupported",
        "source": "src/metatile_behavior.c:MetatileBehavior_IsEastBlocked/WestBlocked/NorthBlocked/SouthBlocked",
        "detail": "MapRuntime.can_enter_cell still uses first-pass map collision plus object occupancy, not source directional metatile behavior.",
    },
    {
        "code": "forced_movement_runtime_pending",
        "status": "unsupported",
        "source": "src/metatile_behavior.c:MetatileBehavior_IsForcedMovementTile + src/field_player_avatar.c",
        "detail": "Walk/slide/current/spin/ice/waterfall/slope/cracked-floor forced movement is traced but not driven by a source-equivalent movement task queue.",
    },
    {
        "code": "terrain_field_effect_runtime_pending",
        "status": "unsupported",
        "source": "src/metatile_behavior.c grass/water/ripple/sand/ash/ice/slope helpers",
        "detail": "Terrain visual effects and step presentation remain future runtime/presentation work.",
    },
    {
        "code": "interaction_helper_table_pending",
        "status": "unsupported",
        "source": "src/metatile_behavior.c TV/PC/sign/furniture/secret-base helpers",
        "detail": "Interaction helpers are not yet generated into a source-backed Godot lookup table.",
    },
    {
        "code": "bridge_elevation_runtime_pending",
        "status": "unsupported",
        "source": "src/metatile_behavior.c:MetatileBehavior_IsBridgeOverWater/GetBridgeType",
        "detail": "Bridge water/elevation semantics are trace metadata only; MapRuntime elevation handling is still first-pass.",
    },
    {
        "code": "bugfix_branch_metadata_only",
        "status": "metadata_only",
        "source": "src/metatile_behavior.c:MetatileBehavior_IsUnableToEmerge #ifdef BUGFIX",
        "detail": "The BUGFIX-gated WATER_DOOR no-emerge behavior is recorded as source metadata until project config branch selection is centralized.",
    },
    {
        "code": "seafoam_external_helper_split_metadata",
        "status": "metadata_only",
        "source": "src/overworld.c:MetatileBehavior_IsSurfableInSeafoamIslands",
        "detail": "The Seafoam surfability helper lives outside metatile_behavior.c and must stay in the generated trace set.",
    },
    {
        "code": "palette_affine_effects_godot_native",
        "status": "metadata_only",
        "source": "project porting policy",
        "detail": "Any visible palette, tint, scale, rotation, or affine-style behavior triggered by metatile effects should be Godot-native while preserving source timing and visible rhythm.",
    },
    {
        "code": "gba_runtime_limits_not_recreated",
        "status": "metadata_only",
        "source": "project porting policy",
        "detail": "GBA palette-bank, VRAM, OAM, and packed tile-map limits are import/source metadata only unless gameplay depends on them.",
    },
    {
        "code": "audio_playback_metadata_only",
        "status": "metadata_only",
        "source": "project-wide audio scope",
        "detail": "Sound/music/fanfare symbols related to future metatile effects remain metadata_only/unsupported until audio scope is reopened.",
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


def strip_c_comments(text):
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"//.*", "", text)


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


def extract_function_body(text, function_name):
    match = re.search(r"\b%s\s*\([^;{}]*\)\s*(?:(?://[^\n]*)|(?:/\*.*?\*/))?\s*\{" % re.escape(function_name), text, re.S)
    if not match:
        return ""
    return extract_braced_body(text, match.end() - 1)


def extract_braced_body(text, brace_index):
    depth = 0
    for index in range(brace_index, len(text)):
        char = text[index]
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return text[brace_index + 1:index]
    return ""


def parse_metatile_constants(header_text):
    body_match = re.search(r"enum\s*\{(.*?)NUM_METATILE_BEHAVIORS", header_text, re.S)
    body = body_match.group(1) if body_match else ""
    constants = []
    next_value = 0
    for line_number, raw_line in enumerate(header_text.splitlines(), start=1):
        if "NUM_METATILE_BEHAVIORS" in raw_line:
            break
        line = raw_line.split("//", 1)[0].strip().rstrip(",")
        if not line.startswith("MB_"):
            continue
        if "=" in line:
            name, value_expr = [part.strip() for part in line.split("=", 1)]
            try:
                next_value = int(value_expr, 0)
            except ValueError:
                pass
        else:
            name = line.strip()
        if name == "MB_INVALID":
            continue
        constants.append({"id": next_value, "name": name, "line": line_number})
        next_value += 1

    num_match = re.search(r"\bNUM_METATILE_BEHAVIORS\b", header_text)
    invalid_match = re.search(r"#define\s+MB_INVALID\s+([^\n]+)", header_text)
    return {
        "source": "include/constants/metatile_behaviors.h",
        "constants": constants,
        "constant_by_name": {row["name"]: row["id"] for row in constants},
        "num_metatile_behaviors_value": len(constants) if num_match else None,
        "mb_invalid_expr": normalize_ws(invalid_match.group(1)) if invalid_match else "",
    }


def parse_header_prototypes(header_text):
    prototypes = {}
    pattern = re.compile(
        r"\b(bool8|bool32|u8)\s+((?:MetatileBehavior|Unref_MetatileBehavior)_[A-Za-z0-9_]+)\s*\(([^;{}]*)\)\s*;"
    )
    for match in pattern.finditer(header_text):
        prototypes[match.group(2)] = {
            "return_type": match.group(1),
            "parameters": normalize_ws(match.group(3)),
        }
    return prototypes


def parse_tile_bit_attributes(source_text, constants):
    cleaned = strip_c_comments(source_text)
    body_match = re.search(r"sTileBitAttributes\s*\[[^\]]+\]\s*=\s*\{(.*?)\};", cleaned, re.S)
    body = body_match.group(1) if body_match else ""
    explicit = {}
    for match in re.finditer(r"\[(MB_[A-Za-z0-9_]+)\]\s*=\s*([^,\n]+)", body):
        name = match.group(1)
        expr = normalize_ws(match.group(2))
        explicit[name] = {
            "behavior": name,
            "behavior_id": constants.get(name),
            "expression": expr,
            "flags": re.findall(r"\bTILE_FLAG_[A-Z0-9_]+\b", expr),
        }

    rows = []
    for name, behavior_id in sorted(constants.items(), key=lambda item: item[1]):
        entry = explicit.get(name, {})
        rows.append({
            "behavior": name,
            "behavior_id": behavior_id,
            "explicit": name in explicit,
            "expression": entry.get("expression", "0"),
            "flags": entry.get("flags", []),
            "has_encounters": "TILE_FLAG_HAS_ENCOUNTERS" in entry.get("flags", []),
            "surfable": "TILE_FLAG_SURFABLE" in entry.get("flags", []),
            "unused_traversable_hint": "TILE_FLAG_UNUSED" in entry.get("flags", []),
        })

    return {
        "source": "src/metatile_behavior.c:sTileBitAttributes",
        "flag_definitions": {
            "TILE_FLAG_HAS_ENCOUNTERS": "1 << 0",
            "TILE_FLAG_SURFABLE": "1 << 1",
            "TILE_FLAG_UNUSED": "1 << 2",
        },
        "explicit_rows": [explicit[name] for name in sorted(explicit, key=lambda key: constants.get(key, 9999))],
        "rows": rows,
        "encounter_behaviors": [row["behavior"] for row in rows if row["has_encounters"]],
        "surfable_behaviors": [row["behavior"] for row in rows if row["surfable"]],
        "unused_hint_behaviors": [row["behavior"] for row in rows if row["unused_traversable_hint"]],
    }


def parse_function_definitions(text, source_file, prototypes):
    rows = []
    pattern = re.compile(
        r"\b(bool8|bool32|u8)(?:\s+[A-Z_][A-Z0-9_]*)*\s+((?:MetatileBehavior|Unref_MetatileBehavior)_[A-Za-z0-9_]+)\s*\(([^;{}]*)\)\s*(?:(?://[^\n]*)|(?:/\*.*?\*/))?\s*\{",
        re.S,
    )
    for match in pattern.finditer(text):
        name = match.group(2)
        body = extract_braced_body(text, match.end() - 1)
        rows.append(_function_record(
            name,
            match.group(1),
            normalize_ws(match.group(3)),
            body,
            source_file,
            text.count("\n", 0, match.start()) + 1,
            prototypes,
        ))
    return rows


def parse_external_helper_definitions(source_root, helper_names, internal_names, prototypes):
    rows = []
    for relative_path in sorted(_source_scan_paths(source_root)):
        if relative_path in ("src/metatile_behavior.c", "include/metatile_behavior.h"):
            continue
        text = read_text(source_root / relative_path)
        for helper_name in sorted(helper_names):
            if helper_name in internal_names:
                continue
            pattern = re.compile(
                r"\b(bool8|bool32|u8|bool32)\s+%s\s*\(([^;{}]*)\)\s*(?:(?://[^\n]*)|(?:/\*.*?\*/))?\s*\{" % re.escape(helper_name),
                re.S,
            )
            match = pattern.search(text)
            if not match:
                continue
            body = extract_braced_body(text, match.end() - 1)
            rows.append(_function_record(
                helper_name,
                match.group(1),
                normalize_ws(match.group(2)),
                body,
                relative_path,
                text.count("\n", 0, match.start()) + 1,
                prototypes,
                external=True,
            ))
    return rows


def _function_record(name, return_type, parameters, body, source_file, line, prototypes, external=False):
    referenced_mb = sorted(set(re.findall(r"\bMB_[A-Za-z0-9_]+\b", body)))
    called_helpers = sorted({
        helper
        for helper in re.findall(r"\b(MetatileBehavior_[A-Za-z0-9_]+)\s*\(", body)
        if helper != name
    })
    return {
        "function": name,
        "source_file": source_file,
        "line": line,
        "return_type": return_type,
        "parameters": parameters,
        "declared_in_header": name in prototypes,
        "external_to_metatile_behavior_c": external,
        "referenced_metatile_behaviors": referenced_mb,
        "range_checks": parse_range_checks(body),
        "called_helpers": called_helpers,
        "tile_flags": sorted(set(re.findall(r"\bTILE_FLAG_[A-Z0-9_]+\b", body))),
        "direction_gates": sorted(set(re.findall(r"\b(?:DIR|CONNECTION)_[A-Z0-9_]+\b", body))),
        "preprocessor_gates": sorted(set(re.findall(r"\b(?:BUGFIX|FREE_MOVE|OW_POISON)\b", body))),
        "categories": classify_helper(name, referenced_mb, body),
        "body_summary": summarize_body(body),
    }


def parse_range_checks(body):
    rows = []
    pattern = re.compile(r"\b([A-Za-z_][A-Za-z0-9_]*)\s*>=\s*(MB_[A-Za-z0-9_]+)\s*&&\s*\1\s*<=\s*(MB_[A-Za-z0-9_]+)")
    for match in pattern.finditer(body):
        rows.append({
            "variable": match.group(1),
            "from": match.group(2),
            "to": match.group(3),
        })
    return rows


def summarize_body(body):
    cleaned = normalize_ws(strip_c_comments(body))
    if len(cleaned) <= 260:
        return cleaned
    return cleaned[:257].rstrip() + "..."


def classify_helper(name, referenced_mb, body):
    haystack = " ".join([name] + referenced_mb)
    categories = []
    rules = [
        ("encounter", ["Encounter", "PokeGrass", "TallGrass", "LongGrass", "Cave", "Mountain"]),
        ("surf_dive_water", ["Surfable", "Water", "Dive", "Emerge", "Seaweed", "Waterfall", "Current"]),
        ("warp_door_transition", ["Warp", "Door", "Escalator", "Ladder", "Arrow", "MOSSDEEP", "LAVARIDGE", "AQUA"]),
        ("forced_movement", ["ForcedMovement", "Walk", "Slide", "Current", "Spin", "Ice", "Muddy", "CrackedFloor"]),
        ("collision_blocking", ["Blocked", "IMPASSABLE", "RunningDisallowed", "BumpySlope", "Rail", "RockClimb"]),
        ("bridge_elevation", ["Bridge", "Fortree", "Pacifidlog", "SidewaysStairs", "RockStairs"]),
        ("terrain_effect", ["Ripples", "Puddle", "Grass", "Sand", "Ash", "Footprints", "HotSprings", "Reflective"]),
        ("interaction", ["PlayerFacing", "PC", "Sign", "TV", "Shelf", "Vase", "Trash", "Poster", "Monitor", "Cable", "BattleRecords"]),
        ("secret_base", ["SecretBase", "Decoration", "Holds", "Balloon", "Glitter", "SoundMat", "SandOrnament"]),
    ]
    for category, tokens in rules:
        if any(token in haystack for token in tokens):
            categories.append(category)
    if "TILE_FLAG_HAS_ENCOUNTERS" in body or "TILE_FLAG_SURFABLE" in body:
        if "encounter" not in categories:
            categories.append("encounter")
    if not categories:
        categories.append("misc")
    return categories


def collect_call_sites(source_root):
    helper_pattern = re.compile(r"\b(MetatileBehavior_[A-Za-z0-9_]+)\s*\(")
    file_rows = []
    helper_counts = {}
    for relative_path in _source_scan_paths(source_root):
        if relative_path in ("src/metatile_behavior.c", "include/metatile_behavior.h"):
            continue
        text = read_text(source_root / relative_path)
        symbols = helper_pattern.findall(strip_c_comments(text))
        if not symbols:
            continue
        unique_symbols = sorted(set(symbols))
        file_rows.append({
            "file": relative_path,
            "call_count": len(symbols),
            "unique_function_count": len(unique_symbols),
            "functions": unique_symbols,
        })
        for symbol in symbols:
            helper_counts.setdefault(symbol, {"symbol": symbol, "call_count": 0, "files": []})
            helper_counts[symbol]["call_count"] += 1
            if relative_path not in helper_counts[symbol]["files"]:
                helper_counts[symbol]["files"].append(relative_path)

    file_rows.sort(key=lambda row: (-row["call_count"], row["file"]))
    helper_rows = sorted(helper_counts.values(), key=lambda row: (-row["call_count"], row["symbol"]))
    return {
        "files": file_rows,
        "helpers": helper_rows,
    }


def _source_scan_paths(source_root):
    paths = []
    for base in ["src", "include"]:
        root = source_root / base
        if not root.exists():
            continue
        for path in root.rglob("*"):
            if path.suffix.lower() not in (".c", ".h"):
                continue
            paths.append(to_project_path(path.relative_to(source_root)))
    return sorted(paths)


def source_flow_rows():
    return [
        {
            "id": "behavior_constants_and_import_ids",
            "source_entry": "include/constants/metatile_behaviors.h",
            "status": "first_pass",
            "critical_order": [
                "MB_NORMAL starts at id 0 and NUM_METATILE_BEHAVIORS follows the last concrete behavior.",
                "export_tilesets.py already imports behavior ids/names into generated metatile attributes.",
                "MB_INVALID is UCHAR_MAX and must stay distinct from any generated behavior id.",
            ],
            "godot_current": [
                "MapRuntime can expose behavior id and behavior_name for a map cell.",
            ],
            "gaps": [
                "Runtime helper predicates are not generated yet.",
            ],
        },
        {
            "id": "tile_bit_attributes",
            "source_entry": "src/metatile_behavior.c:sTileBitAttributes",
            "status": "first_pass",
            "critical_order": [
                "MetatileBehavior_IsEncounterTile reads TILE_FLAG_HAS_ENCOUNTERS.",
                "MetatileBehavior_IsSurfableWaterOrUnderwater reads TILE_FLAG_SURFABLE.",
                "TILE_FLAG_UNUSED is roughly traversable source metadata but is set and not read by the source helper file.",
            ],
            "godot_current": [
                "EncounterEngine carries a hand-maintained first-pass subset of land/water behavior-name sets.",
            ],
            "gaps": [
                "The generated trace should become the canonical source for EncounterEngine and MapRuntime behavior groups.",
            ],
        },
        {
            "id": "encounter_area_classification",
            "source_entry": "src/metatile_behavior.c:IsLandWildEncounter/IsWaterWildEncounter + src/wild_encounter.c",
            "status": "first_pass",
            "critical_order": [
                "Land wild encounters are encounter tiles that are not surfable.",
                "Water wild encounters are tiles that are both surfable and encounter-enabled.",
                "Standard wild encounters also treat bridge-over-water as water only while surfing.",
            ],
            "godot_current": [
                "EncounterEngine can route land/water and surfing bridge behavior names for standard encounter checks.",
            ],
            "gaps": [
                "Broader metatile helper generation should replace duplicated GDScript sets.",
            ],
        },
        {
            "id": "movement_collision_blocking",
            "source_entry": "src/metatile_behavior.c directional blocking helpers + src/field_player_avatar.c",
            "status": "unsupported",
            "critical_order": [
                "Directional impassable helpers are separate for east, west, north, and south.",
                "Secret base breakable doors block east and west helper checks.",
                "Running, biking, rock stairs, rails, bumpy slopes, and rock climb use behavior-specific gates beyond map collision bits.",
            ],
            "godot_current": [
                "MapRuntime.can_enter_cell currently checks bounds, object occupancy, and generated collision only.",
            ],
            "gaps": [
                "Player collision must consume source helper groups and avatar state before being source-equivalent.",
            ],
        },
        {
            "id": "forced_movement_tiles",
            "source_entry": "src/metatile_behavior.c:MetatileBehavior_IsForcedMovementTile",
            "status": "unsupported",
            "critical_order": [
                "Forced movement includes walk/slide ranges, water currents, muddy slope, cracked floor, waterfall, ice, and secret-base jump/spin mats.",
                "Spin direction helpers and STOP_SPINNING are separate from the broad forced movement gate.",
                "Source player-step handling checks forced movement before ordinary keypad movement.",
            ],
            "godot_current": [
                "Player movement is grid-step first-pass and does not chain source forced movement tasks.",
            ],
            "gaps": [
                "A movement scheduler needs behavior-triggered source timing and sprite animation contracts.",
            ],
        },
        {
            "id": "warps_doors_and_transitions",
            "source_entry": "src/metatile_behavior.c door/warp helpers + src/field_screen_effect.c",
            "status": "metadata_only",
            "critical_order": [
                "Animated, non-animated, water, arrow, deep-south, stair, escalator, ladder, gym, hideout, and special warps are distinct behavior helpers.",
                "Door warp presentation already depends on metatile behavior selection before transition playback.",
                "Directional stair warps are a composed helper over four directional stair behavior ids.",
            ],
            "godot_current": [
                "Door transitions have a first-pass generated door overlay path, but the full metatile helper table is not yet a runtime owner.",
            ],
            "gaps": [
                "Non-door metatile transitions need source-backed runtime routing and presentation timing.",
            ],
        },
        {
            "id": "terrain_field_effects",
            "source_entry": "src/metatile_behavior.c terrain helpers",
            "status": "unsupported",
            "critical_order": [
                "Grass, ripples, puddles, sand, ash, footprints, hot springs, ice, seaweed, reflection, and waterfall helpers feed visible field effects.",
                "Visible palette/tint/animation effects should be Godot-native, not GBA palette-bank emulation.",
            ],
            "godot_current": [
                "Terrain effect presentation is not source-equivalent.",
            ],
            "gaps": [
                "Field effect tasks need source timing and generated asset links before visual parity.",
            ],
        },
        {
            "id": "interaction_sign_furniture",
            "source_entry": "src/metatile_behavior.c interaction helpers + src/field_control_avatar.c",
            "status": "metadata_only",
            "critical_order": [
                "TV/monitor helpers gate on facing north.",
                "Wireless and cable box result helpers use CONNECTION_NORTH style facing constants.",
                "PC, shelves, signs, furniture, secret-base objects, and similar helpers are separate source predicates.",
            ],
            "godot_current": [
                "MapRuntime resolves BG/sign events and object interactions, but not a complete metatile interaction helper table.",
            ],
            "gaps": [
                "Script dispatch should use generated helper categories when source interaction code requires metatile predicates.",
            ],
        },
        {
            "id": "bridge_and_elevation_helpers",
            "source_entry": "src/metatile_behavior.c bridge helpers",
            "status": "unsupported",
            "critical_order": [
                "Bridge-over-water edge and no-edge helpers are distinct.",
                "GetBridgeType maps ocean/pond-low/pond-med/pond-high and edge variants into bridge type ids.",
                "Fortree and Pacifidlog bridge/log helpers are separate from water bridge helpers.",
            ],
            "godot_current": [
                "Generated elevation values are exposed, but bridge semantics remain first-pass metadata.",
            ],
            "gaps": [
                "Bridge and elevation behavior need a source-backed MapRuntime contract.",
            ],
        },
        {
            "id": "seafoam_external_helper",
            "source_entry": "src/overworld.c:MetatileBehavior_IsSurfableInSeafoamIslands",
            "status": "metadata_only",
            "critical_order": [
                "The helper first checks MetatileBehavior_IsSurfableWaterOrUnderwater.",
                "Only Seafoam Islands B3F and B4F map ids force this surfable tile to initial on-foot state.",
                "It is declared in include/overworld.h, not include/metatile_behavior.h.",
            ],
            "godot_current": [
                "No generated table currently links this external helper into metatile behavior classification.",
            ],
            "gaps": [
                "External helper definitions must remain part of future metatile behavior generation.",
            ],
        },
        {
            "id": "godot_current_helper_table_gap",
            "source_entry": "scripts/autoload/map_runtime.gd + scripts/autoload/encounter_engine.gd",
            "status": "first_pass",
            "critical_order": [
                "MapRuntime exposes behavior id/name, not helper predicate groups.",
                "EncounterEngine maintains only land/water/bridge subsets needed by its first-pass encounter flow.",
                "This report is data/metadata only and is meant to drive a generated Godot helper registry.",
            ],
            "godot_current": [
                "Behavior ids/names are present in generated tileset JSON and map cell info.",
            ],
            "gaps": [
                "Collision, terrain, transition, and interaction owners still need to consume generated helper categories.",
            ],
        },
        {
            "id": "visual_effect_and_audio_policy",
            "source_entry": "project skill front-loaded porting constraints",
            "status": "metadata_only",
            "critical_order": [
                "Do not recreate GBA palette-bank, VRAM, OAM, or packed graphics limits at runtime.",
                "Palette/tint/blend/scale/rotation/affine visible effects should be Godot-native while preserving source timing and visible rhythm.",
                "Audio remains metadata_only/unsupported until explicitly reopened.",
            ],
            "godot_current": [
                "Generated tilesets and doors are palette-baked normal RGBA assets.",
            ],
            "gaps": [
                "Future dynamic-tile, terrain, weather, and field effects must carry deviation metadata when approximate.",
            ],
        },
    ]


def current_godot_metatile_summary():
    tileset_dir = REPO_ROOT / "data" / "generated" / "tilesets"
    tileset_records = []
    unique_used_behaviors = set()
    unique_declared_behaviors = set()
    total_metatile_entries = 0
    if tileset_dir.exists():
        for path in sorted(tileset_dir.glob("*.json")):
            try:
                data = json.loads(path.read_text(encoding="utf-8"))
            except json.JSONDecodeError:
                continue
            declared = data.get("metatile_behaviors", {}).get("names", [])
            for row in declared if isinstance(declared, list) else []:
                if isinstance(row, dict) and row.get("name"):
                    unique_declared_behaviors.add(str(row["name"]))
            used = set()
            entries = data.get("metatile_entries", [])
            if isinstance(entries, list):
                total_metatile_entries += len(entries)
                for entry in entries:
                    if not isinstance(entry, dict):
                        continue
                    attribute = entry.get("attribute", {})
                    if isinstance(attribute, dict) and attribute.get("behavior_name"):
                        behavior_name = str(attribute["behavior_name"])
                        used.add(behavior_name)
                        unique_used_behaviors.add(behavior_name)
            source = data.get("source", {}) if isinstance(data.get("source", {}), dict) else {}
            tileset_records.append({
                "path": to_project_path(path.relative_to(REPO_ROOT)),
                "map": source.get("map_folder", data.get("map", data.get("name", ""))),
                "metatile_entry_count": len(entries) if isinstance(entries, list) else 0,
                "used_behavior_name_count": len(used),
                "sample_used_behavior_names": sorted(used)[:16],
            })

    return {
        "generated_tileset_record_count": len(tileset_records),
        "generated_metatile_entry_count": total_metatile_entries,
        "declared_behavior_name_count": len(unique_declared_behaviors),
        "used_behavior_name_count": len(unique_used_behaviors),
        "sample_used_behavior_names": sorted(unique_used_behaviors)[:24],
        "tileset_records": tileset_records,
        "runtime_owners": [
            "scripts/autoload/map_runtime.gd:get_metatile_behavior_at/get_metatile_behavior_name_at",
            "scripts/autoload/encounter_engine.gd:LAND_ENCOUNTER_BEHAVIORS/WATER_ENCOUNTER_BEHAVIORS/BRIDGE_OVER_WATER_BEHAVIORS",
        ],
        "runtime_status": "first_pass_behavior_ids_names_only",
    }


def build_stats(presence, locations, constants, bit_attrs, functions, external_functions, call_sites, flow_rows):
    missing_symbols = [symbol for symbol, occurrences in locations.items() if not occurrences]
    status_counts = {}
    for row in flow_rows:
        status_counts[row["status"]] = status_counts.get(row["status"], 0) + 1
    unsupported_status_counts = {}
    for row in UNSUPPORTED:
        unsupported_status_counts[row["status"]] = unsupported_status_counts.get(row["status"], 0) + 1

    function_names = {row["function"] for row in functions}
    called_names = {row["symbol"] for row in call_sites["helpers"]}
    external_names = {row["function"] for row in external_functions}
    header_declared = [row for row in functions if row["declared_in_header"]]
    unprototyped = [row for row in functions if not row["declared_in_header"]]

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
        "metatile_behavior_constant_count": len(constants["constants"]),
        "num_metatile_behaviors_value": constants["num_metatile_behaviors_value"],
        "last_metatile_behavior_id": constants["constants"][-1]["id"] if constants["constants"] else None,
        "explicit_tile_bit_attribute_count": len(bit_attrs["explicit_rows"]),
        "encounter_flag_behavior_count": len(bit_attrs["encounter_behaviors"]),
        "surfable_flag_behavior_count": len(bit_attrs["surfable_behaviors"]),
        "unused_hint_behavior_count": len(bit_attrs["unused_hint_behaviors"]),
        "metatile_behavior_function_count": len(functions),
        "declared_function_count": len(header_declared),
        "unprototyped_function_count": len(unprototyped),
        "unprototyped_functions": [row["function"] for row in unprototyped],
        "external_helper_definition_count": len(external_functions),
        "external_helper_definitions": [row["function"] for row in external_functions],
        "call_site_file_count": len(call_sites["files"]),
        "called_helper_count": len(call_sites["helpers"]),
        "external_called_helper_count": len(called_names - function_names),
        "external_called_helpers": sorted(called_names - function_names),
        "called_but_not_defined_in_trace_count": len(called_names - function_names - external_names),
        "called_but_not_defined_in_trace": sorted(called_names - function_names - external_names),
        "core_helper_count": len(CORE_HELPERS),
    }


def manifest_entry_for(exported, output_path):
    stats = exported["stats"]
    return {
        "category": "overworld_metatile_behavior_trace",
        "path": to_project_path(output_path),
        "source_file_count": stats["source_file_count"],
        "flow_count": stats["flow_count"],
        "metatile_behavior_constant_count": stats["metatile_behavior_constant_count"],
        "metatile_behavior_function_count": stats["metatile_behavior_function_count"],
        "explicit_tile_bit_attribute_count": stats["explicit_tile_bit_attribute_count"],
        "encounter_flag_behavior_count": stats["encounter_flag_behavior_count"],
        "surfable_flag_behavior_count": stats["surfable_flag_behavior_count"],
        "call_site_file_count": stats["call_site_file_count"],
        "unsupported_count": stats["unsupported_count"],
    }


def build_export(source_root):
    source_root = Path(source_root)
    constants_text = read_text(source_root / "include/constants/metatile_behaviors.h")
    metatile_header_text = read_text(source_root / "include/metatile_behavior.h")
    overworld_header_text = read_text(source_root / "include/overworld.h")
    metatile_text = read_text(source_root / "src/metatile_behavior.c")
    presence = source_file_presence(source_root)
    locations = symbol_locations(source_root)
    constants = parse_metatile_constants(constants_text)
    prototypes = parse_header_prototypes(metatile_header_text)
    prototypes.update(parse_header_prototypes(overworld_header_text))
    bit_attrs = parse_tile_bit_attributes(metatile_text, constants["constant_by_name"])
    functions = parse_function_definitions(metatile_text, "src/metatile_behavior.c", prototypes)
    call_sites = collect_call_sites(source_root)
    internal_names = {row["function"] for row in functions}
    called_names = {row["symbol"] for row in call_sites["helpers"]}
    external_functions = parse_external_helper_definitions(source_root, called_names, internal_names, prototypes)
    flow_rows = source_flow_rows()
    stats = build_stats(presence, locations, constants, bit_attrs, functions, external_functions, call_sites, flow_rows)

    return {
        "schema_version": 1,
        "generated_by": GENERATED_BY,
        "source_root": str(source_root),
        "source_files": presence,
        "required_symbols": locations,
        "metatile_behavior_constants": {
            "source": constants["source"],
            "constants": constants["constants"],
            "num_metatile_behaviors_value": constants["num_metatile_behaviors_value"],
            "mb_invalid_expr": constants["mb_invalid_expr"],
        },
        "tile_bit_attributes": bit_attrs,
        "helper_functions": functions,
        "external_helper_functions": external_functions,
        "core_helpers": CORE_HELPERS,
        "call_sites": call_sites,
        "source_flows": flow_rows,
        "godot_current": current_godot_metatile_summary(),
        "godot_trace_owners": {
            "importer": [
                "tools/importer/export_tilesets.py",
                GENERATED_BY,
            ],
            "runtime": [
                "scripts/autoload/map_runtime.gd",
                "scripts/autoload/encounter_engine.gd",
            ],
            "generated_data": [
                "data/generated/tilesets/*.json",
                "data/generated/overworld/metatile_behavior_trace.json",
            ],
            "tests": [
                "tools/importer/export_overworld_metatile_behavior_trace_smoke.py",
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

#!/usr/bin/env python3
"""Export source-traced overworld script-command coverage."""

import argparse
import json
import re
import sys
from pathlib import Path

from export_map import write_json, write_manifest
from source_probe import load_config, to_project_path


GENERATED_BY = "tools/importer/export_overworld_scrcmd_trace.py"
REPORT_PATH = Path("overworld/scrcmd_trace.json")
REPO_ROOT = Path(__file__).resolve().parents[2]

SOURCE_FILES = [
    "data/script_cmd_table.inc",
    "asm/macros/event.inc",
    "include/script.h",
    "src/script.c",
    "src/scrcmd.c",
    "include/global.fieldmap.h",
    "include/fieldmap.h",
    "src/fieldmap.c",
    "include/field_screen_effect.h",
    "src/field_screen_effect.c",
    "include/field_weather.h",
    "src/field_weather.c",
    "include/field_door.h",
    "src/field_door.c",
    "include/field_effect.h",
    "src/field_effect.c",
    "include/script_movement.h",
    "src/script_movement.c",
    "include/event_object_movement.h",
    "src/event_object_movement.c",
    "include/event_object_lock.h",
    "src/event_object_lock.c",
    "include/trainer_see.h",
    "src/trainer_see.c",
    "include/battle_setup.h",
    "src/battle_setup.c",
    "include/overworld.h",
    "src/overworld.c",
    "include/sound.h",
    "src/sound.c",
    "include/field_message_box.h",
    "src/field_message_box.c",
]

REQUIRED_SYMBOLS = [
    "gScriptCmdTable",
    "script_cmd_table_entry",
    "SCR_OP_WAITSTATE",
    "SCR_OP_DELAY",
    "SCR_OP_FADESCREEN",
    "SCR_OP_WARP",
    "SCR_OP_WARPSILENT",
    "SCR_OP_WARPDOOR",
    "SCR_OP_WARPHOLE",
    "SCR_OP_WARPTELEPORT",
    "SCR_OP_WARPSPINENTER",
    "SCR_OP_WARPWHITEFADE",
    "SCR_OP_PLAYSE",
    "SCR_OP_WAITSE",
    "SCR_OP_PLAYFANFARE",
    "SCR_OP_WAITFANFARE",
    "SCR_OP_PLAYBGM",
    "SCR_OP_FADEOUTBGM",
    "SCR_OP_SETWEATHER",
    "SCR_OP_RESETWEATHER",
    "SCR_OP_DOWEATHER",
    "SCR_OP_DOFIELDEFFECT",
    "SCR_OP_WAITFIELDEFFECT",
    "SCR_OP_SETMETATILE",
    "SCR_OP_OPENDOOR",
    "SCR_OP_CLOSEDOOR",
    "SCR_OP_WAITDOORANIM",
    "SCR_OP_TRAINERBATTLE",
    "SCR_OP_DOTRAINERBATTLE",
    "Script_RequestEffects",
    "SCREFF_V1",
    "SCREFF_SAVE",
    "SCREFF_HARDWARE",
    "SCREFF_TRAINERBATTLE",
    "SetupNativeScript",
    "ScriptContext_Stop",
    "ScrCmd_waitstate",
    "ScrCmd_delay",
    "ScrCmd_fadescreen",
    "ScrCmd_fadescreenspeed",
    "ScrCmd_fadescreenswapbuffers",
    "ScrCmd_setweather",
    "ScrCmd_resetweather",
    "ScrCmd_doweather",
    "ScrCmd_warp",
    "ScrCmd_warpsilent",
    "ScrCmd_warpdoor",
    "ScrCmd_warphole",
    "ScrCmd_warpteleport",
    "ScrCmd_warpmossdeepgym",
    "ScrCmd_warpspinenter",
    "ScrCmd_warpwhitefade",
    "ScrCmd_playse",
    "ScrCmd_waitse",
    "ScrCmd_playfanfare",
    "ScrCmd_waitfanfare",
    "ScrCmd_playbgm",
    "ScrCmd_fadeoutbgm",
    "ScrCmd_applymovement",
    "ScrCmd_waitmovement",
    "ScrCmd_removeobject",
    "ScrCmd_addobject",
    "ScrCmd_setobjectxy",
    "ScrCmd_setobjectxyperm",
    "ScrCmd_setobjectmovementtype",
    "ScrCmd_lock",
    "ScrCmd_lockall",
    "ScrCmd_release",
    "ScrCmd_releaseall",
    "ScrCmd_trainerbattle",
    "ScrCmd_dotrainerbattle",
    "ScrCmd_setwildbattle",
    "ScrCmd_dowildbattle",
    "ScrCmd_dofieldeffect",
    "ScrCmd_setfieldeffectargument",
    "ScrCmd_waitfieldeffect",
    "ScrCmd_setmetatile",
    "ScrCmd_opendoor",
    "ScrCmd_closedoor",
    "ScrCmd_waitdooranim",
    "ScrCmd_setdooropen",
    "ScrCmd_setdoorclosed",
    "SetSavedWeather",
    "SetSavedWeatherFromCurrMapHeader",
    "DoCurrentWeather",
    "FadeScreen",
    "FadeScreenHardware",
    "SetWarpDestination",
    "DoWarp",
    "DoDiveWarp",
    "DoDoorWarp",
    "DoFallWarp",
    "DoTeleportTileWarp",
    "DoSpinEnterWarp",
    "DoWhiteFadeWarp",
    "ResetInitialPlayerAvatarState",
    "MapGridSetMetatileIdAt",
    "MAP_OFFSET",
    "MAPGRID_IMPASSABLE",
    "FieldAnimateDoorOpen",
    "FieldAnimateDoorClose",
    "FieldIsDoorAnimationRunning",
    "PlaySE",
    "IsSEPlaying",
    "PlayFanfare",
    "IsFanfareTaskInactive",
    "PlayNewMapMusic",
    "FadeOutBGMTemporarily",
    "ScriptMovement_StartObjectMovementScript",
    "ScriptMovement_IsObjectMovementFinished",
    "FreezeObjects_WaitForPlayer",
    "FreezeForApproachingTrainers",
    "BattleSetup_ConfigureTrainerBattle",
    "BattleSetup_StartTrainerBattle",
    "CreateScriptedWildMon",
    "CreateScriptedDoubleWildMon",
    "BattleSetup_StartScriptedWildBattle",
    "BattleSetup_StartScriptedDoubleWildBattle",
    "FieldEffectStart",
    "FieldEffectActiveListContains",
]

UNSUPPORTED = [
    {
        "code": "scrcmd_full_vm_pending",
        "status": "unsupported",
        "source": "data/script_cmd_table.inc + src/scrcmd.c",
        "detail": "Godot ScriptVM implements only a first synchronous subset of source script commands; the full 231-opcode table is not executable yet.",
    },
    {
        "code": "async_native_wait_scheduler_pending",
        "status": "unsupported",
        "source": "src/scrcmd.c:SetupNativeScript waits",
        "detail": "Source waits such as delay, fade, movement, door, sound, fanfare, field-effect, trainer battle, and waitstate are traced but not scheduled as source-equivalent async script contexts.",
    },
    {
        "code": "weather_script_commands_pending",
        "status": "unsupported",
        "source": "src/scrcmd.c:ScrCmd_setweather/resetweather/doweather",
        "detail": "Weather commands are not implemented in ScriptVM or presentation; future work must route them through source weather ids and Godot-native visual effects.",
    },
    {
        "code": "fade_palette_runtime_pending",
        "status": "unsupported",
        "source": "src/scrcmd.c:ScrCmd_fadescreen/fadescreenspeed/fadescreenswapbuffers",
        "detail": "Screen fades and hardware blend restoration are traced but not source-equivalent in presentation.",
    },
    {
        "code": "audio_playback_metadata_only",
        "status": "metadata_only",
        "source": "src/scrcmd.c audio commands",
        "detail": "SE, fanfare, BGM, cry, and audio wait commands preserve symbols/timing intent only; real playback remains out of scope.",
    },
    {
        "code": "field_effect_runtime_pending",
        "status": "unsupported",
        "source": "src/scrcmd.c:ScrCmd_dofieldeffect/setfieldeffectargument/waitfieldeffect",
        "detail": "FieldEffectStart and FieldEffectActiveListContains are traced, but field-effect task playback is not source-equivalent.",
    },
    {
        "code": "trainerbattle_script_commands_pending",
        "status": "unsupported",
        "source": "src/scrcmd.c:ScrCmd_trainerbattle/dotrainerbattle",
        "detail": "Trainer battle script command parsing and post-battle script flow remain pending beyond debug/event bridge slices.",
    },
    {
        "code": "scripted_wild_battle_commands_pending",
        "status": "unsupported",
        "source": "src/scrcmd.c:ScrCmd_setwildbattle/dowildbattle",
        "detail": "Scripted single/double wild battle commands are traced but not executable in ScriptVM.",
    },
    {
        "code": "broad_warp_variants_pending",
        "status": "unsupported",
        "source": "src/scrcmd.c warp family",
        "detail": "ScriptVM currently handles only warp/warpsilent first-pass effects; door, hole, teleport, spin, white-fade, dynamic, dive, and Mossdeep variants remain pending.",
    },
    {
        "code": "door_set_open_closed_pending",
        "status": "unsupported",
        "source": "src/scrcmd.c:ScrCmd_setdooropen/setdoorclosed",
        "detail": "Open/close animation effects are first-pass records; immediate door-state mutation commands are not runtime-equivalent.",
    },
    {
        "code": "object_subpriority_vobject_pending",
        "status": "unsupported",
        "source": "src/scrcmd.c object subpriority and virtual object commands",
        "detail": "Object visibility/position commands have first-pass runtime effects, but subpriority and virtual object commands remain pending.",
    },
    {
        "code": "map_layout_step_callback_pending",
        "status": "unsupported",
        "source": "src/scrcmd.c:ScrCmd_setmaplayoutindex/setstepcallback",
        "detail": "Map layout switching and per-step callbacks are traced but not executable in Godot runtime.",
    },
    {
        "code": "shop_menu_contest_commands_pending",
        "status": "unsupported",
        "source": "src/scrcmd.c menu/shop/contest commands",
        "detail": "Menu, shop, contest, slot, money/coin UI, and related command families are outside the current overworld vertical slice.",
    },
    {
        "code": "callnative_special_broad_pending",
        "status": "unsupported",
        "source": "asm/macros/event.inc:callnative/gotonative/special/specialvar",
        "detail": "Only a tiny source-traced special subset is implemented; arbitrary native/special dispatch remains unsupported until each target is traced.",
    },
    {
        "code": "gba_hardware_effects_godot_native",
        "status": "metadata_only",
        "source": "project porting policy + SCREFF_HARDWARE commands",
        "detail": "GBA palette/GPU/hardware details are source metadata; visible effects must be Godot-native while preserving source timing and result where practical.",
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


def extract_function_body(text, function_name):
    match = re.search(r"\b%s\s*\([^;{}]*\)\s*\{" % re.escape(function_name), text)
    if not match:
        return ""
    return extract_braced_body(text, match.end() - 1)


def parse_script_cmd_table(table_text):
    rows = []
    pattern = re.compile(
        r"script_cmd_table_entry\s+(SCR_OP_[A-Z0-9_]+)\s+(ScrCmd_[A-Za-z0-9_]+),\s*requests_effects=(\d+)\s*@\s*0x([0-9a-f]+)"
    )
    for match in pattern.finditer(table_text):
        constant = match.group(1)
        rows.append({
            "opcode": int(match.group(4), 16),
            "opcode_hex": "0x%02x" % int(match.group(4), 16),
            "constant": constant,
            "command_name": constant[len("SCR_OP_"):].lower(),
            "handler": match.group(2),
            "requests_effects": int(match.group(3)) == 1,
            "categories": classify_command(constant, match.group(2)),
            "line": table_text.count("\n", 0, match.start()) + 1,
        })
    return rows


def parse_scrcmd_functions(scrcmd_text, table_handlers):
    rows = []
    pattern = re.compile(r"\bbool8\s+(ScrCmd_[A-Za-z0-9_]+)\s*\([^;{}]*\)\s*\{")
    for match in pattern.finditer(scrcmd_text):
        function = match.group(1)
        body = extract_braced_body(scrcmd_text, match.end() - 1)
        calls = sorted(set(re.findall(r"\b([A-Z][A-Za-z0-9_]+)\s*\(", body)))
        rows.append({
            "function": function,
            "line": scrcmd_text.count("\n", 0, match.start()) + 1,
            "in_command_table": function in table_handlers,
            "effect_flags": sorted(set(re.findall(r"\bSCREFF_[A-Z0-9_]+\b", body))),
            "uses_var_get": "VarGet" in body,
            "writes_var": "GetVarPointer" in body or "Script_RequestWriteVar" in body,
            "uses_setup_native_script": "SetupNativeScript" in body,
            "stops_script_context": "ScriptContext_Stop" in body,
            "returns_true_literal": bool(re.search(r"\breturn\s+TRUE\s*;", body)),
            "returns_false_literal": bool(re.search(r"\breturn\s+FALSE\s*;", body)),
            "source_calls": calls,
            "body_summary": summarize_body(body),
        })
    rows.sort(key=lambda row: row["line"])
    return rows


def parse_event_macros(macro_text):
    rows = []
    pattern = re.compile(r"^\t\.macro\s+([A-Za-z_][A-Za-z0-9_]*)\b([^\n]*)", re.M)
    for match in pattern.finditer(macro_text):
        start = match.end()
        end = macro_text.find("\t.endm", start)
        body = macro_text[start:end if end >= 0 else start]
        command_constants = sorted(set(re.findall(r"\bSCR_OP_[A-Z0-9_]+\b", body)))
        native_handlers = sorted(set(re.findall(r"\bScrCmd_[A-Za-z0-9_]+\b", body)))
        rows.append({
            "macro": match.group(1),
            "line": macro_text.count("\n", 0, match.start()) + 1,
            "signature": normalize_ws(match.group(2)),
            "command_constants": command_constants,
            "native_handlers": native_handlers,
            "emits_command": bool(command_constants),
            "uses_callnative_style_handler": bool(native_handlers),
        })
    return rows


def parse_current_script_vm_support(project_root):
    path = project_root / "scripts" / "autoload" / "script_vm.gd"
    if not path.exists():
        return {
            "script_vm_path": "",
            "supported_generated_ops": [],
        }
    text = read_text(path)
    start = text.find("func _execute_instruction")
    end = text.find("\n\nfunc _execute_conditional_branch", start)
    body = text[start:end if end >= 0 else len(text)]
    supported = set()
    for line in body.splitlines():
        stripped = line.strip()
        if stripped.startswith("_:"):
            continue
        if stripped.endswith(":") and stripped.startswith('"'):
            supported.update(re.findall(r'"([a-z0-9_]+)"', stripped[:-1]))
    return {
        "script_vm_path": "scripts/autoload/script_vm.gd",
        "supported_generated_ops": sorted(supported),
    }


def classify_command(constant, handler):
    command = constant[len("SCR_OP_"):]
    categories = []
    if command.startswith("WAIT") or command == "DELAY":
        categories.append("wait_timing")
    if "DOOR" in command:
        categories.append("door")
    if "WARP" in command:
        categories.append("warp_transition")
    if "WEATHER" in command or "FADE" in command or "FLASH" in command:
        categories.append("weather_fade_flash")
    if (
        command in ("PLAYSE", "WAITSE", "PLAYFANFARE", "WAITFANFARE", "PLAYBGM", "SAVEBGM", "PLAYMONCRY", "WAITMONCRY")
        or "FANFARE" in command
        or "BGM" in command
        or "CRY" in command
    ):
        categories.append("audio")
    if "FIELDEFFECT" in command:
        categories.append("field_effect")
    if "OBJECT" in command or "VOBJECT" in command or "MOVEMENT" in command or "FOLLOWER" in command:
        categories.append("object_event")
    if "TRAINER" in command or "WILDBATTLE" in command:
        categories.append("trainer_battle")
    if "METATILE" in command or "MAPLAYOUT" in command or "RESPAWN" in command or "STEPCALLBACK" in command:
        categories.append("map_mutation")
    if (
        "MESSAGE" in command
        or "BOX" in command
        or "MULTICHOICE" in command
        or "TEXTCOLOR" in command
        or "MONPIC" in command
        or "BRAILLE" in command
    ):
        categories.append("message_ui")
    if (
        command.startswith("GOTO")
        or command.startswith("CALL")
        or command.startswith("RETURN")
        or command.startswith("END")
        or "VAR" in command
        or "FLAG" in command
        or "COMPARE" in command
        or "SPECIAL" in command
        or "NATIVE" in command
        or "RANDOM" in command
        or "GAMESTAT" in command
    ):
        categories.append("flow_state")
    if not categories:
        categories.append("other")
    return categories


def summarize_body(body):
    cleaned = normalize_ws(re.sub(r"/\*.*?\*/", "", re.sub(r"//.*", "", body), flags=re.S))
    if len(cleaned) <= 260:
        return cleaned
    return cleaned[:257].rstrip() + "..."


def enrich_table_with_functions_and_vm(table_rows, functions, current_vm):
    function_map = {row["function"]: row for row in functions}
    supported_ops = set(current_vm.get("supported_generated_ops", []))
    for row in table_rows:
        function = function_map.get(row["handler"], {})
        row["handler_found"] = bool(function)
        row["effect_flags"] = function.get("effect_flags", [])
        row["uses_setup_native_script"] = bool(function.get("uses_setup_native_script", False))
        row["stops_script_context"] = bool(function.get("stops_script_context", False))
        row["returns_true_literal"] = bool(function.get("returns_true_literal", False))
        row["source_calls"] = function.get("source_calls", [])
        row["godot_direct_generated_op_supported"] = row["command_name"] in supported_ops
        row["godot_status"] = "first_pass" if row["godot_direct_generated_op_supported"] else "unsupported"
    return table_rows


def source_flow_rows():
    return [
        {
            "id": "script_command_table_order",
            "source_entry": "data/script_cmd_table.inc:gScriptCmdTable",
            "status": "metadata_only",
            "critical_order": [
                "The command table defines SCR_OP_* byte values from 0x00 through 0xe6.",
                "Every active row uses requests_effects=1 in this source tree.",
                "Rows point to ScrCmd_* handlers; several table rows intentionally reuse ScrCmd_nop1.",
            ],
            "godot_current": [
                "Generated script import records macro names and raw instructions, not raw opcode bytes.",
            ],
            "gaps": [
                "The VM should keep a source command table reference for unsupported opcode reporting and future raw-byte fidelity.",
            ],
        },
        {
            "id": "effect_instrumentation",
            "source_entry": "src/scrcmd.c:Script_RequestEffects",
            "status": "metadata_only",
            "critical_order": [
                "SCREFF_SAVE marks commands that mutate save-relevant state.",
                "SCREFF_HARDWARE marks visible/audio/timing hardware-facing effects.",
                "SCREFF_TRAINERBATTLE marks trainer battle argument loading.",
            ],
            "godot_current": [
                "ScriptVM records structured effects but does not yet mirror source effect instrumentation classes.",
            ],
            "gaps": [
                "Future VM traces should expose save/hardware/trainerbattle effect classes per executed command.",
            ],
        },
        {
            "id": "wait_and_native_blocking",
            "source_entry": "src/scrcmd.c:SetupNativeScript/ScriptContext_Stop",
            "status": "unsupported",
            "critical_order": [
                "waitstate stops script context until external code enables it.",
                "delay installs RunPauseTimer for frame-count waits.",
                "fade, movement, door, sound, fanfare, cry, and field-effect waits install native wait predicates.",
            ],
            "godot_current": [
                "ScriptVM records waits as effects or waiting status but does not run source-equivalent asynchronous task timing.",
            ],
            "gaps": [
                "A scheduler must own native wait predicates and visible timing.",
            ],
        },
        {
            "id": "warp_and_transition_commands",
            "source_entry": "src/scrcmd.c warp family + asm/macros/event.inc:formatwarp",
            "status": "first_pass",
            "critical_order": [
                "warp/warpsilent/warpdoor/warphole/warpteleport/warpmossdeepgym/warpspinenter/warpwhitefade all set a destination then call a distinct Do*Warp helper.",
                "Warp-style commands reset the initial player avatar state after queuing the warp.",
                "formatwarp accepts destination warp id, explicit x/y, both, or neither.",
            ],
            "godot_current": [
                "ScriptVM handles warp and warpsilent as first-pass transition effects; EventManager can apply generated destinations.",
            ],
            "gaps": [
                "Door/hole/teleport/spin/white-fade/dynamic/dive variants need source-timed presentation and destination semantics.",
            ],
        },
        {
            "id": "map_mutation_and_door_commands",
            "source_entry": "src/scrcmd.c:setmetatile/opendoor/closedoor/waitdooranim/setdooropen/setdoorclosed",
            "status": "first_pass",
            "critical_order": [
                "setmetatile reads x/y/metatile/impassable through VarGet and adds MAP_OFFSET before writing MapGridSetMetatileIdAt.",
                "opendoor and closedoor add MAP_OFFSET, then call FieldAnimateDoorOpen/Close; opendoor also resolves and plays the door sound.",
                "waitdooranim installs a native wait on FieldIsDoorAnimationRunning.",
            ],
            "godot_current": [
                "ScriptVM emits first-pass setmetatile and door effects; MapRuntime can apply setmetatile and transition presentation can play generated door overlays.",
            ],
            "gaps": [
                "Standalone script door animation, setdooropen/setdoorclosed, and true async waitdooranim remain pending.",
            ],
        },
        {
            "id": "weather_fade_flash_commands",
            "source_entry": "src/scrcmd.c weather/fade/flash commands",
            "status": "unsupported",
            "critical_order": [
                "setweather writes saved weather through SetSavedWeather.",
                "resetweather restores the current map header weather.",
                "doweather applies current weather immediately.",
                "fadescreenswapbuffers restores weather blend state for FADE_FROM_WHITE before hardware fade.",
            ],
            "godot_current": [
                "Weather commands and exact fade/palette presentation are not implemented.",
            ],
            "gaps": [
                "Weather/fade effects must become Godot-native visual effects while preserving source timing.",
            ],
        },
        {
            "id": "audio_commands",
            "source_entry": "src/scrcmd.c playse/waitse/playfanfare/waitfanfare/playbgm/fade*bgm/playmoncry/waitmoncry",
            "status": "metadata_only",
            "critical_order": [
                "SE and fanfare waits use native predicates IsSEPlaying and IsFanfareTaskInactive.",
                "BGM commands can save map music or temporarily fade out/in.",
                "Pokemon cries have a separate wait predicate.",
            ],
            "godot_current": [
                "ScriptVM records audio effects and wait intent only.",
            ],
            "gaps": [
                "Real audio playback is intentionally out of scope until explicitly reopened.",
            ],
        },
        {
            "id": "movement_object_lock_commands",
            "source_entry": "src/scrcmd.c movement/object/lock commands",
            "status": "first_pass",
            "critical_order": [
                "applymovement clears direction overwrite and starts ScriptMovement_StartObjectMovementScript.",
                "waitmovement waits on ScriptMovement_IsObjectMovementFinished and can also wait for follower Pokeball entry.",
                "lock/lockall freeze objects immediately then wait for player/selected movement completion.",
            ],
            "godot_current": [
                "ScriptVM emits first-pass movement/object/lock effects and MapRuntime fast-forwards supported object state changes.",
            ],
            "gaps": [
                "Held movement queues, live object task timing, subpriority, virtual objects, and follower edge cases remain pending.",
            ],
        },
        {
            "id": "trainer_and_battle_commands",
            "source_entry": "src/scrcmd.c trainerbattle/dotrainerbattle/setwildbattle/dowildbattle",
            "status": "unsupported",
            "critical_order": [
                "trainerbattle loads arguments and advances scriptPtr through BattleSetup_ConfigureTrainerBattle.",
                "dotrainerbattle starts trainer battle and returns TRUE to hand off script execution.",
                "setwildbattle prepares scripted single or double wild encounters; dowildbattle starts the corresponding battle and stops the script context.",
            ],
            "godot_current": [
                "EventManager has a first-pass trainer battle bridge outside ScriptVM, and standard wild encounters can bridge to BattleEngine.",
            ],
            "gaps": [
                "Script-driven trainer and scripted wild battle opcodes need source-backed VM execution and post-battle flow.",
            ],
        },
        {
            "id": "field_effect_commands",
            "source_entry": "src/scrcmd.c:dofieldeffect/setfieldeffectargument/waitfieldeffect",
            "status": "unsupported",
            "critical_order": [
                "dofieldeffect stores sFieldEffectScriptId and calls FieldEffectStart.",
                "setfieldeffectargument writes gFieldEffectArguments[argNum].",
                "waitfieldeffect waits until the active effect list no longer contains the effect id.",
            ],
            "godot_current": [
                "No source-equivalent field-effect runtime exists yet.",
            ],
            "gaps": [
                "Field effects need generated asset links, task timing, and Godot-native visual implementation.",
            ],
        },
        {
            "id": "message_ui_and_menu_commands",
            "source_entry": "src/scrcmd.c message/menu commands + data/scripts/std_msgbox.inc",
            "status": "first_pass",
            "critical_order": [
                "message/msgbox/yesnobox/waitmessage/waitbuttonpress/closemessage drive source message UI flow.",
                "Menu, shop, contest, money/coin boxes, multichoice, mon pictures, and braille have separate command families.",
            ],
            "godot_current": [
                "ScriptVM supports first-pass message/msgbox/yesnobox text flow and records UI wait intent.",
            ],
            "gaps": [
                "Source-shaped windows, printers, menus, braille, money/coin boxes, and multichoice UI remain pending.",
            ],
        },
        {
            "id": "godot_current_script_vm_gap",
            "source_entry": "scripts/autoload/script_vm.gd",
            "status": "first_pass",
            "critical_order": [
                "The current VM executes a generated-script op-name subset, not the raw source opcode table.",
                "Unsupported commands are recorded rather than guessed.",
                "This report is a source map for expanding the VM safely.",
            ],
            "godot_current": [
                "Current ScriptVM coverage is intentionally first-pass and synchronous.",
            ],
            "gaps": [
                "Each future command implementation must trace its source-visible waits, presentation, state writes, and audio intent first.",
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
                "Script command reports carry source audio/visual intent without claiming playback parity.",
            ],
            "gaps": [
                "Future fade, weather, field-effect, and battle/warp visual work must report deviations explicitly.",
            ],
        },
    ]


def current_godot_summary(table_rows, macro_rows, current_vm):
    supported_ops = set(current_vm.get("supported_generated_ops", []))
    table_command_names = {row["command_name"] for row in table_rows}
    direct_supported = sorted(table_command_names & supported_ops)
    macro_supported = sorted({
        row["macro"]
        for row in macro_rows
        if row["macro"] in supported_ops
    })
    return {
        "script_vm_path": current_vm.get("script_vm_path", ""),
        "supported_generated_op_count": len(supported_ops),
        "supported_generated_ops": sorted(supported_ops),
        "direct_table_command_supported_count": len(direct_supported),
        "direct_table_command_supported": direct_supported,
        "supported_macro_name_count": len(macro_supported),
        "supported_macro_names": macro_supported,
        "runtime_status": "first_pass_synchronous_subset",
        "audio_status": "metadata_only",
        "weather_status": "unsupported",
        "fade_status": "unsupported",
        "field_effect_status": "unsupported",
        "trainerbattle_script_status": "unsupported",
    }


def build_stats(presence, locations, table_rows, functions, macro_rows, current_vm, flow_rows):
    missing_symbols = [symbol for symbol, occurrences in locations.items() if not occurrences]
    status_counts = {}
    for row in flow_rows:
        status_counts[row["status"]] = status_counts.get(row["status"], 0) + 1
    unsupported_status_counts = {}
    for row in UNSUPPORTED:
        unsupported_status_counts[row["status"]] = unsupported_status_counts.get(row["status"], 0) + 1

    table_handlers = {row["handler"] for row in table_rows}
    function_names = {row["function"] for row in functions}
    category_counts = {}
    for row in table_rows:
        for category in row["categories"]:
            category_counts[category] = category_counts.get(category, 0) + 1

    native_wait_rows = [row for row in functions if row["uses_setup_native_script"]]
    stop_rows = [row for row in functions if row["stops_script_context"]]
    hardware_rows = [row for row in functions if "SCREFF_HARDWARE" in row["effect_flags"]]
    save_rows = [row for row in functions if "SCREFF_SAVE" in row["effect_flags"]]

    godot = current_godot_summary(table_rows, macro_rows, current_vm)
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
        "script_cmd_table_entry_count": len(table_rows),
        "script_cmd_table_last_opcode": max(row["opcode"] for row in table_rows) if table_rows else None,
        "script_cmd_table_requests_effects_count": sum(1 for row in table_rows if row["requests_effects"]),
        "unique_table_handler_count": len(table_handlers),
        "scrcmd_function_count": len(functions),
        "scrcmd_functions_not_in_table_count": len(function_names - table_handlers),
        "scrcmd_functions_not_in_table": sorted(function_names - table_handlers),
        "table_handlers_missing_definition_count": len(table_handlers - function_names),
        "table_handlers_missing_definition": sorted(table_handlers - function_names),
        "event_macro_count": len(macro_rows),
        "event_macro_with_opcode_count": sum(1 for row in macro_rows if row["emits_command"]),
        "event_macro_with_native_handler_count": sum(1 for row in macro_rows if row["uses_callnative_style_handler"]),
        "native_wait_function_count": len(native_wait_rows),
        "script_context_stop_function_count": len(stop_rows),
        "hardware_effect_function_count": len(hardware_rows),
        "save_effect_function_count": len(save_rows),
        "category_counts": category_counts,
        "supported_generated_op_count": godot["supported_generated_op_count"],
        "direct_table_command_supported_count": godot["direct_table_command_supported_count"],
        "supported_macro_name_count": godot["supported_macro_name_count"],
    }


def manifest_entry_for(exported, output_path):
    stats = exported["stats"]
    return {
        "category": "overworld_scrcmd_trace",
        "path": to_project_path(output_path),
        "source_file_count": stats["source_file_count"],
        "flow_count": stats["flow_count"],
        "script_cmd_table_entry_count": stats["script_cmd_table_entry_count"],
        "scrcmd_function_count": stats["scrcmd_function_count"],
        "event_macro_count": stats["event_macro_count"],
        "native_wait_function_count": stats["native_wait_function_count"],
        "supported_generated_op_count": stats["supported_generated_op_count"],
        "unsupported_count": stats["unsupported_count"],
    }


def build_export(source_root):
    source_root = Path(source_root)
    table_text = read_text(source_root / "data/script_cmd_table.inc")
    scrcmd_text = read_text(source_root / "src/scrcmd.c")
    macro_text = read_text(source_root / "asm/macros/event.inc")
    presence = source_file_presence(source_root)
    locations = symbol_locations(source_root)
    table_rows = parse_script_cmd_table(table_text)
    table_handlers = {row["handler"] for row in table_rows}
    functions = parse_scrcmd_functions(scrcmd_text, table_handlers)
    macro_rows = parse_event_macros(macro_text)
    current_vm = parse_current_script_vm_support(REPO_ROOT)
    table_rows = enrich_table_with_functions_and_vm(table_rows, functions, current_vm)
    flow_rows = source_flow_rows()
    stats = build_stats(presence, locations, table_rows, functions, macro_rows, current_vm, flow_rows)

    return {
        "schema_version": 1,
        "generated_by": GENERATED_BY,
        "source_root": str(source_root),
        "source_files": presence,
        "required_symbols": locations,
        "script_command_table": table_rows,
        "scrcmd_functions": functions,
        "event_macros": macro_rows,
        "source_flows": flow_rows,
        "godot_current": current_godot_summary(table_rows, macro_rows, current_vm),
        "godot_trace_owners": {
            "importer": [
                "tools/importer/export_event_scripts.py",
                GENERATED_BY,
            ],
            "runtime": [
                "scripts/autoload/script_vm.gd",
                "scripts/autoload/event_manager.gd",
                "scripts/autoload/map_runtime.gd",
            ],
            "generated_data": [
                "data/generated/scripts/*.json",
                "data/generated/overworld/scrcmd_trace.json",
            ],
            "tests": [
                "tools/importer/export_overworld_scrcmd_trace_smoke.py",
                "tools/godot_smoke/script_vm_smoke.gd",
            ],
        },
        "visual_effect_policy": {
            "palette_and_affine": "Use Godot-native textures, materials, shaders, animation tracks, resources, and renderer state for palette, tint, scale, rotation, affine, fade, weather, and field effects while preserving source timing, ordering, rhythm, and visible result where practical.",
            "gba_runtime_limits": "Do not recreate GBA palette-bank, VRAM, OAM, DMA, or binary tile memory limits at runtime unless a gameplay rule explicitly depends on them.",
            "audio": "Audio playback remains out of scope; sound/music/fanfare/cry symbols and timing intent stay metadata_only/unsupported until audio scope is reopened.",
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

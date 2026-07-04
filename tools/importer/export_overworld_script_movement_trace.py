#!/usr/bin/env python3
"""Export source-traced overworld script movement coverage."""

import argparse
import json
import re
import sys
from pathlib import Path

from export_map import write_json, write_manifest
from source_probe import load_config, to_project_path


GENERATED_BY = "tools/importer/export_overworld_script_movement_trace.py"
REPORT_PATH = Path("overworld/script_movement_trace.json")

SOURCE_FILES = [
    "include/script_movement.h",
    "src/script_movement.c",
    "include/script.h",
    "src/script.c",
    "src/scrcmd.c",
    "include/event_data.h",
    "src/event_data.c",
    "include/event_object_movement.h",
    "src/event_object_movement.c",
    "include/constants/event_objects.h",
    "include/constants/event_object_movement.h",
    "include/config/overworld.h",
    "include/task.h",
    "src/task.c",
    "asm/macros/event.inc",
    "asm/macros/movement.inc",
    "data/scripts/movement.inc",
    "data/scripts/follower.inc",
    "src/follower_npc.c",
    "include/follower_npc.h",
    "tools/mapjson/mapjson.cpp",
]

REQUIRED_SYMBOLS = [
    "ScriptMovement_StartObjectMovementScript",
    "ScriptMovement_IsObjectMovementFinished",
    "ScriptMovement_IsAllObjectMovementFinished",
    "ScriptMovement_UnfreezeObjectEvents",
    "ScriptMovement_StartMoveObjects",
    "GetMoveObjectsTaskId",
    "ScriptMovement_TryAddNewMovement",
    "GetMovementScriptIdFromObjectEventId",
    "LoadObjectEventIdPtrFromMovementScript",
    "SetObjectEventIdAtMovementScript",
    "LoadObjectEventIdFromMovementScript",
    "ClearMovementScriptFinished",
    "SetMovementScriptFinished",
    "IsMovementScriptFinished",
    "SetMovementScript",
    "GetMovementScript",
    "ScriptMovement_AddNewMovement",
    "ScriptMovement_UnfreezeActiveObjects",
    "ScriptMovement_MoveObjects",
    "ScriptMovement_TakeStep",
    "sMovementScripts",
    "OBJECT_EVENTS_COUNT",
    "NUM_TASK_DATA",
    "CreateTask",
    "DestroyTask",
    "FuncIsActiveTask",
    "FindTaskIdByFunc",
    "gTasks",
    "TryGetObjectEventIdByLocalIdAndMap",
    "GetObjectEventIdByLocalId",
    "ObjectEventSetHeldMovement",
    "ObjectEventIsHeldMovementActive",
    "ObjectEventClearHeldMovementIfFinished",
    "ObjectEventGetHeldMovementActionId",
    "FreezeObjectEvent",
    "UnfreezeObjectEvent",
    "ClearObjectEventMovement",
    "GetObjectObjectCollidesWith",
    "GetFollowerObject",
    "EnterPokeballMovement",
    "OW_FOLLOWERS_SCRIPT_MOVEMENT",
    "FLAG_SAFE_FOLLOWER_MOVEMENT",
    "IS_OW_MON_OBJ",
    "LOCALID_NONE",
    "LOCALID_PLAYER",
    "LOCALID_FOLLOWING_POKEMON",
    "OBJ_EVENT_ID_FOLLOWER",
    "MOVEMENT_ACTION_STEP_END",
    "MOVEMENT_ACTION_ENTER_POKEBALL",
    "ScrCmd_applymovement",
    "ScrCmd_applymovementat",
    "ScrCmd_waitmovement",
    "ScrCmd_waitmovementat",
    "Script_waitmovementall",
    "WaitForMovementFinish",
    "WaitForAllMovementFinish",
    "sMovingNpcId",
    "sMovingNpcMapGroup",
    "sMovingNpcMapNum",
    "Script_RequestEffects",
    "SCREFF_V1",
    "SCREFF_HARDWARE",
    "VarGet",
    "VarGetIfExist",
    "ScriptReadHalfword",
    "ScriptReadWord",
    "ScriptReadByte",
    "SetupNativeScript",
    "RunScriptCommand",
    "SCRIPT_MODE_NATIVE",
    "ScriptContext_Stop",
    "ScriptContext_Enable",
    "create_movement_action",
    "step_end",
]

TASK_DATA_LAYOUT = [
    {
        "slot": "gTasks[taskId].data[0]",
        "role": "finished bitset",
        "detail": "One bit per movement-script slot. ClearMovementScriptFinished clears a bit before starting; SetMovementScriptFinished sets it when the script hits MOVEMENT_ACTION_STEP_END.",
    },
    {
        "slot": "gTasks[taskId].data[1..NUM_TASK_DATA-1] as bytes",
        "role": "object-event id slots",
        "detail": "ScriptMovement_StartMoveObjects initializes every byte to 0xFF. ScriptMovement_TryAddNewMovement uses the 0xFF/LOCALID_PLAYER value as the free-slot sentinel before storing an object event id.",
    },
    {
        "slot": "sMovementScripts[OBJECT_EVENTS_COUNT]",
        "role": "movement script pointers",
        "detail": "Each movement slot owns a pointer into a bytecode movement script. ScriptMovement_TakeStep advances the pointer only after ObjectEventSetHeldMovement accepts the next action.",
    },
]

SCRCMD_APPLYMOVEMENT_ORDER = [
    "ScrCmd_applymovement reads a halfword target and resolves it through VarGet.",
    "ScrCmd_applymovement reads a movement-script pointer with ScriptReadWord.",
    "It requests SCREFF_V1 | SCREFF_HARDWARE effects for source effect analysis.",
    "Follower or overworld-mon targets with frozen animation have ClearObjectEventMovement called and animCmdIndex reset to 0 before movement starts.",
    "directionOverwrite is cleared on the target object event before queueing the script.",
    "ScriptMovement_StartObjectMovementScript is called with the current map number/group and the movement pointer.",
    "sMovingNpcId is updated to the resolved local id for later waitmovement 0 semantics.",
    "Follower safety flags may be cleared when a non-follower target moves and FLAG_SAFE_FOLLOWER_MOVEMENT is not set.",
    "The command returns FALSE so bytecode execution can continue without blocking until a later wait command.",
]

SCRCMD_APPLYMOVEMENTAT_ORDER = [
    "ScrCmd_applymovementat reads target through VarGet, movement pointer through ScriptReadWord, then explicit mapGroup/mapNum bytes.",
    "It requests SCREFF_V1 | SCREFF_HARDWARE effects.",
    "It clears target directionOverwrite and calls ScriptMovement_StartObjectMovementScript with the explicit map number/group.",
    "It updates sMovingNpcId to the resolved local id and returns FALSE.",
]

TARGET_RESOLUTION_RULES = [
    "applymovement, applymovementat, waitmovement, and waitmovementat all pass their halfword target through VarGet before use.",
    "A literal object local-id constant remains that numeric local id; a VAR_* operand can point to a runtime local id.",
    "tools/mapjson/mapjson.cpp emits generated LOCALID_* constants as object template index + 1, matching source comments in include/constants/event_objects.h.",
    "LOCALID_NONE is 0. waitmovement 0 does not overwrite sMovingNpcId, so it waits for the last moved object.",
    "LOCALID_PLAYER is 255 and is a local id, not a gObjectEvents slot. ScriptMovement slots store object event ids after TryGetObjectEventIdByLocalIdAndMap resolves the local id.",
    "OBJ_EVENT_ID_FOLLOWER / LOCALID_FOLLOWING_POKEMON is a special follower target with extra animation and Pokeball wait rules.",
    "waitmovement uses the current map group/number; waitmovementat uses explicit map group/number bytes.",
]

TASK_CREATION_AND_ADD_RULES = [
    "ScriptMovement_StartObjectMovementScript resolves localId/mapNum/mapGroup to an object-event id with TryGetObjectEventIdByLocalIdAndMap; a failed lookup returns TRUE, treating the movement as finished/no-op.",
    "If ScriptMovement_MoveObjects is not already active, ScriptMovement_StartMoveObjects creates it at priority 50.",
    "ScriptMovement_StartMoveObjects initializes movement slot bytes to 0xFF through gTasks data[1..].",
    "ScriptMovement_TryAddNewMovement first searches for the target object event id. If the same object is already moving and not finished, it returns TRUE without replacing the script.",
    "If an existing slot for that object is finished, it reuses the slot with ScriptMovement_AddNewMovement.",
    "If no target slot exists, it searches for the free 0xFF sentinel and writes the new object event id there.",
    "ScriptMovement_AddNewMovement clears the finished bit, stores the movement-script pointer, and writes the object-event id into the slot.",
]

TASK_TICK_ORDER = [
    "ScriptMovement_MoveObjects runs once per task tick and scans every movement slot in source order.",
    "For every non-0xFF object event id, it calls ScriptMovement_TakeStep with the slot id, object event id, and current movement pointer.",
    "If the object has an active held movement and ObjectEventClearHeldMovementIfFinished says it is not done, no new movement byte is consumed this tick.",
    "During that held-movement wait, the follower collision branch can force an active follower into EnterPokeballMovement when configured.",
    "If no held movement is active, ScriptMovement_TakeStep reads the next movement byte.",
    "MOVEMENT_ACTION_STEP_END sets the slot finished bit and freezes the object event.",
    "Otherwise ObjectEventSetHeldMovement is attempted; only on success does ScriptMovement_TakeStep advance the script pointer.",
]

WAITMOVEMENT_RULES = [
    "ScrCmd_waitmovement reads localId through VarGet and requests SCREFF_V1 | SCREFF_HARDWARE effects.",
    "If the resolved local id is not LOCALID_NONE, it replaces sMovingNpcId; otherwise it preserves the last moved target.",
    "It stores the current map group/number into sMovingNpcMapGroup and sMovingNpcMapNum.",
    "It installs WaitForMovementFinish with SetupNativeScript and returns TRUE.",
    "RunScriptCommand stays in SCRIPT_MODE_NATIVE until the native function returns TRUE, so bytecode execution is blocked across frames.",
    "WaitForMovementFinish calls ScriptMovement_IsObjectMovementFinished for sMovingNpcId/mapNum/mapGroup.",
    "If a non-follower movement caused the follower to enter a Pokeball, WaitForMovementFinish also waits for the follower movement to finish before returning TRUE.",
]

WAITMOVEMENTAT_AND_ALL_RULES = [
    "ScrCmd_waitmovementat matches waitmovement but reads explicit mapGroup/mapNum bytes before installing the native wait.",
    "Script_waitmovementall is a callnative helper from asm/macros/event.inc, not a normal script opcode.",
    "Script_waitmovementall installs WaitForAllMovementFinish, sets waitAfterCallNative, and polls ScriptMovement_IsAllObjectMovementFinished.",
    "ScriptMovement_IsAllObjectMovementFinished scans every non-0xFF slot and requires its finished bit to be set.",
]

SIMULTANEOUS_MOVEMENT_RULES = [
    "Multiple applymovement commands can be issued before a waitmovement; every accepted target occupies a separate ScriptMovement slot.",
    "All active slots tick from the same ScriptMovement_MoveObjects task, so objects progress concurrently rather than one script fully completing first.",
    "Slot scan order is 0..OBJECT_EVENTS_COUNT-1, which matters when two movements interact with follower collision, occupancy, or side effects in the same tick.",
    "waitmovement 0 waits only for sMovingNpcId, the last target set by applymovement/waitmovement; Script_waitmovementall is the separate all-target wait path.",
    "A second applymovement targeting an unfinished object is ignored by ScriptMovement_TryAddNewMovement instead of replacing the active script.",
]

MOVEMENT_BYTECODE_RULES = [
    "asm/macros/movement.inc emits each movement macro as one movement-action byte.",
    "step_end emits MOVEMENT_ACTION_STEP_END and terminates a movement script.",
    "The ScriptMovement task does not inspect labels or macro names; it only consumes action bytes.",
    "Visible timing comes from ObjectEventSetHeldMovement and the movement action function table in event_object_movement.c, not from the script bytecode parser.",
]

GODOT_CURRENT_RULES = [
    "ScriptVM resolves generated movement labels and records target, raw_target, movement_label, structured steps, net_delta, final_facing, and unsupported steps.",
    "ScriptVM resolves waitmovement 0 to last_movement_target and records a waitmovement effect, but it does not block on a live movement task.",
    "MapRuntime.apply_script_movements fast-forwards net deltas into object-event or player state during dispatch.",
    "No Godot owner currently runs a source-equivalent ScriptMovement_MoveObjects task, held movement queue, per-frame collision, or native wait continuation.",
]

UNSUPPORTED = [
    {
        "code": "script_movement_async_task_runtime_pending",
        "status": "unsupported",
        "source": "src/script_movement.c:ScriptMovement_MoveObjects",
        "detail": "Godot does not yet own a live movement task that ticks active movement-script slots across frames.",
    },
    {
        "code": "held_movement_queue_pending",
        "status": "unsupported",
        "source": "src/event_object_movement.c:ObjectEventSetHeldMovement/ObjectEventExecHeldMovementAction",
        "detail": "ScriptVM emits movement summaries instead of queueing source movement action ids and waiting for heldMovementFinished.",
    },
    {
        "code": "waitmovement_native_blocking_pending",
        "status": "unsupported",
        "source": "src/scrcmd.c:ScrCmd_waitmovement + src/script.c:SetupNativeScript",
        "detail": "waitmovement is recorded as an effect but does not currently suspend and resume ScriptVM on movement completion.",
    },
    {
        "code": "simultaneous_movement_timing_pending",
        "status": "unsupported",
        "source": "src/script_movement.c:ScriptMovement_MoveObjects",
        "detail": "Concurrent per-slot ticking, source slot scan order, and same-frame interaction effects are not runtime-equivalent yet.",
    },
    {
        "code": "player_applymovement_queue_pending",
        "status": "unsupported",
        "source": "src/script_movement.c + src/field_player_avatar.c",
        "detail": "Player-targeted applymovement is fast-forwarded instead of entering a player/object-event movement queue with source animation timing.",
    },
    {
        "code": "applymovementat_cross_map_pending",
        "status": "unsupported",
        "source": "src/scrcmd.c:ScrCmd_applymovementat/ScrCmd_waitmovementat",
        "detail": "Explicit mapGroup/mapNum movement targets are preserved as metadata but only current-map effects are applied safely.",
    },
    {
        "code": "follower_pokeball_wait_pending",
        "status": "unsupported",
        "source": "src/script_movement.c:ScriptMovement_TakeStep + src/scrcmd.c:WaitForMovementFinish",
        "detail": "Follower collision forcing EnterPokeballMovement and the extra wait for MOVEMENT_ACTION_ENTER_POKEBALL are traced but not implemented.",
    },
    {
        "code": "ow_mon_movement_clear_pending",
        "status": "unsupported",
        "source": "src/scrcmd.c:ScrCmd_applymovement",
        "detail": "The frozen follower/overworld-mon ClearObjectEventMovement and animCmdIndex reset path is not implemented in Godot.",
    },
    {
        "code": "movement_action_collision_timing_pending",
        "status": "unsupported",
        "source": "src/event_object_movement.c:MovementAction_*",
        "detail": "Movement action collision checks, delays, jumps, stairs, slides, currents, and per-frame animation timing remain future object-event runtime work.",
    },
    {
        "code": "dynamic_var_target_resolution_first_pass",
        "status": "first_pass",
        "source": "src/scrcmd.c:VarGet(ScriptReadHalfword(ctx))",
        "detail": "ScriptVM follows VarGet-style target resolution for generated variables but lacks the full source event-data memory model.",
    },
    {
        "code": "script_waitmovementall_pending",
        "status": "unsupported",
        "source": "src/scrcmd.c:Script_waitmovementall",
        "detail": "The callnative all-movement wait helper is traced but not a live async ScriptVM wait path.",
    },
    {
        "code": "palette_affine_effects_godot_native",
        "status": "metadata_only",
        "source": "Project porting constraint",
        "detail": "Movement actions that use palette, tint, scale, rotation, affine, or reflection effects should be implemented with Godot-native presentation while preserving source timing and visible result.",
    },
    {
        "code": "audio_playback_pending",
        "status": "metadata_only",
        "source": "Movement-related scripts and field effects",
        "detail": "Sound symbols and timing intent remain metadata only; real audio playback is intentionally out of scope for now.",
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


def movement_macro_records(source_root):
    path = source_root / "asm/macros/movement.inc"
    if not path.exists():
        return []
    text = read_text(path)
    records = []
    pattern = re.compile(r"^\s*create_movement_action\s+([A-Za-z0-9_]+),\s*([A-Za-z0-9_]+)", re.MULTILINE)
    for match in pattern.finditer(text):
        records.append({"macro": match.group(1), "movement_action": match.group(2)})
    return records


def source_flow_rows():
    return [
        {
            "id": "script_command_applymovement_entry",
            "source_entry": "src/scrcmd.c:ScrCmd_applymovement",
            "status": "metadata_only",
            "critical_order": SCRCMD_APPLYMOVEMENT_ORDER,
            "godot_current": [
                "ScriptVM records a movement effect and continues synchronously.",
            ],
            "gaps": [
                "No live ScriptMovement task or held movement queue exists in Godot yet.",
            ],
        },
        {
            "id": "script_command_applymovementat_entry",
            "source_entry": "src/scrcmd.c:ScrCmd_applymovementat",
            "status": "metadata_only",
            "critical_order": SCRCMD_APPLYMOVEMENTAT_ORDER,
            "godot_current": [
                "ScriptVM stores explicit map_group/map_num metadata when present.",
            ],
            "gaps": [
                "Cross-map object-event movement application is intentionally not source-equivalent yet.",
            ],
        },
        {
            "id": "movement_target_resolution",
            "source_entry": "src/scrcmd.c + include/constants/event_objects.h + tools/mapjson/mapjson.cpp",
            "status": "first_pass",
            "critical_order": TARGET_RESOLUTION_RULES,
            "godot_current": [
                "ScriptVM resolves raw targets through generated constants and GameState vars for the first slice.",
            ],
            "gaps": [
                "Full event-data memory and every dynamic local-id path are not complete.",
            ],
        },
        {
            "id": "movement_task_creation_and_slot_layout",
            "source_entry": "src/script_movement.c:ScriptMovement_StartMoveObjects",
            "status": "metadata_only",
            "critical_order": TASK_CREATION_AND_ADD_RULES,
            "godot_current": [
                "There is no Godot movement slot owner yet.",
            ],
            "gaps": [
                "Task priority, slot reuse, and 0xFF free-slot semantics are metadata only.",
            ],
        },
        {
            "id": "add_new_movement_replacement_rules",
            "source_entry": "src/script_movement.c:ScriptMovement_TryAddNewMovement",
            "status": "metadata_only",
            "critical_order": [
                "unfinished same-object movement is not replaced",
                "finished same-object movement reuses the existing slot",
                "new objects use the first free 0xFF slot",
                "script pointer and object-event id are stored together only after the finished bit is cleared",
            ],
            "godot_current": [
                "ScriptVM appends movement result dictionaries without slot conflict rules.",
            ],
            "gaps": [
                "Replacing/ignoring active movements according to source slot state is pending.",
            ],
        },
        {
            "id": "per_tick_take_step_order",
            "source_entry": "src/script_movement.c:ScriptMovement_MoveObjects/ScriptMovement_TakeStep",
            "status": "metadata_only",
            "critical_order": TASK_TICK_ORDER,
            "godot_current": [
                "MapRuntime applies net deltas in one dispatch pass.",
            ],
            "gaps": [
                "Per-frame byte consumption, held action completion, and slot scan order are pending.",
            ],
        },
        {
            "id": "movement_script_completion_and_freeze",
            "source_entry": "src/script_movement.c:ScriptMovement_TakeStep",
            "status": "metadata_only",
            "critical_order": [
                "MOVEMENT_ACTION_STEP_END does not advance the script pointer further",
                "the movement slot finished bit is set",
                "FreezeObjectEvent is called on the moved object",
                "ScriptMovement_UnfreezeObjectEvents can unfreeze active objects and destroy the task",
            ],
            "godot_current": [
                "ScriptVM records final_facing and net_delta; lock/release are separate effects.",
            ],
            "gaps": [
                "Source freeze/unfreeze lifecycle tied to script movement completion is not implemented.",
            ],
        },
        {
            "id": "waitmovement_native_wait",
            "source_entry": "src/scrcmd.c:ScrCmd_waitmovement/WaitForMovementFinish",
            "status": "first_pass",
            "critical_order": WAITMOVEMENT_RULES,
            "godot_current": [
                "ScriptVM records waitmovement with raw and resolved targets; waitmovement 0 uses last_movement_target.",
            ],
            "gaps": [
                "Native wait suspension/resume is not implemented.",
            ],
        },
        {
            "id": "waitmovementat_and_waitmovementall",
            "source_entry": "src/scrcmd.c:ScrCmd_waitmovementat/Script_waitmovementall",
            "status": "metadata_only",
            "critical_order": WAITMOVEMENTAT_AND_ALL_RULES,
            "godot_current": [
                "waitmovementat metadata is recorded when parsed; waitmovementall is not a runtime path.",
            ],
            "gaps": [
                "Explicit-map native waits and all-slot native waits are pending.",
            ],
        },
        {
            "id": "simultaneous_movement_semantics",
            "source_entry": "src/script_movement.c:ScriptMovement_MoveObjects",
            "status": "unsupported",
            "critical_order": SIMULTANEOUS_MOVEMENT_RULES,
            "godot_current": [
                "Multiple movement effects can be applied in one result pass, but not as concurrent per-frame tasks.",
            ],
            "gaps": [
                "Source-equivalent concurrent movement timing and same-frame interactions are pending.",
            ],
        },
        {
            "id": "follower_and_ow_mon_exceptions",
            "source_entry": "src/scrcmd.c + src/script_movement.c + data/scripts/follower.inc",
            "status": "metadata_only",
            "critical_order": [
                "applymovement can clear frozen follower or overworld-mon movement before queueing a script",
                "moving a non-follower can clear FLAG_SAFE_FOLLOWER_MOVEMENT depending on source conditions",
                "ScriptMovement_TakeStep can force a colliding follower into EnterPokeballMovement",
                "WaitForMovementFinish can wait for follower EnterPokeballMovement before releasing the script",
            ],
            "godot_current": [
                "Follower object-event behavior is not source-equivalent yet.",
            ],
            "gaps": [
                "Follower Pokeball and overworld-mon movement exceptions are metadata only.",
            ],
        },
        {
            "id": "godot_current_script_movement_mapping",
            "source_entry": "Godot runtime owner map",
            "status": "first_pass",
            "critical_order": GODOT_CURRENT_RULES,
            "godot_current": [
                "Current behavior is useful for first-slice scripts, but the report keeps it marked below source-equivalent.",
            ],
            "gaps": [
                "Add a Godot-native async movement scheduler before closing runtime TODOs for applymovement/waitmovement.",
            ],
        },
    ]


def manifest_entry_for(exported, output_path):
    stats = exported["stats"]
    return {
        "category": "overworld_script_movement_trace",
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
    presence = source_file_presence(source_root)
    locations = symbol_locations(source_root)
    missing_symbols = sorted(
        symbol
        for symbol, occurrences in locations.items()
        if not occurrences
    )
    flow_rows = source_flow_rows()
    status_counts = {}
    for row in flow_rows:
        status = row["status"]
        status_counts[status] = status_counts.get(status, 0) + 1
    unsupported_status_counts = {}
    for row in UNSUPPORTED:
        status = row["status"]
        unsupported_status_counts[status] = unsupported_status_counts.get(status, 0) + 1
    movement_macros = movement_macro_records(source_root)
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
        "movement_macro_count": len(movement_macros),
    }
    return {
        "schema_version": 1,
        "generated_by": GENERATED_BY,
        "source_root": str(source_root),
        "source_files": presence,
        "required_symbols": locations,
        "task_data_layout": TASK_DATA_LAYOUT,
        "scrcmd_applymovement_order": SCRCMD_APPLYMOVEMENT_ORDER,
        "scrcmd_applymovementat_order": SCRCMD_APPLYMOVEMENTAT_ORDER,
        "target_resolution_rules": TARGET_RESOLUTION_RULES,
        "task_creation_and_add_rules": TASK_CREATION_AND_ADD_RULES,
        "task_tick_order": TASK_TICK_ORDER,
        "waitmovement_rules": WAITMOVEMENT_RULES,
        "waitmovementat_and_all_rules": WAITMOVEMENTAT_AND_ALL_RULES,
        "simultaneous_movement_rules": SIMULTANEOUS_MOVEMENT_RULES,
        "movement_bytecode_rules": MOVEMENT_BYTECODE_RULES,
        "movement_macro_records": movement_macros,
        "source_flows": flow_rows,
        "godot_trace_owners": {
            "runtime": [
                "scripts/autoload/script_vm.gd",
                "scripts/autoload/map_runtime.gd",
                "scripts/autoload/event_manager.gd",
            ],
            "presentation": [
                "scripts/overworld/player_controller.gd",
                "scripts/overworld/object_event_spawner.gd",
                "scripts/overworld/object_event_placeholder.gd",
            ],
            "generated_data": [
                "data/generated/scripts/*.json",
                "tools/importer/export_event_scripts.py",
            ],
            "tests": [
                "tools/godot_smoke/script_vm_smoke.gd",
                "tools/godot_smoke/map_runtime_smoke.gd",
                "tools/godot_smoke/event_manager_smoke.gd",
            ],
        },
        "visual_effect_policy": {
            "palette_and_affine": "Use Godot-native materials, shaders, animation, and resources for palette, tint, scale, rotation, affine, and reflection-like movement effects while preserving source timing and visible result where practical.",
            "gba_runtime_limits": "Do not recreate GBA palette-bank, VRAM, OAM, or movement byte storage limits at runtime unless a gameplay rule explicitly depends on them.",
            "audio": "Sound/music/fanfare symbols stay metadata_only/unsupported until audio scope is reopened.",
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

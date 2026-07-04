#!/usr/bin/env python3
"""Export source-traced overworld event-object lock coverage."""

import argparse
import json
import re
import sys
from pathlib import Path

from export_map import write_json, write_manifest
from source_probe import load_config, to_project_path


GENERATED_BY = "tools/importer/export_overworld_event_object_lock_trace.py"
REPORT_PATH = Path("overworld/event_object_lock_trace.json")

SOURCE_FILES = [
    "include/event_object_lock.h",
    "src/event_object_lock.c",
    "include/event_object_movement.h",
    "src/event_object_movement.c",
    "include/field_player_avatar.h",
    "src/field_player_avatar.c",
    "include/script.h",
    "src/script.c",
    "include/script_movement.h",
    "src/script_movement.c",
    "src/scrcmd.c",
    "include/event_data.h",
    "src/event_data.c",
    "include/task.h",
    "src/task.c",
    "include/trainer_see.h",
    "src/trainer_see.c",
    "include/follower_npc.h",
    "src/follower_npc.c",
    "include/field_message_box.h",
    "include/constants/event_objects.h",
    "include/constants/event_object_movement.h",
    "include/constants/field_effects.h",
    "include/constants/flags.h",
    "include/constants/global.h",
    "include/global.fieldmap.h",
    "include/config/overworld.h",
    "asm/macros/event.inc",
]

REQUIRED_SYMBOLS = [
    "IsPlayerStandingStill",
    "Task_FreezePlayer",
    "IsFreezePlayerFinished",
    "FreezeObjects_WaitForPlayer",
    "Task_FreezeSelectedObjectAndPlayer",
    "IsFreezeSelectedObjectAndPlayerFinished",
    "FreezeObjects_WaitForPlayerAndSelected",
    "ScriptUnfreezeObjectEvents",
    "UnionRoom_UnlockPlayerAndChatPartner",
    "Script_FacePlayer",
    "Script_ClearHeldMovement",
    "Task_FreezeObjectAndPlayer",
    "FreezeForApproachingTrainers",
    "IsFreezeObjectAndPlayerFinished",
    "ScrCmd_faceplayer",
    "ScrCmd_lockall",
    "ScrCmd_lock",
    "ScrCmd_releaseall",
    "ScrCmd_release",
    "ScrCmd_selectapproachingtrainer",
    "ScrCmd_lockfortrainer",
    "SetupNativeScript",
    "Script_RequestEffects",
    "SCREFF_V1",
    "SCREFF_HARDWARE",
    "HideFieldMessageBox",
    "gMsgBoxIsCancelable",
    "gSelectedObjectEvent",
    "gObjectEvents",
    "gPlayerAvatar",
    "T_TILE_TRANSITION",
    "PlayerFreeze",
    "StopPlayerAvatar",
    "GetPlayerFacingDirection",
    "PlayerForceSetHeldMovement",
    "FreezeObjectEvent",
    "FreezeObjectEvents",
    "FreezeObjectEventsExceptOne",
    "FreezeObjectEventsExceptTwo",
    "UnfreezeObjectEvent",
    "UnfreezeObjectEvents",
    "ObjectEventClearHeldMovementIfFinished",
    "ObjectEventClearHeldMovementIfActive",
    "ScriptMovement_UnfreezeObjectEvents",
    "ObjectEventFaceOppositeDirection",
    "GetFaceDirectionMovementAction",
    "ObjectEventSetHeldMovement",
    "ObjectEventForceSetHeldMovement",
    "GetOppositeDirection",
    "SetObjectEventDirection",
    "ObjectEventTurn",
    "TryGetObjectEventIdByLocalIdAndMap",
    "GetObjectEventIdByLocalIdAndMap",
    "GetObjectEventIdByLocalId",
    "GetFollowerObject",
    "PlayerHasFollowerNPC",
    "GetFollowerNPCObjectId",
    "DetermineFollowerNPCDirection",
    "FLAG_SAFE_FOLLOWER_MOVEMENT",
    "OBJ_EVENT_ID_FOLLOWER",
    "OBJ_EVENT_ID_NPC_FOLLOWER",
    "LOCALID_PLAYER",
    "OBJ_EVENT_ID_DYNAMIC_BASE",
    "OBJECT_EVENTS_COUNT",
    "CreateTask",
    "DestroyTask",
    "FuncIsActiveTask",
    "gTasks",
    "GetCurrentApproachingTrainerObjectEventId",
    "GetChosenApproachingTrainerObjectEventId",
    "gNoOfApproachingTrainers",
    "gApproachingTrainers",
    "ClearObjectEventMovement",
    "MOVEMENT_ACTION_FACE_PLAYER",
    "FLDEFF_EXCLAMATION_MARK_ICON",
]

LOCKALL_ORDER = [
    "ScrCmd_lockall requests SCREFF_V1 | SCREFF_HARDWARE effects.",
    "If IsOverworldLinkActive is true, the command returns FALSE and does not install a freeze wait.",
    "Otherwise it snapshots the follower object, calls FreezeObjects_WaitForPlayer, and installs IsFreezePlayerFinished through SetupNativeScript.",
    "FreezeObjects_WaitForPlayer freezes all active non-player objects immediately, then creates Task_FreezePlayer at priority 80.",
    "Task_FreezePlayer polls IsPlayerStandingStill; once the player is no longer in T_TILE_TRANSITION it calls PlayerFreeze and destroys itself.",
    "IsFreezePlayerFinished keeps the script in native mode while Task_FreezePlayer exists; after the task ends it calls StopPlayerAvatar and returns TRUE.",
    "If FLAG_SAFE_FOLLOWER_MOVEMENT is set and a follower exists, lockall unfreezes the follower after scheduling the player wait.",
]

LOCK_SELECTED_ORDER = [
    "ScrCmd_lock requests SCREFF_V1 | SCREFF_HARDWARE effects.",
    "If link mode is active, it returns FALSE without locking.",
    "When gSelectedObjectEvent is active, FreezeObjects_WaitForPlayerAndSelected freezes all active non-player objects except the selected object.",
    "Task_FreezeSelectedObjectAndPlayer then waits for both the player to stop tile-transitioning and the selected object to finish singleMovementActive.",
    "The selected object can be frozen immediately if it has no active single movement at task creation time.",
    "The native wait IsFreezeSelectedObjectAndPlayerFinished calls StopPlayerAvatar only after the task has destroyed itself.",
    "If the selected object is the follower local id, the follower is kept frozen; otherwise an existing follower is unfreezed after the lock setup.",
    "When the selected object is not active, ScrCmd_lock falls back to the lockall-style player-only wait path.",
]

PLAYER_FREEZE_RULES = [
    "IsPlayerStandingStill returns FALSE while gPlayerAvatar.tileTransitionState is T_TILE_TRANSITION.",
    "PlayerFreeze only writes a face-direction held movement when the player is at tile center or not moving.",
    "PlayerFreeze skips forcing that held movement while the player is using the Acro Bike on a bumpy slope.",
    "StopPlayerAvatar clears player object odd bits, preserves current facing through SetObjectEventDirection, and performs bike bumpy-slope counter cleanup when relevant.",
]

OBJECT_FREEZE_RULES = [
    "FreezeObjectEvent returns TRUE without changing state if heldMovementActive or frozen is already true.",
    "Otherwise it sets objectEvent->frozen, backs up sprite animPaused and affineAnimPaused, then pauses both animation channels.",
    "FreezeObjectEvents freezes every active object except gPlayerAvatar.objectEventId.",
    "FreezeObjectEventsExceptOne and FreezeObjectEventsExceptTwo keep one or two specified object-event ids moving while freezing the rest.",
    "UnfreezeObjectEvent clears frozen only on active frozen objects and restores the backed-up sprite animPaused and affineAnimPaused values.",
    "UnfreezeObjectEvents scans every active object event and calls UnfreezeObjectEvent.",
]

RELEASE_ORDER = [
    "ScrCmd_releaseall and ScrCmd_release request SCREFF_V1 | SCREFF_HARDWARE effects.",
    "Both commands clear follower movement first if a follower exists and its sprite data[1] indicates the shadowing state.",
    "Both hide the field message box before unfreezing movement state.",
    "release clears held movement for the active selected object before clearing the player held movement.",
    "releaseall skips the selected-object clear and only clears the player held movement.",
    "Both call ScriptMovement_UnfreezeObjectEvents, then UnfreezeObjectEvents, then reset gMsgBoxIsCancelable to FALSE.",
    "ScriptUnfreezeObjectEvents and UnionRoom_UnlockPlayerAndChatPartner expose related helper paths with the same player clear and unfreeze ordering.",
]

FACEPLAYER_ORDER = [
    "ScrCmd_faceplayer requests SCREFF_V1 | SCREFF_HARDWARE effects.",
    "If the selected object is a visible follower NPC, it derives a follower-facing direction with DetermineFollowerNPCDirection and starts the matching Common_Movement_Face* script.",
    "For ordinary selected objects, it calls ObjectEventFaceOppositeDirection with GetPlayerFacingDirection.",
    "GetPlayerFacingDirection returns the player object's current facingDirection.",
    "ObjectEventFaceOppositeDirection queues a held movement using GetFaceDirectionMovementAction(GetOppositeDirection(direction)).",
    "The actual face action passes through ObjectEventSetHeldMovement and the movement-action table before visible facing changes are complete.",
]

SELECTED_OBJECT_RULES = [
    "gSelectedObjectEvent is a runtime object-event id, not a local id.",
    "Player-facing interactions and trainer-see setup assign gSelectedObjectEvent before a script uses lock, faceplayer, release, or trainer battle helpers.",
    "GetObjectEventIdByLocalIdAndMap resolves script local ids to runtime object-event ids and handles follower special local ids before dynamic local-id lookup.",
    "A failed TryGetObjectEventIdByLocalIdAndMap result uses OBJECT_EVENTS_COUNT as the sentinel.",
    "release, faceplayer, and selected-object lock all check gObjectEvents[gSelectedObjectEvent].active before touching the selected object.",
]

TRAINER_LOCK_RULES = [
    "ScrCmd_selectapproachingtrainer copies GetCurrentApproachingTrainerObjectEventId into gSelectedObjectEvent.",
    "ScrCmd_lockfortrainer requests SCREFF_V1 | SCREFF_HARDWARE effects and returns FALSE immediately in link mode.",
    "If the selected trainer object is active, FreezeForApproachingTrainers freezes all non-player objects except the approaching trainer or trainer pair.",
    "For one trainer it creates one Task_FreezeObjectAndPlayer at priority 80; for two trainers it creates tasks at priorities 80 and 81.",
    "Each Task_FreezeObjectAndPlayer waits for player standing still and for the trainer object to finish singleMovementActive before freezing them.",
    "Trainer-see setup plays the exclamation field effect, walks the trainer toward the player, turns the trainer with MOVEMENT_ACTION_FACE_PLAYER, then turns the player toward the trainer before the trainer script continues.",
    "If a follower object exists, FreezeForApproachingTrainers unfreezes it so it can move behind the player.",
]

GODOT_CURRENT_RULES = [
    "ScriptVM currently records lock, lockall, release, releaseall, and faceplayer as effect rows through _execute_basic_field_command.",
    "MSGBOX_NPC and MSGBOX_SIGN expand into source-shaped lock/face/wait/release effect sequences.",
    "EventManager applies movement and object effects during dispatch, but no owner stores live gSelectedObjectEvent, object frozen flags, native script wait tasks, or held face movements.",
    "TransitionSequencePlayer can lock field input for map/battle transition sequences, but this is not source-equivalent event-object freezing.",
    "PlayerController has a Godot input lock and source-backed first-slice player walk/turn presentation, but not PlayerFreeze/StopPlayerAvatar native wait semantics.",
]

UNSUPPORTED = [
    {
        "code": "event_object_lock_native_task_pending",
        "status": "unsupported",
        "source": "src/event_object_lock.c:Task_FreezePlayer/Task_FreezeSelectedObjectAndPlayer/Task_FreezeObjectAndPlayer",
        "detail": "Godot does not yet create per-frame lock tasks that wait for player tile-transition and object singleMovementActive completion.",
    },
    {
        "code": "selected_object_runtime_state_pending",
        "status": "unsupported",
        "source": "src/scrcmd.c:gSelectedObjectEvent users",
        "detail": "The current interaction path has target metadata but no source-equivalent gSelectedObjectEvent runtime channel shared by lock, faceplayer, release, and trainer helpers.",
    },
    {
        "code": "object_freeze_flags_pending",
        "status": "unsupported",
        "source": "src/event_object_movement.c:FreezeObjectEvent/UnfreezeObjectEvent",
        "detail": "Runtime object events do not yet carry frozen state, heldMovementActive gating, or source restore ordering for all object-event sprites.",
    },
    {
        "code": "sprite_anim_pause_restore_pending",
        "status": "unsupported",
        "source": "src/event_object_movement.c:spriteAnimPausedBackup/spriteAffineAnimPausedBackup",
        "detail": "Godot object-event sprites do not yet pause and restore normal and affine-style animations through a source-timed presentation owner.",
    },
    {
        "code": "player_freeze_stop_pending",
        "status": "unsupported",
        "source": "src/field_player_avatar.c:PlayerFreeze/StopPlayerAvatar",
        "detail": "Godot input locking is separate from the source PlayerFreeze held-movement and StopPlayerAvatar cleanup path.",
    },
    {
        "code": "faceplayer_held_movement_pending",
        "status": "unsupported",
        "source": "src/scrcmd.c:ScrCmd_faceplayer + src/event_object_movement.c:ObjectEventFaceOppositeDirection",
        "detail": "faceplayer is recorded as metadata and does not yet queue a held face movement or wait for visible facing completion.",
    },
    {
        "code": "release_unfreeze_runtime_pending",
        "status": "unsupported",
        "source": "src/scrcmd.c:ScrCmd_release/ScrCmd_releaseall",
        "detail": "release effects do not yet clear selected/player held movements, unfreeze ScriptMovement slots, restore object animation pause state, or hide a source field message box.",
    },
    {
        "code": "follower_lock_exception_pending",
        "status": "unsupported",
        "source": "src/scrcmd.c:ScrCmd_lock/ScrCmd_lockall + include/constants/flags.h:FLAG_SAFE_FOLLOWER_MOVEMENT",
        "detail": "Follower special-case freezing, follower face scripts, and safe-follower unfreeze behavior are traced but not runtime-equivalent.",
    },
    {
        "code": "lockfortrainer_trainer_see_pending",
        "status": "unsupported",
        "source": "src/scrcmd.c:ScrCmd_lockfortrainer + src/trainer_see.c",
        "detail": "Trainer approach locking, exclamation timing, approach movement, player turn, and lockfortrainer freeze tasks are not implemented in the overworld runtime yet.",
    },
    {
        "code": "native_wait_blocking_pending",
        "status": "unsupported",
        "source": "src/script.c:SetupNativeScript + src/scrcmd.c lock commands",
        "detail": "ScriptVM does not currently suspend and resume bytecode execution on lock native wait callbacks.",
    },
    {
        "code": "dynamic_local_id_full_model_first_pass",
        "status": "first_pass",
        "source": "src/event_object_movement.c:GetObjectEventIdByLocalIdAndMap",
        "detail": "Generated local-id aliases are resolved for first-slice maps, but the full source object-event id model and dynamic local-id paths remain incomplete.",
    },
    {
        "code": "palette_affine_effects_godot_native",
        "status": "metadata_only",
        "source": "Project porting constraint + src/event_object_movement.c:FreezeObjectEvent",
        "detail": "Palette, tint, scale, rotation, affine, and animation-pause effects should use Godot-native materials, shaders, animation tracks, or resources while preserving source timing and visible result.",
    },
    {
        "code": "audio_playback_pending",
        "status": "metadata_only",
        "source": "Trainer-see field effects and lock-adjacent scripts",
        "detail": "Sound/music/fanfare symbols and timing intent remain metadata only; real audio playback is intentionally out of scope for now.",
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


def source_flow_rows():
    return [
        {
            "id": "script_command_lockall_entry",
            "source_entry": "src/scrcmd.c:ScrCmd_lockall",
            "status": "metadata_only",
            "critical_order": LOCKALL_ORDER,
            "godot_current": [
                "ScriptVM records a lockall effect and keeps executing synchronously.",
            ],
            "gaps": [
                "No native wait callback, player freeze task, or object frozen state is active.",
            ],
        },
        {
            "id": "script_command_lock_selected_entry",
            "source_entry": "src/scrcmd.c:ScrCmd_lock + src/event_object_lock.c:FreezeObjects_WaitForPlayerAndSelected",
            "status": "metadata_only",
            "critical_order": LOCK_SELECTED_ORDER,
            "godot_current": [
                "ScriptVM records a lock effect without selected-object state.",
            ],
            "gaps": [
                "Selected-object task wait, follower exception, and object freeze state are pending.",
            ],
        },
        {
            "id": "player_freeze_wait_and_stop",
            "source_entry": "src/event_object_lock.c:IsPlayerStandingStill + src/field_player_avatar.c:PlayerFreeze/StopPlayerAvatar",
            "status": "metadata_only",
            "critical_order": PLAYER_FREEZE_RULES,
            "godot_current": [
                "PlayerController and TransitionSequencePlayer can lock input, but this does not model PlayerFreeze.",
            ],
            "gaps": [
                "Tile-transition polling, held face movement, and bike cleanup are pending.",
            ],
        },
        {
            "id": "object_event_freeze_and_unfreeze",
            "source_entry": "src/event_object_movement.c:FreezeObjectEvent/UnfreezeObjectEvent",
            "status": "metadata_only",
            "critical_order": OBJECT_FREEZE_RULES,
            "godot_current": [
                "MapRuntime tracks visible object occupancy and script-applied state, but not frozen animation state.",
            ],
            "gaps": [
                "Object-event sprite pause/restore, affine pause equivalents, and held movement gating are pending.",
            ],
        },
        {
            "id": "release_and_unfreeze_order",
            "source_entry": "src/scrcmd.c:ScrCmd_release/ScrCmd_releaseall + src/event_object_lock.c:ScriptUnfreezeObjectEvents",
            "status": "metadata_only",
            "critical_order": RELEASE_ORDER,
            "godot_current": [
                "ScriptVM records release/releaseall effects and EventManager does not run a release-state owner.",
            ],
            "gaps": [
                "Held movement clearing, message box hiding, ScriptMovement unfreeze, and animation restore ordering are pending.",
            ],
        },
        {
            "id": "faceplayer_selected_object",
            "source_entry": "src/scrcmd.c:ScrCmd_faceplayer",
            "status": "metadata_only",
            "critical_order": FACEPLAYER_ORDER,
            "godot_current": [
                "ScriptVM records faceplayer as an effect only.",
            ],
            "gaps": [
                "Held face movement, visible facing completion, and follower face scripts are pending.",
            ],
        },
        {
            "id": "selected_object_event_resolution",
            "source_entry": "src/event_object_movement.c:GetObjectEventIdByLocalIdAndMap + src/scrcmd.c:gSelectedObjectEvent",
            "status": "first_pass",
            "critical_order": SELECTED_OBJECT_RULES,
            "godot_current": [
                "MapRuntime indexes generated object events by source numeric local id and current interactions can find a facing target.",
            ],
            "gaps": [
                "There is no shared source-equivalent selected-object event id for ScriptVM command effects yet.",
            ],
        },
        {
            "id": "follower_lock_exceptions",
            "source_entry": "src/scrcmd.c:ScrCmd_lock/ScrCmd_lockall/ScrCmd_faceplayer",
            "status": "metadata_only",
            "critical_order": [
                "Follower local ids are special-cased in GetObjectEventIdByLocalIdAndMap.",
                "lock keeps a selected follower frozen but unfreezes other follower objects after lock setup.",
                "lockall conditionally unfreezes the follower only when FLAG_SAFE_FOLLOWER_MOVEMENT is set.",
                "faceplayer uses DetermineFollowerNPCDirection and Common_Movement_Face* for a visible follower selected object.",
            ],
            "godot_current": [
                "Follower runtime behavior is not source-equivalent yet.",
            ],
            "gaps": [
                "Follower object identity, face scripts, and safe-follower unfreeze rules are pending.",
            ],
        },
        {
            "id": "trainer_lockfortrainer_path",
            "source_entry": "src/scrcmd.c:ScrCmd_selectapproachingtrainer/ScrCmd_lockfortrainer + src/event_object_lock.c:FreezeForApproachingTrainers",
            "status": "metadata_only",
            "critical_order": TRAINER_LOCK_RULES,
            "godot_current": [
                "EventManager can hand off first-pass trainer battle requests, but trainer-see field approach is not source-equivalent.",
            ],
            "gaps": [
                "Approaching trainer task timing, exclamation field effect, player-facing wait, and lockfortrainer freezes are pending.",
            ],
        },
        {
            "id": "native_script_wait_loop",
            "source_entry": "src/script.c:SetupNativeScript/RunScriptCommand",
            "status": "unsupported",
            "critical_order": [
                "lock, lockall, and lockfortrainer return TRUE after SetupNativeScript so the script engine enters native mode.",
                "The native callback is polled until it returns TRUE.",
                "Only after the wait callback completes can the script continue to later commands such as faceplayer, message, or release.",
            ],
            "godot_current": [
                "ScriptVM executes these commands in one synchronous run and records wait-like effects as metadata.",
            ],
            "gaps": [
                "A resumable ScriptVM native-wait state machine is required before lock commands are source-equivalent.",
            ],
        },
        {
            "id": "godot_current_event_object_lock_mapping",
            "source_entry": "Godot runtime owner map",
            "status": "first_pass",
            "critical_order": GODOT_CURRENT_RULES,
            "godot_current": [
                "The current mapping is useful for script previews and first-slice dialogue, but it is intentionally below source-equivalent.",
            ],
            "gaps": [
                "Add a Godot-native event-object lock owner that coordinates ScriptVM, MapRuntime object state, PlayerController input, and ObjectEventSpawner presentation.",
            ],
        },
    ]


def manifest_entry_for(exported, output_path):
    stats = exported["stats"]
    return {
        "category": "overworld_event_object_lock_trace",
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
    return {
        "schema_version": 1,
        "generated_by": GENERATED_BY,
        "source_root": str(source_root),
        "source_files": presence,
        "required_symbols": locations,
        "lockall_order": LOCKALL_ORDER,
        "lock_selected_order": LOCK_SELECTED_ORDER,
        "player_freeze_rules": PLAYER_FREEZE_RULES,
        "object_freeze_rules": OBJECT_FREEZE_RULES,
        "release_order": RELEASE_ORDER,
        "faceplayer_order": FACEPLAYER_ORDER,
        "selected_object_rules": SELECTED_OBJECT_RULES,
        "trainer_lock_rules": TRAINER_LOCK_RULES,
        "source_flows": flow_rows,
        "godot_trace_owners": {
            "runtime": [
                "scripts/autoload/script_vm.gd",
                "scripts/autoload/map_runtime.gd",
                "scripts/autoload/event_manager.gd",
                "scripts/overworld/player_controller.gd",
            ],
            "presentation": [
                "scripts/overworld/object_event_spawner.gd",
                "scripts/overworld/object_event_placeholder.gd",
                "scripts/overworld/transition_sequence_player.gd",
            ],
            "generated_data": [
                "data/generated/scripts/*.json",
                "data/generated/maps/*.json",
                "tools/importer/export_event_scripts.py",
            ],
            "tests": [
                "tools/godot_smoke/script_vm_smoke.gd",
                "tools/godot_smoke/event_manager_smoke.gd",
                "tools/godot_smoke/player_turn_input_smoke.gd",
                "tools/godot_smoke/object_event_sprite_smoke.gd",
            ],
        },
        "visual_effect_policy": {
            "palette_and_affine": "Use Godot-native materials, shaders, animation tracks, and resources for palette, tint, scale, rotation, affine, pause, and restore effects while preserving source timing and visible result where practical.",
            "gba_runtime_limits": "Do not recreate GBA palette-bank, VRAM, OAM, or binary sprite limits at runtime unless a gameplay rule explicitly depends on them.",
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

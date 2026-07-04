#!/usr/bin/env python3
"""Export the source-to-Godot overworld parity matrix."""

import argparse
import json
import sys
from collections import Counter
from pathlib import Path

from export_map import write_json, write_manifest
from source_probe import load_config, to_project_path


STATUS_VALUES = ["ported", "first_pass", "metadata_only", "unsupported", "untraced"]


UNSUPPORTED_CODE_REGISTRY = {
    "layer_split_pending": "Metatiles are still rendered through a flattened atlas instead of source BG layer rules.",
    "door_overlay_not_source_equivalent": "Door animation currently draws overlay frames instead of mutating rendered map layers/metatiles.",
    "object_movement_task_pending": "Object-event movements are not yet source task/action queues with per-frame waits.",
    "object_event_sprite_coverage_pending": "Only the first object-event sprite slice is imported.",
    "tileset_animation_runtime_pending": "Source tileset animation callbacks are not yet exported or played.",
    "source_collision_rules_pending": "Movement still lacks full source collision/elevation/metatile behavior checks.",
    "player_avatar_state_coverage_pending": "Only normal on-foot walk and turn-in-place are source-timed.",
    "script_async_runtime_pending": "Live script execution is still mostly synchronous effect records.",
    "camera_backup_streaming_pending": "Connection scrolling does not yet reproduce backup-map streaming and camera timing.",
    "weather_runtime_pending": "Weather and palette effects are metadata/future presentation work.",
    "audio_playback_pending": "Audio symbols are preserved but not played by an audio runtime.",
    "terrain_field_effects_pending": "Terrain effects such as grass cover, ripples, footprints, and bridge visibility are pending.",
    "debug_toolkit_pending": "Godot-only overworld debug panel and hotkeys are not implemented yet.",
}


def row(
    row_id,
    area,
    status,
    source_files,
    source_symbols,
    importers=None,
    generated_artifacts=None,
    runtime_owners=None,
    presentation_owners=None,
    verification=None,
    unsupported=None,
    notes="",
):
    return {
        "id": row_id,
        "area": area,
        "status": status,
        "source": {
            "files": source_files,
            "symbols": source_symbols,
        },
        "godot": {
            "importers": importers or [],
            "generated_artifacts": generated_artifacts or [],
            "runtime_owners": runtime_owners or [],
            "presentation_owners": presentation_owners or [],
            "verification": verification or [],
        },
        "unsupported": unsupported or [],
        "notes": notes,
    }


MATRIX_ROWS = [
    row(
        "map_lifecycle",
        "map_load_and_callbacks",
        "first_pass",
        ["src/overworld.c", "src/script.c"],
        [
            "LoadMapFromWarp",
            "LoadMapFromCameraTransition",
            "InitMap",
            "RunOnTransitionMapScript",
            "RunOnLoadMapScript",
        ],
        importers=["tools/importer/export_map.py", "tools/importer/export_event_scripts.py"],
        generated_artifacts=[
            "data/generated/maps/*.json",
            "data/generated/scripts/*.json",
        ],
        runtime_owners=[
            "scripts/autoload/event_manager.gd",
            "scripts/autoload/map_runtime.gd",
            "scripts/autoload/script_vm.gd",
        ],
        presentation_owners=["scripts/overworld/transition_sequence_player.gd", "scripts/main.gd"],
        verification=["tools/godot_smoke/event_manager_smoke.gd", "tools/godot_smoke/transition_presentation_smoke.gd"],
        unsupported=["script_async_runtime_pending", "camera_backup_streaming_pending", "audio_playback_pending"],
        notes="OnTransition and OnLoad are first-pass source ordered for generated maps; resume/return/dive callbacks remain future work.",
    ),
    row(
        "map_grid_backup_connections",
        "map_grid_connections_camera",
        "first_pass",
        ["src/fieldmap.c", "include/fieldmap.h", "include/global.fieldmap.h"],
        [
            "InitBackupMapLayoutData",
            "InitBackupMapLayoutConnections",
            "GetBorderBlockAt",
            "SaveMapView",
            "LoadSavedMapView",
            "MoveMapViewToBackup",
            "CanCameraMoveInDirection",
        ],
        importers=["tools/importer/export_map.py"],
        generated_artifacts=["data/generated/maps/*.json"],
        runtime_owners=["scripts/autoload/map_runtime.gd"],
        presentation_owners=["scripts/overworld/debug_map_plane.gd", "scripts/overworld/transition_sequence_player.gd"],
        verification=["tools/godot_smoke/map_runtime_smoke.gd", "tools/godot_smoke/transition_presentation_smoke.gd"],
        unsupported=["camera_backup_streaming_pending"],
        notes="Border fallback and first connection switching exist; backup-map streaming and exact camera update timing remain pending.",
    ),
    row(
        "metatile_layer_rendering",
        "map_layers",
        "unsupported",
        ["include/global.fieldmap.h", "src/fieldmap.c"],
        ["METATILE_LAYER_TYPE_NORMAL", "METATILE_LAYER_TYPE_COVERED", "METATILE_LAYER_TYPE_SPLIT"],
        importers=["tools/importer/export_tilesets.py"],
        generated_artifacts=["data/generated/tilesets/*.json", "assets/generated/tilesets/*_metatiles.png"],
        runtime_owners=["scripts/autoload/map_runtime.gd"],
        presentation_owners=["scripts/overworld/debug_map_plane.gd"],
        verification=["tools/godot_smoke/map_runtime_smoke.gd"],
        unsupported=["layer_split_pending"],
        notes="Current renderer uses a flattened metatile atlas and cannot place player/object sprites between source BG layers.",
    ),
    row(
        "metatile_behaviors",
        "movement_and_interaction_rules",
        "first_pass",
        ["src/metatile_behavior.c", "include/constants/metatile_behaviors.h"],
        ["MetatileBehavior_Is*", "MB_*"],
        importers=["tools/importer/export_tilesets.py"],
        generated_artifacts=["data/generated/tilesets/*.json"],
        runtime_owners=[
            "scripts/autoload/map_runtime.gd",
            "scripts/autoload/event_manager.gd",
            "scripts/autoload/encounter_engine.gd",
        ],
        presentation_owners=[],
        verification=["tools/godot_smoke/map_runtime_smoke.gd", "tools/godot_smoke/encounter_engine_smoke.gd"],
        unsupported=["source_collision_rules_pending", "terrain_field_effects_pending"],
        notes="Behavior names are generated and used by encounters/warps, but full movement and terrain side effects are pending.",
    ),
    row(
        "field_input_step_pipeline",
        "field_input",
        "first_pass",
        ["src/field_control_avatar.c"],
        [
            "ProcessPlayerFieldInput",
            "TryStartStepBasedScript",
            "TryArrowWarp",
            "TryStartInteractionScript",
            "TryDoorWarp",
        ],
        importers=["tools/importer/export_event_scripts.py"],
        generated_artifacts=["data/generated/scripts/*.json"],
        runtime_owners=["scripts/autoload/event_manager.gd", "scripts/overworld/player_controller.gd"],
        presentation_owners=["scripts/main.gd"],
        verification=["tools/godot_smoke/field_wild_encounter_smoke.gd", "tools/godot_smoke/event_manager_smoke.gd"],
        unsupported=["script_async_runtime_pending", "source_collision_rules_pending"],
        notes="OnFrame and completed-step ordering are first-pass; misc walking, DexNav, arrow warp, and full interaction behavior remain pending.",
    ),
    row(
        "player_avatar",
        "player_avatar_states",
        "first_pass",
        ["src/field_player_avatar.c", "src/event_object_movement.c", "src/data/object_events/object_event_anims.h"],
        [
            "PlayerWalkNormal",
            "PlayerTurnInPlace",
            "SetStepAnimHandleAlternation",
            "sPlayerAvatarGfxIds",
        ],
        importers=["tools/importer/export_object_event_sprites.py"],
        generated_artifacts=["data/generated/object_events/object_event_sprites.json"],
        runtime_owners=["scripts/overworld/player_controller.gd"],
        presentation_owners=["scripts/overworld/player_controller.gd"],
        verification=["tools/godot_smoke/player_turn_input_smoke.gd", "tools/godot_smoke/object_event_sprite_smoke.gd"],
        unsupported=["player_avatar_state_coverage_pending"],
        notes="Normal Brendan/May walk and turn-in-place are source-timed; run/bike/surf/field-move states are pending.",
    ),
    row(
        "object_event_assets",
        "object_event_sprite_assets",
        "first_pass",
        [
            "src/data/object_events/object_event_graphics_info.h",
            "src/data/object_events/object_event_pic_tables.h",
            "src/data/object_events/object_event_graphics.h",
            "src/data/object_events/object_event_anims.h",
        ],
        [
            "gObjectEventGraphicsInfo_*",
            "sPicTable_*",
            "sAnimTable_*",
            "sFaceDirectionAnimNums",
            "sMoveDirectionAnimNums",
        ],
        importers=["tools/importer/export_object_event_sprites.py"],
        generated_artifacts=["data/generated/object_events/object_event_sprites.json", "assets/generated/object_events/*.png"],
        runtime_owners=["scripts/autoload/data_registry.gd"],
        presentation_owners=["scripts/overworld/object_event_placeholder.gd", "scripts/overworld/object_event_spawner.gd"],
        verification=["tools/godot_smoke/object_event_sprite_smoke.gd"],
        unsupported=["object_event_sprite_coverage_pending", "object_movement_task_pending"],
        notes="First 11 Littleroot/debug/player records import; full object-event graphics and animations are pending.",
    ),
    row(
        "object_event_runtime",
        "object_event_runtime",
        "first_pass",
        [
            "src/event_object_movement.c",
            "src/data/object_events/movement_type_func_tables.h",
            "src/data/object_events/movement_action_func_tables.h",
        ],
        [
            "TrySpawnObjectEvents",
            "UpdateObjectEventsForCameraUpdate",
            "sMovementTypeCallbacks",
            "ObjectEventSetHeldMovement",
            "NpcTakeStep",
            "sStepTimes",
        ],
        importers=["tools/importer/export_map.py", "tools/importer/export_object_event_sprites.py"],
        generated_artifacts=["data/generated/maps/*.json", "data/generated/object_events/object_event_sprites.json"],
        runtime_owners=["scripts/autoload/map_runtime.gd"],
        presentation_owners=["scripts/overworld/object_event_placeholder.gd", "scripts/overworld/object_event_spawner.gd"],
        verification=["tools/godot_smoke/map_runtime_smoke.gd"],
        unsupported=["object_movement_task_pending", "source_collision_rules_pending"],
        notes="Object templates, occupancy, and save snapshots exist; movement callbacks/actions are not source-equivalent.",
    ),
    row(
        "script_movement",
        "scripted_movement",
        "first_pass",
        ["src/script_movement.c", "src/event_object_lock.c", "src/scrcmd.c"],
        [
            "ScriptMovement_StartObjectMovementScript",
            "ScriptMovement_MoveObjects",
            "ScrCmd_applymovement",
            "ScrCmd_waitmovement",
            "FreezeObjectEvents",
        ],
        importers=["tools/importer/export_event_scripts.py"],
        generated_artifacts=["data/generated/scripts/*.json"],
        runtime_owners=["scripts/autoload/script_vm.gd", "scripts/autoload/map_runtime.gd"],
        presentation_owners=["scripts/overworld/player_controller.gd", "scripts/overworld/object_event_placeholder.gd"],
        verification=["tools/godot_smoke/script_vm_smoke.gd", "tools/godot_smoke/event_manager_smoke.gd"],
        unsupported=["object_movement_task_pending", "script_async_runtime_pending"],
        notes="Movement labels resolve and fast-forward net deltas; visible task queues and waits are pending.",
    ),
    row(
        "door_animation",
        "doors",
        "first_pass",
        ["src/field_door.c"],
        [
            "sDoorAnimGraphicsTable",
            "sDoorOpenAnimFrames",
            "sDoorCloseAnimFrames",
            "Task_AnimateDoor",
            "FieldAnimateDoorOpen",
            "FieldAnimateDoorClose",
        ],
        importers=["tools/importer/export_tilesets.py"],
        generated_artifacts=["data/generated/tilesets/*.json", "assets/generated/door_anims/*.png"],
        runtime_owners=["scripts/autoload/map_runtime.gd", "scripts/autoload/event_manager.gd", "scripts/autoload/script_vm.gd"],
        presentation_owners=["scripts/overworld/debug_map_plane.gd", "scripts/overworld/transition_sequence_player.gd"],
        verification=["tools/godot_smoke/transition_presentation_smoke.gd", "tools/godot_smoke/script_vm_smoke.gd"],
        unsupported=["door_overlay_not_source_equivalent", "audio_playback_pending", "script_async_runtime_pending"],
        notes="Used Littleroot door atlases and frame order exist; playback is overlay-only and script waits are not real tasks.",
    ),
    row(
        "tileset_animation",
        "dynamic_tilesets",
        "unsupported",
        ["src/tileset_anims.c", "include/tileset_anims.h", "src/data/tilesets/headers.h"],
        [
            "InitTilesetAnimations",
            "InitSecondaryTilesetAnimation",
            "UpdateTilesetAnimations",
            "TransferTilesetAnimsBuffer",
            ".callback = InitTilesetAnim_*",
        ],
        importers=["tools/importer/export_tilesets.py"],
        generated_artifacts=["data/generated/tilesets/*.json"],
        runtime_owners=[],
        presentation_owners=[],
        verification=[],
        unsupported=["tileset_animation_runtime_pending"],
        notes="Tileset callback symbols are not exported as animation runtime data yet.",
    ),
    row(
        "script_opcode_overworld",
        "overworld_script_opcodes",
        "first_pass",
        ["src/scrcmd.c", "data/scripts/std_msgbox.inc", "data/scripts/movement.inc"],
        [
            "ScrCmd_delay",
            "ScrCmd_setmetatile",
            "ScrCmd_opendoor",
            "ScrCmd_closedoor",
            "ScrCmd_waitdooranim",
            "ScrCmd_warp",
            "ScrCmd_warpsilent",
        ],
        importers=["tools/importer/export_event_scripts.py"],
        generated_artifacts=["data/generated/scripts/*.json"],
        runtime_owners=["scripts/autoload/script_vm.gd", "scripts/autoload/event_manager.gd", "scripts/autoload/map_runtime.gd"],
        presentation_owners=["scripts/main.gd", "scripts/overworld/transition_sequence_player.gd"],
        verification=["tools/godot_smoke/script_vm_smoke.gd", "tools/godot_smoke/event_manager_smoke.gd"],
        unsupported=["script_async_runtime_pending", "door_overlay_not_source_equivalent", "audio_playback_pending"],
        notes="Several opcodes emit structured effects; true async waits, fades, weather, and many warp variants are pending.",
    ),
    row(
        "terrain_field_effects",
        "terrain_and_field_effects",
        "untraced",
        ["src/field_effect.c", "src/field_effect_helpers.c", "src/field_weather_effect.c"],
        ["FieldEffectStart", "DoTracksGroundEffect", "DoGroundEffects_OnSpawn"],
        importers=[],
        generated_artifacts=[],
        runtime_owners=[],
        presentation_owners=[],
        verification=[],
        unsupported=["terrain_field_effects_pending"],
        notes="Terrain effects need a focused source audit before runtime work.",
    ),
    row(
        "weather_lighting_audio",
        "weather_lighting_audio",
        "metadata_only",
        ["src/field_weather.c", "src/field_weather_effect.c", "src/sound.c"],
        ["SetSav1Weather", "DoCurrentWeather", "PlaySE", "PlayFanfare"],
        importers=["tools/importer/export_map.py", "tools/importer/export_event_scripts.py"],
        generated_artifacts=["data/generated/maps/*.json", "data/generated/scripts/*.json"],
        runtime_owners=["scripts/autoload/event_manager.gd", "scripts/autoload/script_vm.gd"],
        presentation_owners=["scripts/overworld/transition_sequence_player.gd"],
        verification=["tools/godot_smoke/script_vm_smoke.gd", "tools/godot_smoke/transition_presentation_smoke.gd"],
        unsupported=["weather_runtime_pending", "audio_playback_pending"],
        notes="Map weather and audio symbols are preserved as metadata but not played/rendered source-equivalently.",
    ),
    row(
        "debug_overworld_toolkit",
        "debug_tooling",
        "unsupported",
        [],
        ["Godot-only debug panel", "debug_overworld_toggle"],
        importers=[],
        generated_artifacts=[],
        runtime_owners=["scripts/autoload/data_registry.gd", "scripts/autoload/map_runtime.gd"],
        presentation_owners=["scripts/main.gd"],
        verification=["tools/godot_smoke/overworld_debug_tools_smoke.gd"],
        unsupported=["debug_toolkit_pending"],
        notes="Requested Godot-only panel for avatar switching, teleport, weather override, and inspection overlays. It must remain outside source-equivalent gameplay.",
    ),
]


def build_export(source_root=None):
    entries = []
    for base_entry in MATRIX_ROWS:
        entry = dict(base_entry)
        entry["source"] = dict(base_entry["source"])
        entry["godot"] = dict(base_entry["godot"])
        entry["unsupported"] = list(base_entry["unsupported"])
        entry["source"]["file_presence"] = source_file_presence(source_root, entry["source"]["files"])
        entries.append(entry)

    stats = build_stats(entries)
    return {
        "schema_version": 1,
        "generated_by": "tools/importer/export_overworld_parity_matrix.py",
        "source_root": str(source_root) if source_root is not None else "",
        "status_values": STATUS_VALUES,
        "unsupported_code_registry": [
            {"code": code, "description": description}
            for code, description in sorted(UNSUPPORTED_CODE_REGISTRY.items())
        ],
        "entries": entries,
        "stats": stats,
    }


def source_file_presence(source_root, source_files):
    presence = []
    for source_file in source_files:
        exists = None
        if source_root is not None and str(source_root) != "":
            exists = (source_root / source_file).exists()
        presence.append({
            "path": source_file,
            "exists": exists,
        })
    return presence


def build_stats(entries):
    status_counts = Counter(entry["status"] for entry in entries)
    unsupported_counts = Counter(
        code
        for entry in entries
        for code in entry.get("unsupported", [])
    )
    missing_registry_codes = sorted(
        code
        for code in unsupported_counts
        if code not in UNSUPPORTED_CODE_REGISTRY
    )
    source_files = sorted({
        source_file
        for entry in entries
        for source_file in entry["source"]["files"]
    })
    missing_source_files = sorted({
        item["path"]
        for entry in entries
        for item in entry["source"].get("file_presence", [])
        if item["exists"] is False
    })
    return {
        "entry_count": len(entries),
        "status_counts": {status: status_counts.get(status, 0) for status in STATUS_VALUES},
        "unsupported_entry_count": sum(1 for entry in entries if entry.get("unsupported")),
        "unsupported_code_count": len(unsupported_counts),
        "unsupported_counts": dict(sorted(unsupported_counts.items())),
        "missing_registry_codes": missing_registry_codes,
        "source_file_reference_count": len(source_files),
        "missing_source_file_count": len(missing_source_files),
        "missing_source_files": missing_source_files,
        "areas": sorted({entry["area"] for entry in entries}),
    }


def manifest_entry_for(exported, output_path):
    stats = exported["stats"]
    return {
        "category": "overworld_parity_matrix",
        "path": to_project_path(output_path),
        "entry_count": stats["entry_count"],
        "unsupported_entry_count": stats["unsupported_entry_count"],
        "unsupported_code_count": stats["unsupported_code_count"],
        "missing_source_file_count": stats["missing_source_file_count"],
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
    output_path = output_root / "overworld" / "parity_matrix.json"

    exported = build_export(source_root)
    write_json(output_path, exported)
    manifest_entry = manifest_entry_for(exported, output_path)
    write_manifest(
        output_root / "import_manifest.json",
        exported_overworld_reports=[manifest_entry],
        generator="tools/importer/export_overworld_parity_matrix.py",
    )

    print(json.dumps({"exported": manifest_entry, "stats": exported["stats"]}, ensure_ascii=False, indent=2))
    return 0 if not exported["stats"]["missing_registry_codes"] else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

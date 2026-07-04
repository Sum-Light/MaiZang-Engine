#!/usr/bin/env python3
"""Export source-traced overworld map-load lifecycle coverage."""

import argparse
import json
import re
import sys
from pathlib import Path

from export_map import write_json, write_manifest
from source_probe import load_config, to_project_path


GENERATED_BY = "tools/importer/export_overworld_map_load_trace.py"
REPORT_PATH = Path("overworld/map_load_trace.json")

SOURCE_FILES = [
    "src/overworld.c",
    "src/fieldmap.c",
    "src/script.c",
    "include/constants/map_scripts.h",
]

REQUIRED_SYMBOLS = [
    "LoadMapFromCameraTransition",
    "LoadMapFromWarp",
    "LoadMapInStepsLocal",
    "DoMapLoadLoop",
    "InitMap",
    "RunOnTransitionMapScript",
    "RunOnLoadMapScript",
    "RunOnResumeMapScript",
    "TryRunOnWarpIntoMapScript",
    "CB2_LoadMap",
    "CB2_LoadMap2",
    "RunFieldCallback",
    "FieldCB_DefaultWarpExit",
]

UNSUPPORTED = [
    {
        "code": "resume_map_script_pending",
        "status": "unsupported",
        "source": "src/overworld.c:ResumeMap -> src/script.c:RunOnResumeMapScript",
        "detail": "Godot records resume hooks in debug output but does not yet dispatch MAP_SCRIPT_ON_RESUME during generated map loads.",
    },
    {
        "code": "warp_into_map_table_pending",
        "status": "unsupported",
        "source": "src/overworld.c:InitObjectEventsLocal -> src/script.c:TryRunOnWarpIntoMapScript",
        "detail": "Godot records OnWarpIntoMap table labels/conditions but does not yet run them after spawning object events.",
    },
    {
        "code": "field_callback_pipeline_pending",
        "status": "unsupported",
        "source": "src/overworld.c:RunFieldCallback",
        "detail": "Godot transition playback has first-pass structured sequences, but not the source gFieldCallback/gFieldCallback2 lifecycle.",
    },
    {
        "code": "weather_palette_load_pending",
        "status": "metadata_only",
        "source": "src/overworld.c:SetSavedWeatherFromCurrMapHeader/DoCurrentWeather/ApplyWeatherColorMapToPals",
        "detail": "Weather symbols are preserved while palette/color-map effects are intentionally Godot-native future presentation work.",
    },
    {
        "code": "tileset_animation_runtime_pending",
        "status": "unsupported",
        "source": "src/overworld.c:InitSecondaryTilesetAnimation/InitTilesetAnimations",
        "detail": "Source tileset animation callbacks and frame copy cadence are not yet exported or played at runtime.",
    },
    {
        "code": "audio_playback_pending",
        "status": "metadata_only",
        "source": "src/overworld.c:TransitionMapMusic/Overworld_ClearSavedMusic",
        "detail": "Audio playback remains out of scope; map music ids and timing intent stay metadata-only.",
    },
    {
        "code": "camera_backup_streaming_pending",
        "status": "unsupported",
        "source": "src/overworld.c:LoadMapInStepsLocal/ResetFieldCamera/DrawWholeMapView",
        "detail": "The source staged map-view/camera/VRAM load loop is not source-equivalent in Godot yet.",
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
            "id": "camera_transition_load",
            "source_entry": "src/overworld.c:LoadMapFromCameraTransition",
            "status": "first_pass_metadata",
            "critical_order": [
                "SetWarpDestination",
                "TransitionMapMusic unless current section is MAPSEC_BATTLE_FRONTIER",
                "ApplyCurrentWarp",
                "LoadCurrentMapData",
                "LoadObjEventTemplatesFromHeader",
                "TrySetMapSaveWarpStatus",
                "ClearTempFieldEventData",
                "ResetDexNavSearch",
                "ResetCyclingRoadChallengeData",
                "RestartWildEncounterImmunitySteps",
                "DoTimeBasedEvents",
                "SetSavedWeatherFromCurrMapHeader",
                "ChooseAmbientCrySpecies",
                "SetDefaultFlashLevel",
                "Overworld_ClearSavedMusic",
                "RunOnTransitionMapScript",
                "InitMap",
                "CopySecondaryTilesetToVramUsingHeap",
                "LoadSecondaryTilesetPalette",
                "ApplyWeatherColorMapToPals",
                "InitSecondaryTilesetAnimation",
                "UpdateLocationHistoryForRoamer",
                "MoveAllRoamers",
                "DoCurrentWeather",
                "ResetFieldTasksArgs",
                "RunOnResumeMapScript",
                "ShowMapNamePopup when source conditions pass",
            ],
            "godot_current": [
                "EventManager can run MAP_SCRIPT_ON_TRANSITION and MAP_SCRIPT_ON_LOAD for generated map loads.",
                "MapRuntime consumes generated map/layout/tileset data instead of source VRAM/palette loads.",
                "MapRuntime/EventManager debug dump exposes map type, weather, music, and active script hooks.",
            ],
            "gaps": [
                "TransitionMapMusic/Overworld_ClearSavedMusic remain metadata-only.",
                "Weather color maps and palette effects are not implemented.",
                "RunOnResumeMapScript is not dispatched during Godot map loads.",
                "Secondary tileset VRAM/palette/tile animation steps are not source-equivalent.",
                "Roamer/location history side effects are future work.",
            ],
        },
        {
            "id": "warp_load_core",
            "source_entry": "src/overworld.c:LoadMapFromWarp",
            "status": "first_pass",
            "critical_order": [
                "LoadCurrentMapData",
                "Load object templates from Battle Pyramid/Trainer Hill/header depending on map",
                "Check map type indoors/outdoors",
                "CheckLeftFriendsSecretBase",
                "TrySetMapSaveWarpStatus",
                "ClearTempFieldEventData",
                "ResetDexNavSearch",
                "Reset hours override",
                "ResetCyclingRoadChallengeData",
                "RestartWildEncounterImmunitySteps",
                "TryUpdateRandomTrainerRematches/MapResetTrainerRematches when enabled",
                "DoTimeBasedEvents unless returning from link-style load",
                "SetSavedWeatherFromCurrMapHeader",
                "ChooseAmbientCrySpecies",
                "Clear flash flag outdoors",
                "SetDefaultFlashLevel",
                "Overworld_ClearSavedMusic",
                "RunOnTransitionMapScript",
                "UpdateLocationHistoryForRoamer",
                "MoveAllRoamersToOtherLocationSets",
                "Clear chain fishing/DexNav streak",
                "InitBattlePyramidMap/InitTrainerHillMap/InitMap",
                "UpdateTVScreensOnMap and InitSecretBaseAppearance for normal indoor warps",
            ],
            "godot_current": [
                "EventManager transition payloads can reconfigure MapRuntime, GameState.current_map_id, ScriptVM script data, and then run first-pass map-load scripts.",
                "Generated destination warp-id lookup and exit-task metadata are covered for the first generated maps.",
            ],
            "gaps": [
                "Battle Pyramid/Trainer Hill special layout paths are not implemented.",
                "Weather, ambient cries, flash, roamers, TV screens, and Secret Base map-load side effects are not source-equivalent.",
                "The source distinction between LoadMapFromWarp(TRUE/FALSE) is not fully modeled.",
            ],
        },
        {
            "id": "local_step_loader",
            "source_entry": "src/overworld.c:LoadMapInStepsLocal",
            "status": "first_pass_metadata",
            "critical_order": [
                "case 0: FieldClearVBlankHBlankCallbacks then LoadMapFromWarp",
                "case 1: ResetMirageTowerAndSaveBlockPtrs and ResetScreenForMapLoad",
                "case 2: ResumeMap, including StartWeather/ResumePausedWeather/RunOnResumeMapScript",
                "case 3: InitObjectEventsLocal and SetCameraToTrackPlayer",
                "case 4: InitCurrentFlashLevelScanlineEffect, InitOverworldGraphicsRegisters, InitTextBoxGfxAndPrinters",
                "case 5: ResetFieldCamera",
                "case 6: CopyPrimaryTilesetToVram",
                "case 7: CopySecondaryTilesetToVram",
                "case 8: wait for temp buffers, then LoadMapTilesetPalettes",
                "case 9: DrawWholeMapView",
                "case 10: InitTilesetAnimations",
                "case 11: optional ShowMapNamePopup",
                "case 12: RunFieldCallback",
                "case 13: done",
            ],
            "godot_current": [
                "TransitionSequencePlayer has source-ordered first-pass fade/load/reveal sequence data.",
                "DebugMapPlane draws current generated map data immediately from RGBA atlas/debug tiles.",
            ],
            "gaps": [
                "Godot does not currently stage map load over the source case-by-case callback loop.",
                "VRAM/OAM/palette steps are intentionally not recreated as GBA limits, but their visible effects still need Godot-native equivalents.",
                "RunFieldCallback and exact map-name popup timing are pending.",
            ],
        },
        {
            "id": "layout_onload_script",
            "source_entry": "src/fieldmap.c:InitMap",
            "status": "first_pass",
            "critical_order": [
                "InitMapLayoutData",
                "SetOccupiedSecretBaseEntranceMetatiles",
                "RunOnLoadMapScript",
            ],
            "godot_current": [
                "MapRuntime.configure_from_data loads generated map/layout grids.",
                "EventManager.run_map_load_scripts runs MAP_SCRIPT_ON_TRANSITION first, then source-timed template sync, then MAP_SCRIPT_ON_LOAD.",
            ],
            "gaps": [
                "Secret Base entrance occupancy and broader map-layout side effects remain future work.",
            ],
        },
        {
            "id": "map_script_dispatch_helpers",
            "source_entry": "src/script.c:RunOnTransitionMapScript/RunOnLoadMapScript",
            "status": "first_pass",
            "critical_order": [
                "MapHeaderGetScriptTable finds map_script type records",
                "MapHeaderRunScriptType runs immediate scripts for ON_LOAD/ON_TRANSITION/ON_RESUME/ON_DIVE/ON_RETURN",
                "MapHeaderCheckScriptTable evaluates map_script_2 tables with VarGet equality",
                "TryRunOnWarpIntoMapScript runs first matching ON_WARP_INTO_MAP_TABLE script immediately",
            ],
            "godot_current": [
                "EventManager.run_map_script_type runs ON_TRANSITION and ON_LOAD immediate scripts.",
                "EventManager.try_run_on_frame_map_script evaluates map_script_2 tables using GameState vars.",
                "EventManager.get_current_map_debug_dump inspects all seven hook labels and table conditions read-only.",
            ],
            "gaps": [
                "ON_RESUME, ON_DIVE_WARP, ON_RETURN_TO_FIELD, and ON_WARP_INTO_MAP_TABLE are not all dispatched in their source lifecycle slots.",
                "True ScriptContext async/wait timing remains pending.",
            ],
        },
        {
            "id": "field_callback_setup",
            "source_entry": "src/overworld.c:CB2_LoadMap/RunFieldCallback",
            "status": "first_pass_metadata",
            "critical_order": [
                "CB2_LoadMap clears field callbacks, initializes ScriptContext, unlocks controls, clears callback1, sets callback2 to CB2_DoChangeMap, and saves CB2_LoadMap2",
                "CB2_LoadMap2 runs DoMapLoadLoop then installs VBlankCB_Field, CB1_Overworld, and CB2_Overworld",
                "DoMapLoadLoop repeatedly runs LoadMapInStepsLocal until complete",
                "RunFieldCallback prefers gFieldCallback2, otherwise runs gFieldCallback or FieldCB_DefaultWarpExit, then clears callbacks",
            ],
            "godot_current": [
                "Main delegates transition playback to TransitionSequencePlayer and keeps input locked until sequence completion.",
                "Transition sequences record first-pass callbacks such as exit-task selection and battle scene handoff points.",
            ],
            "gaps": [
                "The gFieldCallback/gFieldCallback2 ownership model is not represented as a runtime state machine.",
                "FieldCB_DefaultWarpExit and fade-from-black paths are only approximated by current transition sequence data.",
            ],
        },
    ]


def manifest_entry_for(exported, output_path):
    stats = exported["stats"]
    return {
        "category": "overworld_map_load_trace",
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
    stats = {
        "flow_count": len(flow_rows),
        "source_file_count": len(SOURCE_FILES),
        "missing_source_file_count": sum(1 for item in presence if not item["exists"]),
        "required_symbol_count": len(REQUIRED_SYMBOLS),
        "missing_symbol_count": len(missing_symbols),
        "missing_symbols": missing_symbols,
        "status_counts": status_counts,
        "unsupported_count": len(UNSUPPORTED),
    }
    return {
        "schema_version": 1,
        "generated_by": GENERATED_BY,
        "source_root": str(source_root),
        "source_files": presence,
        "required_symbols": locations,
        "source_flows": flow_rows,
        "godot_trace_owners": {
            "runtime": [
                "scripts/autoload/event_manager.gd",
                "scripts/autoload/map_runtime.gd",
                "scripts/autoload/script_vm.gd",
            ],
            "presentation": [
                "scripts/main.gd",
                "scripts/overworld/transition_sequence_player.gd",
                "scripts/overworld/debug_map_plane.gd",
            ],
            "tests": [
                "tools/godot_smoke/event_manager_smoke.gd",
                "tools/godot_smoke/map_runtime_smoke.gd",
                "tools/godot_smoke/transition_presentation_smoke.gd",
                "tools/godot_smoke/overworld_runtime_debug_dump_smoke.gd",
            ],
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

#!/usr/bin/env python3
"""Export source-traced overworld field-control ordering coverage."""

import argparse
import json
import re
import sys
from pathlib import Path

from export_map import write_json, write_manifest
from source_probe import load_config, to_project_path


GENERATED_BY = "tools/importer/export_overworld_field_control_trace.py"
REPORT_PATH = Path("overworld/field_control_trace.json")

SOURCE_FILES = [
    "include/field_control_avatar.h",
    "src/field_control_avatar.c",
    "include/script.h",
    "src/script.c",
    "include/wild_encounter.h",
    "src/wild_encounter.c",
    "include/metatile_behavior.h",
    "src/metatile_behavior.c",
    "include/field_screen_effect.h",
    "src/field_screen_effect.c",
    "include/overworld.h",
    "src/overworld.c",
    "include/trainer_see.h",
    "src/trainer_see.c",
    "include/dexnav.h",
    "src/dexnav.c",
    "include/item_menu.h",
    "src/item_menu.c",
    "include/start_menu.h",
    "src/start_menu.c",
    "include/debug.h",
    "src/debug.c",
    "include/field_player_avatar.h",
    "src/field_player_avatar.c",
    "include/pokemon.h",
    "src/pokemon.c",
    "include/follower_npc.h",
    "src/follower_npc.c",
    "include/secret_base.h",
    "src/secret_base.c",
    "include/trainer_hill.h",
    "src/trainer_hill.c",
]

REQUIRED_SYMBOLS = [
    "FieldInput",
    "FieldClearPlayerInput",
    "FieldGetPlayerInput",
    "ProcessPlayerFieldInput",
    "GetPlayerPosition",
    "GetInFrontOfPlayerPosition",
    "GetPlayerCurMetatileBehavior",
    "TryStartInteractionScript",
    "GetInteractionScript",
    "GetInteractedLinkPlayerScript",
    "GetInteractedObjectEventScript",
    "GetInteractedBackgroundEventScript",
    "GetInteractedMetatileScript",
    "GetInteractedWaterScript",
    "TrySetupDiveDownScript",
    "TrySetupDiveEmergeScript",
    "TryStartStepBasedScript",
    "TryStartCoordEventScript",
    "TryStartWarpEventScript",
    "TryStartMiscWalkingScripts",
    "TryStartStepCountScript",
    "TryRunCoordEventScript",
    "GetCoordEventScriptAtPosition",
    "GetCoordEventScriptAtMapPosition",
    "GetBackgroundEventAtPosition",
    "CheckStandardWildEncounter",
    "RestartWildEncounterImmunitySteps",
    "sWildEncounterImmunitySteps",
    "sPrevMetatileBehavior",
    "TryArrowWarp",
    "IsWarpMetatileBehavior",
    "IsArrowWarpMetatileBehavior",
    "GetWarpEventAtMapPosition",
    "GetWarpEventAtPosition",
    "SetupWarp",
    "TryDoorWarp",
    "TryDoDiveWarp",
    "TrySetDiveWarp",
    "TrySetUpWalkIntoSignpostScript",
    "GetFacingSignpostType",
    "SetMsgSignPostAndVarFacing",
    "SetUpWalkIntoSignScript",
    "GetSignpostScriptAtMapPosition",
    "CancelSignPostMessageBox",
    "CheckForTrainersWantingBattle",
    "TryRunOnFrameMapScript",
    "RunScriptImmediatelyUntilEffect",
    "Script_HasNoEffect",
    "GetRamScript",
    "StandardWildEncounter",
    "UpdateRepelCounter",
    "OnStep_DexNavSearch",
    "TryFindHiddenPokemon",
    "UseRegisteredKeyItemOnField",
    "TryStartDexNavSearch",
    "ShowStartMenu",
    "Debug_ShowMainMenu",
    "CanTriggerSpinEvolution",
    "TrySpecialOverworldEvo",
    "DoWarp",
    "DoDoorWarp",
    "DoStairWarp",
    "DoDiveWarp",
    "DoEscalatorWarp",
    "DoTeleportTileWarp",
    "DoSpinExitWarp",
    "DoMossdeepGymWarp",
    "SetDiveWarpEmerge",
    "SetDiveWarpDive",
    "SetWarpDestinationToDynamicWarp",
    "SetWarpDestinationToMapWarp",
    "SetDynamicWarp",
    "UpdateEscapeWarp",
    "GetTrainerHillTrainerScript",
    "GetFollowerNPCScriptPointer",
    "TrySetCurSecretBase",
]

FIELD_INPUT_FLAGS = [
    {
        "field": "pressedAButton",
        "source_gate": "new A button, only when tile centered/not moving, not forced movement, and speed is not PLAYER_SPEED_FASTEST",
    },
    {
        "field": "checkStandardWildEncounter",
        "source_gate": "tileTransitionState == T_TILE_CENTER and current metatile is not forced movement",
    },
    {
        "field": "pressedStartButton",
        "source_gate": "new START button, same field-control gate as A/B/R/SELECT",
    },
    {
        "field": "pressedSelectButton",
        "source_gate": "new SELECT button, same field-control gate as A/B/R/START",
    },
    {
        "field": "heldDirection",
        "source_gate": "any held dpad direction under the tile-centered/not-moving gate",
    },
    {
        "field": "heldDirection2",
        "source_gate": "same held dpad gate; consumed later by TryDoorWarp",
    },
    {
        "field": "tookStep",
        "source_gate": "tileTransitionState == T_TILE_CENTER and runningState == MOVING, unless forced movement",
    },
    {
        "field": "pressedBButton",
        "source_gate": "new B button, same field-control gate as A/R/START/SELECT",
    },
    {
        "field": "pressedRButton",
        "source_gate": "new R button, same field-control gate as A/B/START/SELECT",
    },
    {
        "field": "input_field_1_2",
        "source_gate": "DEBUG_OVERWORLD_MENU trigger latch, used to open Debug_ShowMainMenu",
    },
    {
        "field": "dpadDirection",
        "source_gate": "held dpad priority order: UP, DOWN, LEFT, RIGHT",
    },
]

PROCESS_PLAYER_FIELD_INPUT_ORDER = [
    "reset gSpecialVar_LastTalked, gSelectedObjectEvent, and gMsgIsSignPost",
    "read player facing direction, destination position, and current metatile behavior",
    "CheckForTrainersWantingBattle",
    "TryRunOnFrameMapScript",
    "pressed B -> TrySetupDiveEmergeScript",
    "tookStep -> IncrementGameStat(GAME_STAT_STEPS), IncrementBirthIslandRockStepCount, TryStartStepBasedScript",
    "checkStandardWildEncounter with no dpad or same-facing dpad -> front-cell TrySetUpWalkIntoSignpostScript, then restore current cell",
    "checkStandardWildEncounter -> CheckStandardWildEncounter",
    "heldDirection and same-facing dpad -> TryArrowWarp on the current cell",
    "switch to the tile in front of the player",
    "heldDirection and same-facing dpad -> front-cell TrySetUpWalkIntoSignpostScript",
    "pressed A -> TryStartInteractionScript",
    "heldDirection2 and same-facing dpad -> TryDoorWarp",
    "pressed A -> TrySetupDiveDownScript",
    "pressed START -> FlagSet(FLAG_OPENED_START_MENU), PlaySE(SE_WIN_OPEN), ShowStartMenu",
    "tookStep -> TryFindHiddenPokemon",
    "pressed SELECT -> UseRegisteredKeyItemOnField",
    "pressed R -> TryStartDexNavSearch",
    "debug trigger -> PlaySE(SE_WIN_OPEN), FreezeObjectEvents, Debug_ShowMainMenu",
    "CanTriggerSpinEvolution -> ResetSpinTimer and TrySpecialOverworldEvo",
]

STEP_BASED_SCRIPT_ORDER = [
    "TryStartCoordEventScript",
    "TryStartWarpEventScript",
    "TryStartMiscWalkingScripts",
    "TryStartStepCountScript",
    "UpdateRepelCounter, only when not forced movement and not on a forced-movement metatile",
    "OnStep_DexNavSearch",
]

STEP_COUNT_ORDER = [
    "InUnionRoom returns false before mutating counters",
    "IncrementRematchStepCounter",
    "UpdateFriendshipStepCounter",
    "UpdateFarawayIslandStepCounter",
    "UpdateFollowerStepCounter",
    "UpdatePoisonStepCounter -> EventScript_FieldPoison, only when OW_POISON_DAMAGE < GEN_5 and not forced movement",
    "ShouldEggHatch -> IncrementGameStat(GAME_STAT_HATCHED_EGGS), EventScript_EggHatch",
    "AbnormalWeatherHasExpired -> AbnormalWeather_EventScript_EndEventAndCleanup_1",
    "ShouldDoBrailleRegicePuzzle -> IslandCave_EventScript_OpenRegiEntrance",
    "ShouldDoWallyCall -> MauvilleCity_EventScript_RegisterWallyCall",
    "ShouldDoScottFortreeCall -> Route119_EventScript_ScottWonAtFortreeGymCall",
    "ShouldDoScottBattleFrontierCall -> LittlerootTown_ProfessorBirchsLab_EventScript_ScottAboardSSTidalCall",
    "ShouldDoRoxanneCall -> RustboroCity_Gym_EventScript_RegisterRoxanne",
    "ShouldDoRivalRayquazaCall -> MossdeepCity_SpaceCenter_2F_EventScript_RivalRayquazaCall",
    "UpdateVsSeekerStepCounter -> EventScript_VsSeekerChargingDone",
    "SafariZoneTakeStep",
    "CountSSTidalStep(1) -> SSTidalCorridor_EventScript_ReachedStepCount",
    "TryStartMatchCall",
]

INTERACTION_RESOLUTION_ORDER = [
    "GetInteractedObjectEventScript",
    "GetInteractedBackgroundEventScript",
    "GetInteractedMetatileScript",
    "GetInteractedWaterScript",
    "TryStartInteractionScript skips NULL scripts and Script_HasNoEffect scripts",
    "TryStartInteractionScript plays SE_SELECT except for listed PC and secret-base doll/cushion exceptions",
    "ScriptContext_SetupScript starts the selected script",
]

METATILE_SCRIPT_ORDER = [
    "TV screen -> EventScript_TV or EventScript_PlayerFacingTVScreen",
    "PC -> EventScript_PC",
    "Closed Sootopolis door -> EventScript_ClosedSootopolisDoor",
    "Sky Pillar closed door -> SkyPillar_Outside_EventScript_ClosedDoor",
    "Cable Box Results 1 -> EventScript_CableBoxResults",
    "Pokeblock feeder -> EventScript_PokeBlockFeeder",
    "Trick House puzzle door -> Route110_TrickHousePuzzle_EventScript_Door",
    "Region map -> EventScript_RegionMap",
    "Running Shoes manual -> EventScript_RunningShoesManual",
    "Picture book shelf, bookshelf, Pokemon Center bookshelf, vase, trash can, shop shelf, blueprint",
    "Wireless/cable/questionnaire/trainer-hill monitor checks",
    "FRLG-only furniture and monitor checks, guarded by IS_FRLG",
    "Pokemart/Pokemon Center signs only when facing north, setting signpost message state",
    "Rock Climb prompt when rock climbable and inactive",
    "Secret-base PC/record mixing/furniture/poster checks gated by elevation rules",
]

WATER_AND_DIVE_RULES = [
    "Fast water without surfing -> EventScript_CurrentTooFast",
    "Unlocked Surf, a Surf-capable party, surfable/fishable water, and follower allowance -> EventScript_UseSurf",
    "Waterfall metatile with follower allowance -> EventScript_UseWaterfall or EventScript_CannotUseWaterfall",
    "TrySetupDiveDownScript requires follower allowance, unlocked Dive, and TrySetDiveWarp() == 2",
    "TrySetupDiveEmergeScript requires follower allowance, unlocked Dive, underwater map type, and TrySetDiveWarp() == 1",
    "TryDoDiveWarp performs direct dive/emerge warp setup, DoDiveWarp, and SE_M_DIVE",
]

COORD_EVENT_RULES = [
    "GetCoordEventScriptAtPosition scans map coord events in source order",
    "x/y must match after MAP_OFFSET removal",
    "event elevation must match current elevation or ELEVATION_TRANSITION",
    "NULL coord-event script triggers DoCoordEventWeather(trigger) and returns no script",
    "TRIGGER_RUN_IMMEDIATELY runs the script immediately and returns no script",
    "normal coord events compare trigger var or flag to index before returning a script",
]

WARP_RULES = [
    "GetWarpEventAtPosition scans map warps in source order",
    "x/y must match after MAP_OFFSET removal",
    "warp elevation must match current elevation or ELEVATION_TRANSITION",
    "step warps require IsWarpMetatileBehavior on the current metatile",
    "special step warps branch to escalator, Lavaridge, Aqua Hideout, Union Room, Mt. Pyre hole, or Mossdeep Gym handlers before default DoWarp",
    "SetupWarp handles Trainer Hill destinations, dynamic warp destinations, escape warp updates, and destination-side dynamic warp setup",
]

DOOR_ARROW_RULES = [
    "TryArrowWarp only runs from the current cell when heldDirection and same-facing dpad are true",
    "arrow warp requires a warp event at the current cell and a direction-specific arrow metatile behavior",
    "directional stair warp clears bike transition flags to on-foot and inserts a 12-frame delay when needed",
    "TryDoorWarp only runs for the front cell when direction == DIR_NORTH",
    "open secret-base door calls WarpIntoSecretBase",
    "warp door requires a warp event and IsWarpMetatileBehavior before DoDoorWarp",
]

SIGNPOST_RULES = [
    "TrySetUpWalkIntoSignpostScript rejects held left/right dpad and any direction other than north",
    "Pokemon Center signs and Pokemart signs use common sign scripts",
    "plain signpost metatiles fetch the background event script at the map position",
    "missing signpost scripts fall back to EventScript_TestSignpostMsg",
    "SetMsgSignPostAndVarFacing sets WALK_AWAY_SIGNPOST_FRAMES, cancelable message state, gMsgIsSignPost, and gSpecialVar_Facing",
    "CancelSignPostMessageBox waits for the signpost timer, then dpad-turn/move or START sets EventScript_CancelMessageBox and locks controls",
    "START cancellation creates Task_OpenStartMenu if it is not already active",
]

UNSUPPORTED = [
    {
        "code": "field_input_sampling_not_source_shaped",
        "status": "unsupported",
        "source": "src/field_control_avatar.c:FieldGetPlayerInput",
        "detail": "PlayerController still reads Godot input directly instead of building and processing a source-shaped FieldInput structure every field frame.",
    },
    {
        "code": "full_process_player_field_input_priority_pending",
        "status": "first_pass",
        "source": "src/field_control_avatar.c:ProcessPlayerFieldInput",
        "detail": "Trainer/on-frame/step/wild/door dispatch have first-pass Godot pieces, but the whole source priority list is not yet executed from a single ProcessPlayerFieldInput equivalent.",
    },
    {
        "code": "interaction_resolution_order_pending",
        "status": "unsupported",
        "source": "src/field_control_avatar.c:GetInteractionScript",
        "detail": "MapRuntime can resolve first-slice object and BG/sign interactions, but it does not yet apply the full object -> background -> metatile -> water script resolution order.",
    },
    {
        "code": "object_event_sideways_stairs_and_counter_pending",
        "status": "unsupported",
        "source": "src/field_control_avatar.c:GetInteractedObjectEventScript",
        "detail": "Sideways-stair object lookup, counter look-through, Trainer Hill, follower NPC, gSelectedObjectEvent, and gSpecialVar_LastTalked side effects remain future runtime work.",
    },
    {
        "code": "background_hidden_item_secret_base_pending",
        "status": "unsupported",
        "source": "src/field_control_avatar.c:GetInteractedBackgroundEventScript",
        "detail": "Directional BG events, hidden-item variables/flags, and secret-base background-event entry checks are not yet source-equivalent.",
    },
    {
        "code": "metatile_and_water_scripts_pending",
        "status": "unsupported",
        "source": "src/field_control_avatar.c:GetInteractedMetatileScript/GetInteractedWaterScript",
        "detail": "PCs, TVs, shelves, signs, rock climb, secret-base furniture, Surf, Waterfall, and related metatile/water prompts are preserved as trace metadata but are not fully implemented.",
    },
    {
        "code": "walk_into_signpost_cancel_pending",
        "status": "unsupported",
        "source": "src/field_control_avatar.c:TrySetUpWalkIntoSignpostScript/CancelSignPostMessageBox",
        "detail": "Walk-into signpost setup, cancelable signpost message timing, and delayed Start Menu opening are not yet runtime-equivalent.",
    },
    {
        "code": "arrow_warp_directional_stair_pending",
        "status": "unsupported",
        "source": "src/field_control_avatar.c:TryArrowWarp",
        "detail": "Arrow warps and directional stair warps, including bike-to-foot transition delay, are not yet reproduced in Godot.",
    },
    {
        "code": "door_warp_source_order_partial",
        "status": "first_pass",
        "source": "src/field_control_avatar.c:TryDoorWarp",
        "detail": "Blocked north-facing door warps and first-pass door animation overlays exist, but door dispatch is not yet owned by the traced FieldInput ordering path.",
    },
    {
        "code": "coord_event_weather_immediate_pending",
        "status": "first_pass",
        "source": "src/field_control_avatar.c:TryRunCoordEventScript",
        "detail": "Normal generated coord events dispatch after player steps, but NULL weather coord events and TRIGGER_RUN_IMMEDIATELY semantics remain pending.",
    },
    {
        "code": "step_count_side_effects_pending",
        "status": "unsupported",
        "source": "src/field_control_avatar.c:TryStartStepCountScript",
        "detail": "Most step-count side effects are summaries only: poison, egg hatching, abnormal-weather expiry, Regice puzzle, calls, VS Seeker, Safari, S.S. Tidal, and Match Call.",
    },
    {
        "code": "dive_field_move_flow_pending",
        "status": "unsupported",
        "source": "src/field_control_avatar.c:TrySetupDiveDownScript/TrySetupDiveEmergeScript",
        "detail": "Dive down/emerge setup, direct dive warp, follower allowance, and SE_M_DIVE timing are not source-equivalent yet.",
    },
    {
        "code": "registered_item_hidden_pokemon_dexnav_pending",
        "status": "unsupported",
        "source": "src/field_control_avatar.c:ProcessPlayerFieldInput tail",
        "detail": "TryFindHiddenPokemon, UseRegisteredKeyItemOnField, and TryStartDexNavSearch remain future source-backed field-input tail work.",
    },
    {
        "code": "overworld_debug_toolkit_pending",
        "status": "unsupported",
        "source": "Godot-only debug lane",
        "detail": "The TODO now tracks a debug key/panel for avatar-state switching, manifest-backed map teleport, and weather override/reset. This must stay debug-only and separate from source-equivalent warps and weather.",
    },
    {
        "code": "audio_playback_pending",
        "status": "metadata_only",
        "source": "SE_SELECT/SE_WIN_OPEN/SE_M_DIVE and related field sounds",
        "detail": "Sound symbols and timing intent are preserved in reports, but real audio playback is intentionally out of scope for now.",
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
            "id": "field_input_sampling",
            "source_entry": "src/field_control_avatar.c:FieldGetPlayerInput + include/field_control_avatar.h:FieldInput",
            "status": "metadata_only",
            "critical_order": [
                "FieldClearPlayerInput clears every FieldInput bit and dpadDirection",
                "button presses are sampled only when tile centered without forced movement or when not moving",
                "START/SELECT/A/B/R are ignored at PLAYER_SPEED_FASTEST",
                "heldDirection and heldDirection2 are both set from any held dpad under the same movement gate",
                "tookStep and checkStandardWildEncounter are set only when not forced movement",
                "dpadDirection priority is UP, DOWN, LEFT, RIGHT",
                "DEBUG_OVERWORLD_MENU can latch input_field_1_2",
            ],
            "godot_current": [
                "scripts/overworld/player_controller.gd reads Godot input actions directly.",
                "PlayerController calls a field-input precheck before accept/movement input.",
            ],
            "gaps": [
                "No source-shaped FieldInput object is built and fed through one ProcessPlayerFieldInput owner yet.",
            ],
        },
        {
            "id": "process_player_field_input_priority",
            "source_entry": "src/field_control_avatar.c:ProcessPlayerFieldInput",
            "status": "first_pass",
            "critical_order": PROCESS_PLAYER_FIELD_INPUT_ORDER,
            "godot_current": [
                "Main dispatches OnFrame precheck before player accept/movement input.",
                "Main dispatches player-step summaries after movement completes.",
                "Main dispatches blocked north-facing door warp checks separately.",
            ],
            "gaps": [
                "The Godot path is still split across PlayerController, Main, EventManager, and MapRuntime rather than a source-shaped priority dispatcher.",
            ],
        },
        {
            "id": "step_based_script_order",
            "source_entry": "src/field_control_avatar.c:TryStartStepBasedScript/TryStartStepCountScript",
            "status": "first_pass",
            "critical_order": STEP_BASED_SCRIPT_ORDER,
            "step_count_order": STEP_COUNT_ORDER,
            "godot_current": [
                "EventManager.dispatch_player_step follows the first-pass order for generated coord events, step warps, misc walking summaries, step-count summaries, Repel/Lure, DexNav summary, and standard wild encounters.",
            ],
            "gaps": [
                "Most misc walking and step-count side effects are summarized instead of executing source-equivalent scripts and presentation.",
            ],
        },
        {
            "id": "interaction_resolution_order",
            "source_entry": "src/field_control_avatar.c:GetInteractionScript/TryStartInteractionScript",
            "status": "metadata_only",
            "critical_order": INTERACTION_RESOLUTION_ORDER,
            "godot_current": [
                "MapRuntime resolves first-slice object/sign interaction targets and EventManager dispatches script previews/effects.",
            ],
            "gaps": [
                "Metatile and water interactions are not included in the target resolver yet.",
            ],
        },
        {
            "id": "object_and_background_interaction_rules",
            "source_entry": "src/field_control_avatar.c:GetInteractedObjectEventScript/GetInteractedBackgroundEventScript",
            "status": "metadata_only",
            "critical_order": [
                "object interaction sets gSpecialVar_Facing before lookup",
                "east/west sideways-stair cases can lookup diagonal object positions",
                "counter metatiles lookup one extra tile beyond the counter",
                "OBJECT_EVENTS_COUNT and LOCALID_PLAYER are ignored",
                "gSelectedObjectEvent and gSpecialVar_LastTalked are set on success",
                "Trainer Hill and follower NPC scripts override ordinary object script lookup",
                "GetRamScript can replace the object-event script by local id",
                "background events are source-order scanned by x/y/elevation",
                "directional background events only trigger from matching player facing",
                "hidden items set VAR_0x8004, VAR_0x8005, VAR_0x8009 and skip already-set flags",
                "secret-base background events require north-facing interaction and TrySetCurSecretBase",
            ],
            "godot_current": [
                "MapRuntime indexes generated object events, BG/sign events, and source numeric local-id aliases.",
            ],
            "gaps": [
                "Sideways stairs, counter look-through, hidden item variables, and secret-base background handling are pending.",
            ],
        },
        {
            "id": "metatile_water_dive_interaction_scripts",
            "source_entry": "src/field_control_avatar.c:GetInteractedMetatileScript/GetInteractedWaterScript/TrySetupDive*",
            "status": "metadata_only",
            "critical_order": METATILE_SCRIPT_ORDER,
            "water_and_dive_rules": WATER_AND_DIVE_RULES,
            "godot_current": [
                "Generated metatile behavior names are available through MapRuntime.",
                "Surf/Waterfall/Dive prompts and metatile scripts are not runtime-owned yet.",
            ],
            "gaps": [
                "The report preserves the source order for later runtime implementation.",
            ],
        },
        {
            "id": "coord_event_and_step_warp_rules",
            "source_entry": "src/field_control_avatar.c:GetCoordEventScriptAtPosition/TryStartWarpEventScript/SetupWarp",
            "status": "first_pass",
            "critical_order": COORD_EVENT_RULES + WARP_RULES,
            "godot_current": [
                "MapRuntime indexes generated coordinate events and warp events.",
                "EventManager dispatches generated normal coord events and generated step warps.",
            ],
            "gaps": [
                "NULL weather coord events, immediate coord events, Trainer Hill warp special cases, and dynamic warp edge cases are pending.",
            ],
        },
        {
            "id": "door_and_arrow_warp_rules",
            "source_entry": "src/field_control_avatar.c:TryArrowWarp/TryDoorWarp",
            "status": "first_pass",
            "critical_order": DOOR_ARROW_RULES,
            "godot_current": [
                "Blocked front-cell door warp dispatch only fires while facing north.",
                "TransitionSequencePlayer plays generated door animation overlays for first-slice door transitions.",
            ],
            "gaps": [
                "Arrow warps, directional stair warps, secret-base door entry, and source ownership through FieldInput are pending.",
            ],
        },
        {
            "id": "standard_wild_tail_order",
            "source_entry": "src/field_control_avatar.c:CheckStandardWildEncounter and ProcessPlayerFieldInput tail",
            "status": "first_pass",
            "critical_order": [
                "OW_FLAG_NO_ENCOUNTER blocks standard wild encounter checks",
                "sWildEncounterImmunitySteps counts from 0 up to four steps before StandardWildEncounter can run",
                "sPrevMetatileBehavior is updated every checked step",
                "successful StandardWildEncounter resets immunity to 0",
                "TryFindHiddenPokemon happens after Start menu handling and only on tookStep",
                "UseRegisteredKeyItemOnField happens after hidden Pokemon and only on SELECT",
                "TryStartDexNavSearch happens after registered item use and only on R",
            ],
            "godot_current": [
                "EventManager.dispatch_player_step keeps first-pass four-step standard wild immunity and previous/current metatile tracking.",
                "EncounterEngine performs first-pass source-order standard encounter generation when enough field context is supplied.",
            ],
            "gaps": [
                "Hidden Pokemon, registered item, and R-button DexNav field-input tail behavior are not source-equivalent yet.",
            ],
        },
        {
            "id": "walk_into_signpost_and_cancel_rules",
            "source_entry": "src/field_control_avatar.c:TrySetUpWalkIntoSignpostScript/CancelSignPostMessageBox",
            "status": "metadata_only",
            "critical_order": SIGNPOST_RULES,
            "godot_current": [
                "MapRuntime can return first-slice sign interaction targets from BG events.",
            ],
            "gaps": [
                "Walk-into signpost auto-trigger and cancelable signpost message timing are pending.",
            ],
        },
        {
            "id": "debug_and_spin_evolution_tail",
            "source_entry": "src/field_control_avatar.c:ProcessPlayerFieldInput tail",
            "status": "metadata_only",
            "critical_order": [
                "input_field_1_2 opens the source DEBUG_OVERWORLD_MENU path after R-button DexNav checks",
                "debug menu plays SE_WIN_OPEN, freezes object events, then calls Debug_ShowMainMenu",
                "CanTriggerSpinEvolution is checked after the debug menu path",
                "spin evolution resets the spin timer and calls TrySpecialOverworldEvo",
            ],
            "godot_current": [
                "Main already registers F6/F7 battle debug launchers.",
                "The overworld TODO tracks a separate debug key/panel for avatar state, teleport, and weather controls.",
            ],
            "gaps": [
                "Source debug menu parity is separate from Godot-only developer tooling.",
            ],
        },
        {
            "id": "godot_current_field_control_mapping",
            "source_entry": "Godot runtime owner map",
            "status": "unsupported",
            "critical_order": [
                "PlayerController owns direct input sampling and basic normal on-foot movement",
                "Main owns OnFrame precheck, interaction dispatch, blocked-door checks, debug keys, and transition handoff",
                "EventManager owns generated script dispatch, player-step summaries, standard wild checks, and transition requests",
                "MapRuntime owns current map cell, event, warp, coord-event, and metatile behavior lookup",
            ],
            "godot_current": [
                "This split is workable for Godot architecture but still needs a source-shaped field-control contract between the owners.",
            ],
            "gaps": [
                "The runtime must converge on the source ProcessPlayerFieldInput priority without copying GBA hardware constraints.",
            ],
        },
    ]


def manifest_entry_for(exported, output_path):
    stats = exported["stats"]
    return {
        "category": "overworld_field_control_trace",
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
        "field_input_flags": FIELD_INPUT_FLAGS,
        "process_player_field_input_order": PROCESS_PLAYER_FIELD_INPUT_ORDER,
        "step_based_script_order": STEP_BASED_SCRIPT_ORDER,
        "step_count_order": STEP_COUNT_ORDER,
        "interaction_resolution_order": INTERACTION_RESOLUTION_ORDER,
        "metatile_script_order": METATILE_SCRIPT_ORDER,
        "water_and_dive_rules": WATER_AND_DIVE_RULES,
        "coord_event_rules": COORD_EVENT_RULES,
        "warp_rules": WARP_RULES,
        "door_arrow_rules": DOOR_ARROW_RULES,
        "signpost_rules": SIGNPOST_RULES,
        "source_flows": flow_rows,
        "godot_trace_owners": {
            "runtime": [
                "scripts/autoload/event_manager.gd",
                "scripts/autoload/map_runtime.gd",
                "scripts/autoload/script_vm.gd",
            ],
            "presentation_input": [
                "scripts/main.gd",
                "scripts/overworld/player_controller.gd",
                "scripts/overworld/transition_sequence_player.gd",
            ],
            "debug_lane": [
                "scripts/main.gd:F6/F7 battle debug keys",
                "wiki/overworld-parity-todo.md:Godot-only overworld debug toolkit",
            ],
            "tests": [
                "tools/godot_smoke/event_manager_smoke.gd",
                "tools/godot_smoke/field_wild_encounter_smoke.gd",
                "tools/godot_smoke/transition_presentation_smoke.gd",
                "tools/godot_smoke/player_turn_input_smoke.gd",
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

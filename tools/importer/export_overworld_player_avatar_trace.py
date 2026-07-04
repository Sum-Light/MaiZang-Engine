#!/usr/bin/env python3
"""Export source-traced overworld player-avatar state coverage."""

import argparse
import json
import re
import sys
from pathlib import Path

from export_map import write_json, write_manifest
from source_probe import load_config, to_project_path


GENERATED_BY = "tools/importer/export_overworld_player_avatar_trace.py"
REPORT_PATH = Path("overworld/player_avatar_trace.json")

SOURCE_FILES = [
    "include/global.fieldmap.h",
    "include/field_player_avatar.h",
    "src/field_player_avatar.c",
    "include/bike.h",
    "src/bike.c",
    "include/event_object_movement.h",
    "src/event_object_movement.c",
    "include/constants/event_objects.h",
    "include/constants/metatile_behaviors.h",
    "src/metatile_behavior.c",
    "src/field_control_avatar.c",
    "src/field_effect.c",
    "src/follower_npc.c",
    "src/overworld.c",
    "src/item_use.c",
    "src/fishing.c",
]

REQUIRED_SYMBOLS = [
    "PlayerAvatar",
    "PLAYER_AVATAR_STATE_NORMAL",
    "PLAYER_AVATAR_STATE_MACH_BIKE",
    "PLAYER_AVATAR_STATE_ACRO_BIKE",
    "PLAYER_AVATAR_STATE_SURFING",
    "PLAYER_AVATAR_STATE_UNDERWATER",
    "PLAYER_AVATAR_STATE_FIELD_MOVE",
    "PLAYER_AVATAR_STATE_FISHING",
    "PLAYER_AVATAR_STATE_WATERING",
    "PLAYER_AVATAR_STATE_VSSEEKER",
    "PLAYER_AVATAR_FLAG_ON_FOOT",
    "PLAYER_AVATAR_FLAG_MACH_BIKE",
    "PLAYER_AVATAR_FLAG_ACRO_BIKE",
    "PLAYER_AVATAR_FLAG_SURFING",
    "PLAYER_AVATAR_FLAG_UNDERWATER",
    "PLAYER_AVATAR_FLAG_CONTROLLABLE",
    "PLAYER_AVATAR_FLAG_FORCED_MOVE",
    "PLAYER_AVATAR_FLAG_DASH",
    "PLAYER_AVATAR_FLAG_BIKE",
    "FOLLOWER_INVISIBLE_FLAGS",
    "Collision",
    "COLLISION_NONE",
    "COLLISION_STOP_SURFING",
    "COLLISION_LEDGE_JUMP",
    "COLLISION_STAIR_WARP",
    "NOT_MOVING",
    "TURN_DIRECTION",
    "MOVING",
    "T_NOT_MOVING",
    "T_TILE_TRANSITION",
    "T_TILE_CENTER",
    "gPlayerAvatar",
    "sForcedMovementTestFuncs",
    "sForcedMovementFuncs",
    "sPlayerNotOnBikeFuncs",
    "sAcroBikeTrickMetatiles",
    "sAcroBikeTrickCollisionTypes",
    "sPlayerAvatarTransitionFuncs",
    "sPlayerAvatarGfxIds",
    "sRivalAvatarGfxIds",
    "sPlayerAvatarGfxToStateFlag",
    "PlayerStep",
    "TryInterruptObjectEventSpecialAnim",
    "MovePlayerAvatarUsingKeypadInput",
    "PlayerAllowForcedMovementIfMovingSameDirection",
    "TryUpdatePlayerSpinDirection",
    "TryDoMetatileBehaviorForcedMovement",
    "GetForcedMovementByMetatileBehavior",
    "ForcedMovement_None",
    "DoForcedMovement",
    "DoForcedMovementInCurrentDirection",
    "ForcedMovement_Slip",
    "ForcedMovement_MuddySlope",
    "ForcedMovement_MatJump",
    "ForcedMovement_MatSpin",
    "MovePlayerNotOnBike",
    "CheckMovementInputNotOnBike",
    "PlayerNotOnBikeNotMoving",
    "PlayerNotOnBikeTurningInPlace",
    "PlayerNotOnBikeMoving",
    "CanTriggerSpinEvolution",
    "CheckForPlayerAvatarCollision",
    "CheckForPlayerAvatarStaticCollision",
    "CheckForObjectEventCollision",
    "CheckForObjectEventStaticCollision",
    "GetCollisionAtCoords",
    "CanStopSurfing",
    "ShouldJumpLedge",
    "TryPushBoulder",
    "CheckAcroBikeCollision",
    "SetPlayerAvatarTransitionFlags",
    "DoPlayerAvatarTransition",
    "PlayerAvatarTransition_Normal",
    "PlayerAvatarTransition_MachBike",
    "PlayerAvatarTransition_AcroBike",
    "PlayerAvatarTransition_Surfing",
    "PlayerAvatarTransition_Underwater",
    "PlayerAvatarTransition_ReturnToField",
    "UpdatePlayerAvatarTransitionState",
    "PlayerAnimIsMultiFrameStationary",
    "PlayerSetAnimId",
    "PlayerWalkNormal",
    "PlayerWalkFast",
    "PlayerRideWaterCurrent",
    "PlayerWalkFaster",
    "PlayerRun",
    "PlayerOnBikeCollide",
    "PlayerNotOnBikeCollide",
    "PlayerFaceDirection",
    "PlayerTurnInPlace",
    "PlayerJumpLedge",
    "PlayerFreeze",
    "PlayerApplyTileForcedMovement",
    "PlayCollisionSoundIfNotFacingWarp",
    "GetXYCoordsOneStepInFrontOfPlayer",
    "PlayerGetDestCoords",
    "player_get_pos_including_state_based_drift",
    "GetPlayerFacingDirection",
    "GetPlayerMovementDirection",
    "PlayerGetElevation",
    "TestPlayerAvatarFlags",
    "GetPlayerAvatarFlags",
    "StopPlayerAvatar",
    "GetPlayerAvatarGraphicsIdByStateIdAndGender",
    "GetPlayerAvatarGraphicsIdByStateId",
    "GetPlayerAvatarGenderByGraphicsId",
    "PartyHasMonWithSurf",
    "IsPlayerSurfingNorth",
    "IsPlayerFacingSurfableFishableWater",
    "ClearPlayerAvatarInfo",
    "SetPlayerAvatarStateMask",
    "GetPlayerAvatarGraphicsIdByCurrentState",
    "SetPlayerAvatarExtraStateTransition",
    "InitPlayerAvatar",
    "SetPlayerInvisibility",
    "SetPlayerAvatarFieldMove",
    "SetPlayerAvatarFishing",
    "PlayerUseAcroBikeOnBumpySlope",
    "SetPlayerAvatarWatering",
    "HideShowWarpArrow",
    "StartStrengthAnim",
    "CreateStopSurfingTask",
    "Task_StopSurfingInit",
    "Task_WaitStopSurfing",
    "MovePlayerOnBike",
    "MovePlayerOnMachBike",
    "MovePlayerOnAcroBike",
    "sMachBikeSpeeds",
    "sAcroBikeInputHandlers",
    "sAcroBikeTransitions",
    "GetBikeCollision",
    "GetBikeCollisionAt",
    "GetOnOffBike",
    "BikeClearState",
    "Bike_UpdateBikeCounterSpeed",
    "GetPlayerSpeed",
    "Bike_HandleBumpySlopeJump",
    "IsRunningDisallowed",
    "IsBikingDisallowedByPlayer",
]

PLAYER_AVATAR_STATES = [
    {
        "state": "PLAYER_AVATAR_STATE_NORMAL",
        "male_graphics": "PLAYER_AVATAR_GFX_MALE_NORMAL",
        "female_graphics": "PLAYER_AVATAR_GFX_FEMALE_NORMAL",
        "state_flag": "PLAYER_AVATAR_FLAG_ON_FOOT",
    },
    {
        "state": "PLAYER_AVATAR_STATE_MACH_BIKE",
        "male_graphics": "PLAYER_AVATAR_GFX_MALE_MACH_BIKE",
        "female_graphics": "PLAYER_AVATAR_GFX_FEMALE_MACH_BIKE",
        "state_flag": "PLAYER_AVATAR_FLAG_MACH_BIKE",
    },
    {
        "state": "PLAYER_AVATAR_STATE_ACRO_BIKE",
        "male_graphics": "PLAYER_AVATAR_GFX_MALE_ACRO_BIKE",
        "female_graphics": "PLAYER_AVATAR_GFX_FEMALE_ACRO_BIKE",
        "state_flag": "PLAYER_AVATAR_FLAG_ACRO_BIKE",
    },
    {
        "state": "PLAYER_AVATAR_STATE_SURFING",
        "male_graphics": "PLAYER_AVATAR_GFX_MALE_SURFING",
        "female_graphics": "PLAYER_AVATAR_GFX_FEMALE_SURFING",
        "state_flag": "PLAYER_AVATAR_FLAG_SURFING",
    },
    {
        "state": "PLAYER_AVATAR_STATE_UNDERWATER",
        "male_graphics": "PLAYER_AVATAR_GFX_MALE_UNDERWATER",
        "female_graphics": "PLAYER_AVATAR_GFX_FEMALE_UNDERWATER",
        "state_flag": "PLAYER_AVATAR_FLAG_UNDERWATER",
    },
    {
        "state": "PLAYER_AVATAR_STATE_FIELD_MOVE",
        "male_graphics": "PLAYER_AVATAR_GFX_MALE_FIELD_MOVE",
        "female_graphics": "PLAYER_AVATAR_GFX_FEMALE_FIELD_MOVE",
        "state_flag": "temporary graphics, not in sPlayerAvatarGfxToStateFlag",
    },
    {
        "state": "PLAYER_AVATAR_STATE_FISHING",
        "male_graphics": "PLAYER_AVATAR_GFX_MALE_FISHING",
        "female_graphics": "PLAYER_AVATAR_GFX_FEMALE_FISHING",
        "state_flag": "temporary graphics, not in sPlayerAvatarGfxToStateFlag",
    },
    {
        "state": "PLAYER_AVATAR_STATE_WATERING",
        "male_graphics": "PLAYER_AVATAR_GFX_MALE_WATERING",
        "female_graphics": "PLAYER_AVATAR_GFX_FEMALE_WATERING",
        "state_flag": "temporary graphics, not in sPlayerAvatarGfxToStateFlag",
    },
    {
        "state": "PLAYER_AVATAR_STATE_VSSEEKER",
        "male_graphics": "PLAYER_AVATAR_GFX_MALE_VSSEEKER",
        "female_graphics": "PLAYER_AVATAR_GFX_FEMALE_VSSEEKER",
        "state_flag": "temporary graphics, not in sPlayerAvatarGfxToStateFlag",
    },
]

FORCED_MOVEMENT_ORDER = [
    "MetatileBehavior_IsTrickHouseSlipperyFloor -> ForcedMovement_Slip",
    "MetatileBehavior_IsIce_2 -> ForcedMovement_Slip",
    "MetatileBehavior_IsWalkSouth -> ForcedMovement_WalkSouth",
    "MetatileBehavior_IsWalkNorth -> ForcedMovement_WalkNorth",
    "MetatileBehavior_IsWalkWest -> ForcedMovement_WalkWest",
    "MetatileBehavior_IsWalkEast -> ForcedMovement_WalkEast",
    "MetatileBehavior_IsSouthwardCurrent -> ForcedMovement_PushedSouthByCurrent",
    "MetatileBehavior_IsNorthwardCurrent -> ForcedMovement_PushedNorthByCurrent",
    "MetatileBehavior_IsWestwardCurrent -> ForcedMovement_PushedWestByCurrent",
    "MetatileBehavior_IsEastwardCurrent -> ForcedMovement_PushedEastByCurrent",
    "MetatileBehavior_IsSlideSouth -> ForcedMovement_SlideSouth",
    "MetatileBehavior_IsSlideNorth -> ForcedMovement_SlideNorth",
    "MetatileBehavior_IsSlideWest -> ForcedMovement_SlideWest",
    "MetatileBehavior_IsSlideEast -> ForcedMovement_SlideEast",
    "MetatileBehavior_IsWaterfall -> ForcedMovement_PushedSouthByCurrent",
    "MetatileBehavior_IsSecretBaseJumpMat -> ForcedMovement_MatJump",
    "MetatileBehavior_IsSecretBaseSpinMat -> ForcedMovement_MatSpin",
    "MetatileBehavior_IsMuddySlope -> ForcedMovement_MuddySlope",
    "MetatileBehavior_IsSpinRight -> ForcedMovement_SpinRight",
    "MetatileBehavior_IsSpinLeft -> ForcedMovement_SpinLeft",
    "MetatileBehavior_IsSpinUp -> ForcedMovement_SpinUp",
    "MetatileBehavior_IsSpinDown -> ForcedMovement_SpinDown",
]

PLAYER_STEP_ORDER = [
    "HideShowWarpArrow",
    "skip all step input when gPlayerAvatar.preventStep is true",
    "TryUpdatePlayerSpinDirection can consume the frame while already in forced spin movement",
    "Bike_TryAcroBikeHistoryUpdate(newKeys, heldKeys)",
    "TryInterruptObjectEventSpecialAnim",
    "npc_clear_strange_bits clears inanimate/disableAnim/facingDirectionLocked and dash flag",
    "DoPlayerAvatarTransition consumes pending transitionFlags",
    "TryDoMetatileBehaviorForcedMovement",
    "follower forced-movement handoff can set preventStep",
    "MovePlayerAvatarUsingKeypadInput",
    "PlayerAllowForcedMovementIfMovingSameDirection clears controllable while moving",
]

NON_BIKE_MOVEMENT_ORDER = [
    "CheckMovementInputNotOnBike returns NOT_MOVING when direction is DIR_NONE",
    "different direction while not already MOVING returns TURN_DIRECTION",
    "otherwise returns MOVING",
    "NOT_MOVING -> PlayerFaceDirection(current facing)",
    "TURN_DIRECTION -> WindUpSpinTimer(direction), PlayerTurnInPlace(direction)",
    "MOVING -> CheckForPlayerAvatarCollision(direction)",
    "COLLISION_LEDGE_JUMP -> PlayerJumpLedge",
    "COLLISION_OBJECT_EVENT with Faraway Island Mew -> special collide action",
    "COLLISION_STAIR_WARP -> PlayerFaceDirection(direction)",
    "ordinary blocking collisions -> PlayerNotOnBikeCollide unless excluded collision types apply",
    "successful surf movement uses PlayerWalkFast, or PlayerWalkSlow when DexNav searching and A held",
    "successful running requires B held, FLAG_SYS_B_DASH, not underwater, running allowed, no follower door handoff, and no ORAS dowsing overlay",
    "ordinary successful movement uses PlayerWalkSlowStairs on rock stairs or PlayerWalkNormal otherwise",
]

COLLISION_PIPELINE = [
    "CheckForPlayerAvatarCollision first checks current-cell directional stair warp behavior",
    "destination coords are moved one step in the requested direction",
    "CheckForObjectEventCollision starts with GetCollisionAtCoords",
    "COLLISION_ELEVATION_MISMATCH can become COLLISION_STOP_SURFING through CanStopSurfing",
    "ShouldJumpLedge increments GAME_STAT_JUMPED_DOWN_LEDGES and returns COLLISION_LEDGE_JUMP",
    "COLLISION_OBJECT_EVENT can become COLLISION_PUSHED_BOULDER when Strength and boulder rules allow",
    "COLLISION_NONE can become COLLISION_ROTATING_GATE",
    "COLLISION_NONE can become Acro Bike trick collisions for bumpy slopes and rails",
]

TRANSITION_RULES = [
    "SetPlayerAvatarTransitionFlags ORs pending transitionFlags then immediately calls DoPlayerAvatarTransition",
    "DoPlayerAvatarTransition scans transitionFlags bit-by-bit in PLAYER_AVATAR_STATE order",
    "Normal transition sets normal graphics, turns object, and masks state to PLAYER_AVATAR_FLAG_ON_FOOT",
    "Mach Bike transition sets Mach Bike graphics, turns object, masks state to bike flag, and clears bike state",
    "Acro Bike transition sets Acro Bike graphics, turns object, masks state to bike flag, clears bike state, and handles bumpy slope jump",
    "Surfing transition sets surf graphics, masks state to surfing, starts FLDEFF_SURF_BLOB, and sets BOB_PLAYER_AND_MON",
    "Underwater transition sets underwater graphics, masks state to underwater, and starts underwater surf-blob bobbing",
    "Return-to-field transition only restores PLAYER_AVATAR_FLAG_CONTROLLABLE",
    "SetPlayerAvatarStateMask preserves dash, forced-move, and controllable bits before applying the requested state flags",
]

BIKE_RULES = [
    "MovePlayerOnBike dispatches to standard bike when both Mach and Acro flags are set, Mach Bike when Mach only, otherwise Acro Bike",
    "Mach Bike speeds are PLAYER_SPEED_NORMAL, PLAYER_SPEED_FAST, PLAYER_SPEED_FASTEST by bikeFrameCounter",
    "Acro Bike has handlers for normal, turning, wheelie standing, bunny hop, wheelie moving, side jump, turn jump, and slope",
    "Acro trick input uses direction/button history with a 4-frame timer list",
    "Bike collision treats running-disallowed metatiles as impassable and advances Cycling Road collision count",
    "GetOnOffBike toggles between on-foot and requested bike flags while changing saved/current music",
    "GetPlayerSpeed returns Mach indexed speed, Acro faster speed, surfing/dash fast speed, or normal speed",
]

TILE_TRANSITION_RULES = [
    "UpdatePlayerAvatarTransitionState starts each update at T_NOT_MOVING",
    "active non-finished non-stationary movement -> T_TILE_TRANSITION",
    "finished or inactive movement that is not stationary while turning -> T_TILE_CENTER",
    "stationary actions include facing, delays, walk-in-place, and Acro wheelie in-place actions",
    "FieldGetPlayerInput consumes tileTransitionState and runningState to decide tookStep, wild checks, and button gates",
]

SURF_AND_SPECIAL_RULES = [
    "PartyHasMonWithSurf checks carried party moves only when the player is not already surfing",
    "IsPlayerFacingSurfableFishableWater requires front-cell elevation mismatch, player default elevation, and surfable/fishable water behavior",
    "IsPlayerSurfingNorth requires movement direction north while surfing",
    "CanStopSurfing starts CreateStopSurfingTask when surfing into default elevation with no blocking object or follower exception",
    "CreateStopSurfingTask locks controls, restores map music, toggles surfing off/on-foot on, sets preventStep, prepares follower dismount, jumps player, then restores normal graphics and destroys surf blob",
    "SetPlayerAvatarFieldMove, SetPlayerAvatarFishing, and SetPlayerAvatarWatering set temporary graphics and directional sprite animations",
    "Secret-base jump/spin mats set preventStep and play source movement/sound/task sequences",
]

UNSUPPORTED = [
    {
        "code": "player_avatar_state_struct_not_runtime_owned",
        "status": "unsupported",
        "source": "include/global.fieldmap.h:struct PlayerAvatar",
        "detail": "Godot does not yet keep a source-shaped player avatar state object with flags, transitionFlags, runningState, tileTransitionState, bike counters, acro history, and spin tile.",
    },
    {
        "code": "full_player_step_loop_pending",
        "status": "unsupported",
        "source": "src/field_player_avatar.c:PlayerStep",
        "detail": "PlayerController currently reads direct Godot input and handles only first-pass normal turn/walk; the full PlayerStep order is not runtime-owned yet.",
    },
    {
        "code": "forced_movement_state_machine_pending",
        "status": "unsupported",
        "source": "src/field_player_avatar.c:sForcedMovementTestFuncs/sForcedMovementFuncs",
        "detail": "Ice, currents, slide tiles, waterfall, muddy slope, spin tiles, and secret-base jump/spin mats are preserved as trace metadata but are not implemented.",
    },
    {
        "code": "source_collision_pipeline_pending",
        "status": "unsupported",
        "source": "src/field_player_avatar.c:CheckForObjectEventCollision + src/event_object_movement.c:GetCollisionAtCoords",
        "detail": "Godot MapRuntime.can_enter_cell is still bounds + collision == 0 + object occupancy, without elevation mismatch, ledges, boulders, rotating gates, stair warps, rails, stop-surfing, or sideways stair rules.",
    },
    {
        "code": "mach_bike_state_pending",
        "status": "unsupported",
        "source": "src/bike.c:MovePlayerOnMachBike/GetPlayerSpeed",
        "detail": "Mach Bike acceleration, fastest speed gating, muddy-slope exception, Cycling Road behavior, and source movement actions are not implemented.",
    },
    {
        "code": "acro_bike_tricks_pending",
        "status": "unsupported",
        "source": "src/bike.c:MovePlayerOnAcroBike/AcroBike_TryHistoryUpdate",
        "detail": "Acro Bike wheelies, bunny hops, side jumps, turn jumps, slope states, rail collisions, and 4-frame trick history are pending.",
    },
    {
        "code": "surf_underwater_avatar_pending",
        "status": "unsupported",
        "source": "src/field_player_avatar.c:PlayerAvatarTransition_Surfing/PlayerAvatarTransition_Underwater",
        "detail": "Surfing and underwater graphics, blob field effects, bob state, stop-surfing task, and follower dismount behavior remain future work.",
    },
    {
        "code": "avatar_transition_effects_pending",
        "status": "unsupported",
        "source": "src/field_player_avatar.c:DoPlayerAvatarTransition",
        "detail": "Godot currently swaps only normal Brendan/May graphics from gender; transitionFlags and source state-mask semantics are not implemented.",
    },
    {
        "code": "tile_transition_state_pending",
        "status": "unsupported",
        "source": "src/field_player_avatar.c:UpdatePlayerAvatarTransitionState",
        "detail": "Godot movement completion does not yet expose T_NOT_MOVING/T_TILE_TRANSITION/T_TILE_CENTER exactly for field input and encounter gates.",
    },
    {
        "code": "run_dash_creep_pending",
        "status": "unsupported",
        "source": "src/field_player_avatar.c:PlayerNotOnBikeMoving",
        "detail": "B-button dash, DexNav creep, running-disallowed checks, rock-stair slow run/walk, and dash flag clearing are not runtime-equivalent.",
    },
    {
        "code": "field_move_fishing_watering_pending",
        "status": "unsupported",
        "source": "src/field_player_avatar.c:SetPlayerAvatarFieldMove/SetPlayerAvatarFishing/SetPlayerAvatarWatering",
        "detail": "Temporary field-move, fishing, watering, and VS Seeker player graphics and directional animations are not implemented.",
    },
    {
        "code": "normal_walk_turn_first_pass_only",
        "status": "first_pass",
        "source": "src/field_player_avatar.c:PlayerWalkNormal/PlayerTurnInPlace + src/event_object_movement.c:SetStepAnimHandleAlternation",
        "detail": "PlayerController drives source-timed normal Brendan/May walk and turn-in-place frames, but the surrounding source avatar state machine is still pending.",
    },
    {
        "code": "debug_avatar_switcher_pending",
        "status": "unsupported",
        "source": "Godot-only debug lane",
        "detail": "The overworld debug toolkit still needs a key/panel to request avatar state previews through future avatar runtime APIs without pretending to be source gameplay.",
    },
    {
        "code": "palette_affine_effects_godot_native",
        "status": "metadata_only",
        "source": "Project porting constraint",
        "detail": "Player-avatar palette swaps, tinting, scaling, rotation, or affine-like effects should use Godot-native materials/animation while preserving source timing and visible result, not runtime GBA palette/OAM limits.",
    },
    {
        "code": "audio_playback_pending",
        "status": "metadata_only",
        "source": "SE_WALL_HIT/SE_LEDGE/SE_BIKE_HOP/SE_M_STRENGTH and avatar-related sound cues",
        "detail": "Sound symbols and timing intent are preserved in reports, but real audio playback remains intentionally out of scope.",
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
            "id": "player_avatar_data_model",
            "source_entry": "include/global.fieldmap.h:struct PlayerAvatar and enums",
            "status": "metadata_only",
            "critical_order": [
                "Player avatar state ids cover normal, Mach Bike, Acro Bike, surfing, underwater, field move, fishing, watering, and VS Seeker",
                "flags include on-foot, Mach Bike, Acro Bike, surfing, underwater, controllable, forced movement, and dash",
                "runningState values are NOT_MOVING, TURN_DIRECTION, and MOVING",
                "tileTransitionState values are T_NOT_MOVING, T_TILE_TRANSITION, and T_TILE_CENTER",
                "collision enum includes stop-surfing, ledge jump, pushed boulder, rotating gate, Acro rail/hop, stair warp, and sideways stairs",
            ],
            "godot_current": [
                "GameState stores player gender and grid position.",
                "PlayerController stores facing direction and sprite animation state only.",
            ],
            "gaps": [
                "No source-shaped avatar flags/counters/transition state object exists in Godot yet.",
            ],
        },
        {
            "id": "player_step_main_loop_order",
            "source_entry": "src/field_player_avatar.c:PlayerStep",
            "status": "metadata_only",
            "critical_order": PLAYER_STEP_ORDER,
            "godot_current": [
                "PlayerController reads ui_* input directly and checks a field-input precheck before accept/movement.",
            ],
            "gaps": [
                "The full source PlayerStep owner is pending.",
            ],
        },
        {
            "id": "forced_movement_table_order",
            "source_entry": "src/field_player_avatar.c:sForcedMovementTestFuncs/sForcedMovementFuncs",
            "status": "metadata_only",
            "critical_order": FORCED_MOVEMENT_ORDER,
            "godot_current": [
                "MapRuntime can expose source metatile behavior names for the current map.",
            ],
            "gaps": [
                "No forced-movement dispatch consumes those behavior names yet.",
            ],
        },
        {
            "id": "non_bike_input_state_machine",
            "source_entry": "src/field_player_avatar.c:MovePlayerNotOnBike/PlayerNotOnBikeMoving",
            "status": "first_pass",
            "critical_order": NON_BIKE_MOVEMENT_ORDER,
            "godot_current": [
                "PlayerController implements first-pass turn-in-place and normal walking with source-timed sprite frames.",
            ],
            "gaps": [
                "Dash, creep, surf movement, rock-stair slow movement, ledges, Mew, stair warp, and special collision effects are pending.",
            ],
        },
        {
            "id": "collision_pipeline",
            "source_entry": "src/field_player_avatar.c:CheckForPlayerAvatarCollision/CheckForObjectEventCollision",
            "status": "metadata_only",
            "critical_order": COLLISION_PIPELINE,
            "godot_current": [
                "MapRuntime.can_enter_cell checks bounds, generated collision == 0, and object occupancy.",
            ],
            "gaps": [
                "Source elevation, metatile-behavior, object-event collision, ledge, boulder, stop-surfing, and Acro collision semantics are pending.",
            ],
        },
        {
            "id": "bike_dispatch_speed_and_music",
            "source_entry": "src/bike.c:MovePlayerOnBike/GetPlayerSpeed/GetOnOffBike",
            "status": "metadata_only",
            "critical_order": BIKE_RULES,
            "godot_current": [
                "No player bike state exists yet.",
            ],
            "gaps": [
                "Bike movement, speed, music, and collision rules remain future work; sound/music stays metadata-only.",
            ],
        },
        {
            "id": "acro_bike_state_machine",
            "source_entry": "src/bike.c:CheckMovementInputAcroBike/sAcroBikeInputHandlers/sAcroBikeTransitions",
            "status": "metadata_only",
            "critical_order": [
                "Acro state handlers are indexed by gPlayerAvatar.acroBikeState",
                "normal state can pop a standing wheelie on new B without direction",
                "same direction plus held B from standing can enter wheelie-moving rise",
                "turning waits more than 6 frames before changing direction",
                "4-frame input history can trigger side jump or turn jump",
                "bumpy slope and rails feed special Acro collision/transition branches",
            ],
            "godot_current": [
                "No Acro Bike preview or runtime state exists yet.",
            ],
            "gaps": [
                "Will be needed both for gameplay and the requested debug avatar-state switcher.",
            ],
        },
        {
            "id": "avatar_transition_graphics",
            "source_entry": "src/field_player_avatar.c:sPlayerAvatarTransitionFuncs/sPlayerAvatarGfxIds",
            "status": "first_pass",
            "critical_order": TRANSITION_RULES,
            "godot_current": [
                "PlayerController chooses OBJ_EVENT_GFX_BRENDAN_NORMAL or OBJ_EVENT_GFX_MAY_NORMAL from GameState gender.",
                "Object-event sprite metadata contains first-pass normal Brendan/May animation data.",
            ],
            "gaps": [
                "All non-normal player graphics, transition flags, surf/underwater field effects, and temporary field-move/fishing/watering graphics are pending.",
            ],
        },
        {
            "id": "tile_transition_state",
            "source_entry": "src/field_player_avatar.c:UpdatePlayerAvatarTransitionState",
            "status": "metadata_only",
            "critical_order": TILE_TRANSITION_RULES,
            "godot_current": [
                "GridMover emits movement completion, but PlayerController does not expose source tileTransitionState.",
            ],
            "gaps": [
                "Field-input ordering and encounter gating need this source-shaped state.",
            ],
        },
        {
            "id": "movement_action_wrappers",
            "source_entry": "src/field_player_avatar.c:PlayerSetAnimId and movement wrappers",
            "status": "first_pass",
            "critical_order": [
                "PlayerSetAnimId sets copyable movement and held object-event movement only when no active player movement exists",
                "normal walk uses GetWalkNormalMovementAction and COPY_MOVE_WALK",
                "turn-in-place uses GetWalkInPlaceFastMovementAction and COPY_MOVE_FACE",
                "run, fast walk, faster walk, water current, collision, ledge jump, and Acro wheelie actions use distinct movement ids and copy modes",
                "wall hit, ledge, bike hop, Strength, spin, and surf-related sounds are source-timed cues but audio is metadata-only for now",
            ],
            "godot_current": [
                "PlayerController drives normal walk and turn-in-place sprite frames from generated object-event sprite animation tables.",
            ],
            "gaps": [
                "Most movement action ids and copyable movement modes are not runtime-modeled.",
            ],
        },
        {
            "id": "surf_underwater_and_special_avatar_modes",
            "source_entry": "src/field_player_avatar.c:PartyHasMonWithSurf/IsPlayerFacingSurfableFishableWater/CreateStopSurfingTask",
            "status": "metadata_only",
            "critical_order": SURF_AND_SPECIAL_RULES,
            "godot_current": [
                "Surf/Dive prompts are currently only reflected in field-control trace metadata.",
            ],
            "gaps": [
                "Surfing, underwater, field-move, fishing, watering, and secret-base mat player tasks are pending.",
            ],
        },
        {
            "id": "godot_current_player_avatar_mapping",
            "source_entry": "Godot runtime owner map",
            "status": "unsupported",
            "critical_order": [
                "PlayerController owns direct input, facing, first-pass normal turn/walk sprite animation, and interaction signal emission",
                "MapRuntime owns generated passability and object occupancy queries",
                "Main owns blocked movement handoff for connections and front-cell door warps",
                "EventManager owns player-step event dispatch after movement finishes",
                "Object-event sprite metadata owns the first player normal walk/turn animation tables",
            ],
            "godot_current": [
                "This split should converge toward a source-shaped avatar runtime contract rather than direct texture swaps.",
            ],
            "gaps": [
                "The requested debug avatar-state switcher should target the future avatar runtime API and report unsupported states explicitly.",
            ],
        },
    ]


def manifest_entry_for(exported, output_path):
    stats = exported["stats"]
    return {
        "category": "overworld_player_avatar_trace",
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
        "player_avatar_states": PLAYER_AVATAR_STATES,
        "player_step_order": PLAYER_STEP_ORDER,
        "forced_movement_order": FORCED_MOVEMENT_ORDER,
        "non_bike_movement_order": NON_BIKE_MOVEMENT_ORDER,
        "collision_pipeline": COLLISION_PIPELINE,
        "transition_rules": TRANSITION_RULES,
        "bike_rules": BIKE_RULES,
        "tile_transition_rules": TILE_TRANSITION_RULES,
        "surf_and_special_rules": SURF_AND_SPECIAL_RULES,
        "visual_effect_policy": {
            "palette_and_affine": "Use Godot-native textures, materials, shaders, animation, and resources for palette, tint, scale, rotation, and affine-like presentation while preserving source timing/visible result where practical.",
            "gba_runtime_limits": "Do not recreate GBA palette-bank, VRAM, or OAM limits at runtime unless a gameplay rule explicitly depends on them.",
            "audio": "Sound/music symbols stay metadata_only/unsupported until audio scope is reopened.",
        },
        "source_flows": flow_rows,
        "godot_trace_owners": {
            "runtime": [
                "scripts/overworld/player_controller.gd",
                "scripts/autoload/map_runtime.gd",
                "scripts/autoload/event_manager.gd",
            ],
            "generated_assets": [
                "data/generated/object_events/object_event_sprites.json",
                "tools/importer/export_object_event_sprites.py",
            ],
            "debug_lane": [
                "wiki/overworld-parity-todo.md:Godot-only overworld debug toolkit",
            ],
            "tests": [
                "tools/godot_smoke/player_turn_input_smoke.gd",
                "tools/godot_smoke/object_event_sprite_smoke.gd",
                "tools/godot_smoke/field_wild_encounter_smoke.gd",
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

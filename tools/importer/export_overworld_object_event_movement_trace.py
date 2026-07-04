#!/usr/bin/env python3
"""Export source-traced overworld object-event movement coverage."""

import argparse
import json
import re
import sys
from pathlib import Path

from export_map import write_json, write_manifest
from source_probe import load_config, to_project_path


GENERATED_BY = "tools/importer/export_overworld_object_event_movement_trace.py"
REPORT_PATH = Path("overworld/object_event_movement_trace.json")

SOURCE_FILES = [
    "include/global.fieldmap.h",
    "include/event_object_movement.h",
    "include/constants/event_objects.h",
    "include/constants/event_object_movement.h",
    "include/constants/field_effects.h",
    "src/event_object_movement.c",
    "src/script_movement.c",
    "src/event_object_lock.c",
    "src/field_effect_helpers.c",
    "src/field_effect.c",
    "src/follower_npc.c",
    "src/field_player_avatar.c",
    "src/data/object_events/base_oam.h",
    "src/data/object_events/object_event_graphics.h",
    "src/data/object_events/object_event_graphics_info.h",
    "src/data/object_events/object_event_graphics_info_pointers.h",
    "src/data/object_events/object_event_pic_tables.h",
    "src/data/object_events/object_event_anims.h",
    "src/data/object_events/object_event_subsprites.h",
    "src/data/object_events/movement_type_func_tables.h",
    "src/data/object_events/movement_action_func_tables.h",
]

REQUIRED_SYMBOLS = [
    "ObjectEventTemplate",
    "ObjectEvent",
    "ObjectEventGraphicsInfo",
    "gObjectEvents",
    "OBJECT_EVENTS_COUNT",
    "NUM_MOVEMENT_TYPES",
    "MOVEMENT_TYPE_NONE",
    "MOVEMENT_TYPE_LOOK_AROUND",
    "MOVEMENT_TYPE_WANDER_AROUND",
    "MOVEMENT_TYPE_WANDER_UP_AND_DOWN",
    "MOVEMENT_TYPE_WANDER_LEFT_AND_RIGHT",
    "MOVEMENT_TYPE_FACE_UP",
    "MOVEMENT_TYPE_FACE_DOWN",
    "MOVEMENT_TYPE_FACE_LEFT",
    "MOVEMENT_TYPE_FACE_RIGHT",
    "MOVEMENT_TYPE_PLAYER",
    "MOVEMENT_TYPE_COPY_PLAYER",
    "MOVEMENT_TYPE_COPY_PLAYER_IN_GRASS",
    "MOVEMENT_TYPE_FOLLOW_PLAYER",
    "MOVEMENT_TYPE_INVISIBLE",
    "MOVEMENT_ACTION_NONE",
    "MOVEMENT_ACTION_FACE_DOWN",
    "MOVEMENT_ACTION_WALK_NORMAL_DOWN",
    "MOVEMENT_ACTION_WALK_FAST_DOWN",
    "MOVEMENT_ACTION_WALK_FASTER_DOWN",
    "MOVEMENT_ACTION_PLAYER_RUN_DOWN",
    "MOVEMENT_ACTION_JUMP_DOWN",
    "MOVEMENT_ACTION_JUMP_IN_PLACE_DOWN",
    "MOVEMENT_ACTION_HIDE_REFLECTION",
    "MOVEMENT_ACTION_SHOW_REFLECTION",
    "MOVEMENT_ACTION_INIT_AFFINE_ANIM",
    "MOVEMENT_ACTION_CLEAR_AFFINE_ANIM",
    "MOVEMENT_ACTION_STEP_END",
    "COLLISION_NONE",
    "COLLISION_OUTSIDE_RANGE",
    "COLLISION_IMPASSABLE",
    "COLLISION_ELEVATION_MISMATCH",
    "COLLISION_OBJECT_EVENT",
    "COLLISION_SIDEWAYS_STAIRS_TO_LEFT",
    "COLLISION_SIDEWAYS_STAIRS_TO_RIGHT",
    "SHADOW_SIZE_S",
    "SHADOW_SIZE_M",
    "SHADOW_SIZE_L",
    "SHADOW_SIZE_NONE",
    "TRACKS_NONE",
    "TRACKS_FOOT",
    "TRACKS_BIKE_TIRE",
    "TRACKS_SLITHER",
    "TRACKS_SPOT",
    "TRACKS_BUG",
    "sMovementTypeCallbacks",
    "sMovementTypeHasRange",
    "gInitialMovementTypeFacingDirections",
    "gMovementTypeFuncs_WanderAround",
    "gMovementTypeFuncs_LookAround",
    "gMovementTypeFuncs_WanderUpAndDown",
    "gMovementTypeFuncs_WanderLeftAndRight",
    "gMovementTypeFuncs_FaceDirection",
    "gMovementTypeFuncs_WalkBackAndForth",
    "gMovementTypeFuncs_CopyPlayer",
    "gMovementTypeFuncs_CopyPlayerInGrass",
    "gMovementTypeFuncs_FollowPlayer",
    "gMovementTypeFuncs_Invisible",
    "gMovementActionFuncs",
    "gMovementActionFuncs_FaceDown",
    "gMovementActionFuncs_WalkNormalDown",
    "gMovementActionFuncs_WalkFastDown",
    "gMovementActionFuncs_WalkInPlaceFastDown",
    "gMovementActionFuncs_PlayerRunDown",
    "gMovementActionFuncs_JumpDown",
    "gMovementActionFuncs_HideReflection",
    "gMovementActionFuncs_ShowReflection",
    "ClearObjectEvent",
    "ClearAllObjectEvents",
    "ResetObjectEvents",
    "InitObjectEventStateFromTemplate",
    "TrySetupObjectEventSprite",
    "TrySpawnObjectEventTemplate",
    "SpawnSpecialObjectEvent",
    "SpawnSpecialObjectEventParameterized",
    "TrySpawnObjectEvent",
    "TrySpawnObjectEvents",
    "UpdateObjectEventsForCameraUpdate",
    "RemoveObjectEvent",
    "RemoveObjectEventByLocalIdAndMap",
    "GetObjectEventIdByLocalIdAndMap",
    "GetObjectEventIdByXY",
    "GetObjectEventIdByPosition",
    "SetObjectEventDynamicGraphicsId",
    "GetObjectEventGraphicsInfo",
    "ObjectEventSetGraphicsId",
    "SetObjectEventDirection",
    "ObjectEventTurn",
    "ShiftObjectEventCoords",
    "ShiftStillObjectEventCoords",
    "MoveObjectEventToMapCoords",
    "TryMoveObjectEventToMapCoords",
    "ObjectEventMoveDestCoords",
    "UpdateObjectEventCurrentMovement",
    "ClearObjectEventMovement",
    "ObjectEventSetHeldMovement",
    "ObjectEventForceSetHeldMovement",
    "ObjectEventClearHeldMovement",
    "ObjectEventClearHeldMovementIfActive",
    "ObjectEventClearHeldMovementIfFinished",
    "ObjectEventCheckHeldMovementStatus",
    "ObjectEventGetHeldMovementActionId",
    "ObjectEventExecHeldMovementAction",
    "ObjectEventExecSingleMovementAction",
    "TryUpdateMovementActionOnStairs",
    "GetFaceDirectionMovementAction",
    "GetWalkNormalMovementAction",
    "GetWalkFastMovementAction",
    "GetWalkInPlaceFastMovementAction",
    "GetPlayerRunMovementAction",
    "GetJumpMovementAction",
    "SetStepAnim",
    "SetStepAnimHandleAlternation",
    "InitNpcForMovement",
    "NpcTakeStep",
    "GetCollisionAtCoords",
    "GetVanillaCollision",
    "GetSidewaysStairsCollision",
    "GetCollisionFlagsAtCoords",
    "GetObjectObjectCollidesWith",
    "DoesObjectCollideWithObjectAt",
    "IsCoordOutsideObjectEventMovementRange",
    "IsMetatileDirectionallyImpassable",
    "IsElevationMismatchAt",
    "AreElevationsCompatible",
    "sElevationToSubpriority",
    "sElevationToPriority",
    "ObjectEventUpdateElevation",
    "SetObjectSubpriorityByElevation",
    "ObjectEventUpdateSubpriority",
    "UpdateObjectEventVisibility",
    "UpdateObjectEventOffscreen",
    "UpdateObjectEventSpriteVisibility",
    "UpdateObjectEventSpriteInvisibility",
    "DoGroundEffects_OnSpawn",
    "DoGroundEffects_OnBeginStep",
    "DoGroundEffects_OnFinishStep",
    "GetAllGroundEffectFlags_OnSpawn",
    "GetAllGroundEffectFlags_OnBeginStep",
    "GetAllGroundEffectFlags_OnFinishStep",
    "GroundEffect_WaterReflection",
    "GroundEffect_IceReflection",
    "GroundEffect_SandTracks",
    "GroundEffect_DeepSandTracks",
    "GroundEffect_Ripple",
    "GroundEffect_StepOnPuddle",
    "GroundEffect_JumpLandingDust",
    "GroundEffect_ShortGrass",
    "GroundEffect_HotSprings",
    "GroundEffect_Seaweed",
    "DoTracksGroundEffect_Footprints",
    "DoTracksGroundEffect_BikeTireTracks",
    "DoTracksGroundEffect_SlitherTracks",
    "SetUpShadow",
    "SetUpReflection",
    "UpdateObjectReflectionSprite",
    "GetGroundEffectFlags_Reflection",
    "ObjectEventGetNearbyReflectionType",
    "GetReflectionTypeByMetatileBehavior",
    "gReflectionEffectPaletteMap",
    "LoadPlayerObjectReflectionPalette",
    "LoadSpecialObjectReflectionPalette",
    "FreezeObjectEvent",
    "FreezeObjectEvents",
    "FreezeObjectEventsExceptOne",
    "FreezeObjectEventsExceptTwo",
    "UnfreezeObjectEvent",
    "UnfreezeObjectEvents",
    "ScriptMovement_StartObjectMovementScript",
    "ScriptMovement_IsObjectMovementFinished",
    "ScriptMovement_IsAllObjectMovementFinished",
    "ScriptMovement_TryAddNewMovement",
    "ScriptMovement_MoveObjects",
    "ScriptMovement_TakeStep",
    "ScriptMovement_UnfreezeObjectEvents",
    "gObjectEventGraphicsInfoPointers",
    "gObjectEventGraphicsInfo_BrendanNormal",
    "gObjectEventGraphicsInfo_Boy1",
    "gObjectEventBaseOam_16x32",
    "gObjectEventPic_BrendanNormalRunning",
    "sPicTable_Boy1",
    "sAnimTable_Standard",
    "sAnim_FaceSouth",
    "sAnim_GoSouth",
    "sStepAnimTables",
    "sFaceDirectionAnimNums",
    "sMoveDirectionAnimNums",
    "sMoveDirectionFastAnimNums",
    "sRunningDirectionAnimNums",
    "sSpinDirectionAnimNums",
    "sJumpSpecialDirectionAnimNums",
    "gFaceDirectionMovementActions",
    "gWalkNormalMovementActions",
    "gWalkFastMovementActions",
    "gWalkInPlaceFastMovementActions",
    "gPlayerRunMovementActions",
    "gJumpMovementActions",
]

OBJECT_EVENT_STRUCT_FIELDS = {
    "template_fields": [
        "localId",
        "graphicsId",
        "kind",
        "x/y",
        "elevation",
        "movementType",
        "movementRangeX/Y",
        "trainerType",
        "trainerRange_berryTreeId",
        "script",
        "flagId",
    ],
    "runtime_state_fields": [
        "active",
        "singleMovementActive",
        "triggerGroundEffectsOnMove",
        "triggerGroundEffectsOnStop",
        "disableCoveringGroundEffects",
        "landingJump",
        "heldMovementActive",
        "heldMovementFinished",
        "frozen",
        "facingDirectionLocked",
        "disableAnim",
        "enableAnim",
        "inanimate",
        "invisible",
        "offScreen",
        "trackedByCamera",
        "isPlayer",
        "hasReflection",
        "inShortGrass",
        "inShallowFlowingWater",
        "inSandPile",
        "inHotSprings",
        "noShadow",
        "fixedPriority",
        "hideReflection",
        "graphicsId",
        "movementType",
        "trainerType",
        "localId/mapNum/mapGroup",
        "currentElevation/previousElevation",
        "initialCoords/currentCoords/previousCoords",
        "facingDirection/movementDirection/range",
        "fieldEffectSpriteId",
        "warpArrowSpriteId",
        "movementActionId",
        "currentMetatileBehavior/previousMetatileBehavior",
        "previousMovementDirection",
        "directionOverwrite",
        "directionSequenceIndex",
        "playerCopyableMovement",
        "spriteId",
    ],
    "graphics_info_fields": [
        "tileTag",
        "paletteTag",
        "reflectionPaletteTag",
        "size",
        "width/height",
        "paletteSlot",
        "shadowSize",
        "inanimate",
        "compressed",
        "tracks",
        "oam",
        "subspriteTables",
        "anims",
        "images",
        "affineAnims",
    ],
}

SPAWN_LIFECYCLE_ORDER = [
    "ResetObjectEvents clears link/player/object state and creates reflection effect sprites",
    "map templates are copied into save-backed objectEventTemplates before spawning",
    "InitObjectEventStateFromTemplate resolves clone templates, checks available slots, flag visibility, and obstacle visibility",
    "template x/y are shifted by MAP_OFFSET into current/previous/initial object-event coords",
    "graphicsId is resolved through SetObjectEventDynamicGraphicsId, including OBJ_EVENT_GFX_VAR_* style ids",
    "movementType, range, trainer metadata, elevation, and initial facing are copied from the template",
    "sMovementTypeHasRange upgrades zero ranges to one tile for ranged wander/copy/sequence types",
    "CopyObjectGraphicsInfoToSpriteTemplate_WithMovementType binds graphics info plus sMovementTypeCallbacks[movementType]",
    "TrySetupObjectEventSprite loads palette/tiles, creates the sprite, assigns map coords plus camera offset, starts face anim when animateable, sets subpriority, then updates visibility",
    "RemoveObjectEvent clears active state, destroys/free palettes/tiles where needed, and zeroes species graphics metadata",
]

OBJECT_EVENT_FRAME_ORDER = [
    "DoGroundEffects_OnSpawn",
    "TryEnableObjectEventAnim",
    "if heldMovementActive -> ObjectEventExecHeldMovementAction",
    "else if not frozen -> run movement type callback while it returns true",
    "DoGroundEffects_OnBeginStep",
    "DoGroundEffects_OnFinishStep",
    "UpdateObjectEventSpriteAnimPause",
    "UpdateObjectEventVisibility",
    "ObjectEventUpdateSubpriority",
]

MOVEMENT_TYPE_GROUPS = [
    {
        "group": "idle_and_facing",
        "source": "sMovementTypeCallbacks + movement_type_func_tables.h",
        "entries": [
            "MOVEMENT_TYPE_NONE -> MovementType_None",
            "MOVEMENT_TYPE_LOOK_AROUND -> MovementType_LookAround",
            "MOVEMENT_TYPE_FACE_* -> MovementType_FaceDirection",
            "MOVEMENT_TYPE_ROTATE_* -> rotate step functions",
        ],
    },
    {
        "group": "wander_and_range",
        "source": "sMovementTypeHasRange + GetCollisionAtCoords",
        "entries": [
            "MOVEMENT_TYPE_WANDER_AROUND(_SLOWER)",
            "MOVEMENT_TYPE_WANDER_UP_AND_DOWN / DOWN_AND_UP",
            "MOVEMENT_TYPE_WANDER_LEFT_AND_RIGHT / RIGHT_AND_LEFT",
            "MOVEMENT_TYPE_WALK_* back-and-forth",
            "MOVEMENT_TYPE_WALK_SEQUENCE_* route tables",
        ],
    },
    {
        "group": "player_copy_and_follow",
        "source": "MovementType_CopyPlayer/CopyPlayerInGrass/FollowPlayer",
        "entries": [
            "copy player direction variants use sPlayerDirectionsForCopy and copyable movement ids",
            "in-grass copy variants feed grass-specific tile callbacks",
            "MOVEMENT_TYPE_FOLLOW_PLAYER variants include shadow, active, and moving steps",
        ],
    },
    {
        "group": "special_visibility_and_in_place",
        "source": "MovementType_Buried/Invisible/WalkInPlace/JogInPlace/RunInPlace",
        "entries": [
            "invisible sets invisible state and keeps per-frame callback alive",
            "in-place movement types loop movement actions without changing cells",
            "berry tree growth and disguise types use custom step tables",
        ],
    },
]

MOVEMENT_ACTION_GROUPS = [
    {
        "group": "face_and_stationary",
        "entries": [
            "MOVEMENT_ACTION_FACE_*",
            "MOVEMENT_ACTION_DELAY_1/2/4/8/16",
            "MOVEMENT_ACTION_WALK_IN_PLACE_*",
            "MOVEMENT_ACTION_LOCK_FACING_DIRECTION/UNLOCK_FACING_DIRECTION",
        ],
    },
    {
        "group": "tile_steps",
        "entries": [
            "MOVEMENT_ACTION_WALK_SLOW_*",
            "MOVEMENT_ACTION_WALK_NORMAL_*",
            "MOVEMENT_ACTION_WALK_FAST_*",
            "MOVEMENT_ACTION_WALK_FASTER_*",
            "MOVEMENT_ACTION_PLAYER_RUN_*",
            "MOVEMENT_ACTION_WALK_SLOW_STAIRS_*",
            "MOVEMENT_ACTION_WALK_*_DIAGONAL_*",
        ],
    },
    {
        "group": "jumps_slides_and_currents",
        "entries": [
            "MOVEMENT_ACTION_JUMP_2_*",
            "MOVEMENT_ACTION_JUMP_*",
            "MOVEMENT_ACTION_JUMP_IN_PLACE_*",
            "MOVEMENT_ACTION_JUMP_SPECIAL_*",
            "MOVEMENT_ACTION_SLIDE_*",
            "MOVEMENT_ACTION_RIDE_WATER_CURRENT_*",
            "MOVEMENT_ACTION_SURF_STILL_*",
            "MOVEMENT_ACTION_SPIN_*",
        ],
    },
    {
        "group": "visibility_affine_reflection_priority",
        "entries": [
            "MOVEMENT_ACTION_SET_INVISIBLE/SET_VISIBLE",
            "MOVEMENT_ACTION_HIDE_REFLECTION/SHOW_REFLECTION",
            "MOVEMENT_ACTION_SET_FIXED_PRIORITY/CLEAR_FIXED_PRIORITY",
            "MOVEMENT_ACTION_INIT_AFFINE_ANIM/CLEAR_AFFINE_ANIM",
            "MOVEMENT_ACTION_WALK_*_AFFINE",
        ],
    },
    {
        "group": "acro_emote_and_field_specials",
        "entries": [
            "MOVEMENT_ACTION_ACRO_* wheelie/hop/jump/move variants",
            "MOVEMENT_ACTION_EMOTE_*",
            "MOVEMENT_ACTION_REVEAL_TRAINER",
            "MOVEMENT_ACTION_ROCK_SMASH_BREAK",
            "MOVEMENT_ACTION_CUT_TREE",
            "MOVEMENT_ACTION_FLY_UP/FLY_DOWN",
            "MOVEMENT_ACTION_EXIT_POKEBALL/ENTER_POKEBALL",
        ],
    },
]

HELD_MOVEMENT_RULES = [
    "ObjectEventSetHeldMovement refuses to replace an overridden movement, remaps actions on sideways stairs, unfreezes the object, sets heldMovementActive, clears heldMovementFinished, and resets sActionFuncId",
    "NPCFollow is notified from held movement so follower copy state can stay in source order",
    "when player field controls are locked and safe follower movement is enabled, player movement actions update playerCopyableMovement through sActionIdToCopyableMovement",
    "ObjectEventExecHeldMovementAction calls gMovementActionFuncs[movementActionId][sActionFuncId] until the action reports finished",
    "ObjectEventClearHeldMovementIfFinished reports 0 while active, 16 when no held movement exists, and clears finished held movement before the next script step",
]

SCRIPT_MOVEMENT_TASK_ORDER = [
    "ScriptMovement_StartObjectMovementScript resolves localId/map to an object event id and starts ScriptMovement_MoveObjects if needed",
    "ScriptMovement_TryAddNewMovement appends one movement script per active object slot unless a matching object is already moving",
    "ScriptMovement_MoveObjects iterates active movement script slots once per task tick",
    "ScriptMovement_TakeStep reads the next movement byte, calls ObjectEventSetHeldMovement, advances script position on successful queueing, and handles MOVEMENT_ACTION_STEP_END",
    "ScriptMovement_IsObjectMovementFinished and ScriptMovement_IsAllObjectMovementFinished gate waitmovement semantics",
    "ScriptMovement_UnfreezeObjectEvents unfreezes objects after active script movement tasks finish",
]

COLLISION_PIPELINE = [
    "GetCollisionAtCoords reads current and next metatile behavior, then resets directionOverwrite",
    "sideways-stairs edge cases can immediately return COLLISION_IMPASSABLE before normal collision",
    "GetVanillaCollision checks movement range, map collision/border/directional impassability, camera movement, elevation mismatch, and object-event occupancy in order",
    "GetSidewaysStairsCollision can convert vanilla collision into diagonal sideways-stair movement and directionOverwrite",
    "object occupancy checks active object events at both currentCoords and previousCoords, excluding self and follower exemptions, then requires compatible elevation",
    "ELEVATION_TRANSITION is compatible with any elevation; ordinary mismatches block collision unless source-specific logic remaps elsewhere",
]

ELEVATION_AND_DEPTH_RULES = [
    "ObjectEventUpdateElevation reads current and previous map-grid elevations from object coords",
    "ELEVATION_MULTI_LEVEL bridge cells keep subsprite priority behavior instead of replacing the stored elevation",
    "sElevationToPriority maps source elevation to GBA OBJ priority; Godot should translate the visible order into layer/z rules, not emulate OAM",
    "SetObjectSubpriorityByElevation derives subpriority from sprite y, centerToCornerVecY, global coord offset, elevation subpriority, and caller subpriority",
    "followers can borrow player elevation during transition elevations so bridge/priority hiding stays visually synced",
]

GROUND_EFFECT_RULES = [
    "ground effect flags are gathered on spawn, begin-step, and finish-step from current/previous metatile behaviors",
    "tall grass, long grass, short grass, hot springs, shallow flowing water, sand pile, puddle, ripple, jump splashes, dust, and seaweed all dispatch through sGroundEffectFuncs",
    "tracks dispatch by ObjectEventGraphicsInfo.tracks and include foot, bike tire, slither, spot, and bug patterns",
    "water and ice reflections call SetUpReflection through ground effects; reflection state is held on objEvent.hasReflection and hideReflection",
    "shadows are gated by CurrentMapHasShadows, weather noShadows, object flags, and current metatile behavior",
    "source palette patching for reflections is import/presentation metadata only; Godot should use native mirrored sprites/materials while preserving visible timing",
]

FREEZE_LOCK_VISIBILITY_RULES = [
    "FreezeObjectEvent refuses already held/frozen objects, then pauses sprite anim and affine anim while saving prior pause state",
    "FreezeObjectEvents skips the player object event; except-one/two variants are used for selected-object and trainer locks",
    "UnfreezeObjectEvent restores saved anim/affine pause state",
    "UpdateObjectEventVisibility combines offscreen and invisible/object state before sprite visibility is applied",
    "Movement actions can set invisible/visible, disable/restore animation, hide/show reflection, and fixed priority independently of map template visibility",
]

UNSUPPORTED = [
    {
        "code": "object_event_runtime_struct_pending",
        "status": "unsupported",
        "source": "include/global.fieldmap.h:struct ObjectEvent",
        "detail": "Godot MapRuntime stores dictionaries for current/template positions and visibility, but does not yet own a source-shaped object-event runtime struct with held movement, elevation, ground-effect, reflection, freeze, and sprite callback state.",
    },
    {
        "code": "object_spawn_despawn_lifecycle_first_pass",
        "status": "first_pass",
        "source": "src/event_object_movement.c:InitObjectEventStateFromTemplate/TrySpawnObjectEventTemplate/RemoveObjectEvent",
        "detail": "Godot indexes generated map object events and applies first-pass add/remove/show/hide effects, but camera-range spawn/despawn, clone templates, dynamic local ids, and source palette/tile lifecycle are not runtime-equivalent.",
    },
    {
        "code": "camera_spawn_despawn_pending",
        "status": "unsupported",
        "source": "src/event_object_movement.c:TrySpawnObjectEvents/UpdateObjectEventsForCameraUpdate",
        "detail": "Source object events are spawned/despawned around the camera and backup-map window; Godot currently keeps first-slice objects indexed for the loaded map.",
    },
    {
        "code": "movement_type_callbacks_pending",
        "status": "unsupported",
        "source": "src/event_object_movement.c:sMovementTypeCallbacks",
        "detail": "Movement type callbacks for wandering, facing cycles, sequences, copy-player, follower, berry/disguise, invisible, and in-place behavior are traced but not executed per frame.",
    },
    {
        "code": "held_movement_action_queue_pending",
        "status": "unsupported",
        "source": "src/event_object_movement.c:ObjectEventSetHeldMovement/ObjectEventExecHeldMovementAction",
        "detail": "Godot ScriptVM movement effects are still fast-forwarded into net deltas instead of queued as source held movement actions with per-frame completion.",
    },
    {
        "code": "movement_action_timing_pending",
        "status": "unsupported",
        "source": "src/data/object_events/movement_action_func_tables.h + src/event_object_movement.c:MovementAction_*",
        "detail": "Walk, run, jump, slide, delay, Acro, surf-still, spin, affine, visibility, emote, and field special action timings are preserved as trace metadata only.",
    },
    {
        "code": "script_movement_async_pending",
        "status": "unsupported",
        "source": "src/script_movement.c:ScriptMovement_MoveObjects/ScriptMovement_TakeStep",
        "detail": "`applymovement` and `waitmovement` are not yet backed by live object movement tasks; the current result remains a synchronous first-pass summary.",
    },
    {
        "code": "source_collision_pipeline_pending",
        "status": "unsupported",
        "source": "src/event_object_movement.c:GetCollisionAtCoords",
        "detail": "Godot object/player movement still lacks source range checks, directionally impassable metatiles, elevation compatibility, previous-coordinate occupancy, follower exemptions, camera gates, and sideways-stair direction overwrite.",
    },
    {
        "code": "elevation_subpriority_depth_pending",
        "status": "unsupported",
        "source": "src/event_object_movement.c:sElevationToPriority/sElevationToSubpriority",
        "detail": "Godot z_index currently follows a simple grid-y rule and does not reproduce bridge, elevation, subsprite, long-grass, and y-derived subpriority ordering.",
    },
    {
        "code": "ground_effect_tracks_pending",
        "status": "unsupported",
        "source": "src/event_object_movement.c:sGroundEffectFuncs/sGroundEffectTracksFuncs",
        "detail": "Grass, water, sand, track, puddle, dust, hot-spring, seaweed, and jump landing field effects are not yet spawned from object-event movement.",
    },
    {
        "code": "shadows_reflections_pending",
        "status": "unsupported",
        "source": "src/event_object_movement.c:GetGroundEffectFlags_Reflection + src/field_effect_helpers.c:SetUpReflection/SetUpShadow",
        "detail": "ObjectEventPlaceholder draws a simple oval shadow, but source shadow gating, reflection sprites, bridge/water/ice variants, and hide/show reflection movement actions are pending.",
    },
    {
        "code": "object_freeze_lock_pending",
        "status": "unsupported",
        "source": "src/event_object_lock.c + src/event_object_movement.c:FreezeObjectEvent",
        "detail": "Script lock/release currently records effects without fully freezing/unfreezing object event callbacks and restoring sprite animation/affine pause state.",
    },
    {
        "code": "object_graphics_full_import_pending",
        "status": "first_pass",
        "source": "src/data/object_events/object_event_graphics_info_pointers.h",
        "detail": "Only the first 11 source-backed object graphics needed by Littleroot/debug/player coverage are imported; full object graphics, shadows, tracks, reflections, affine metadata, and follower/dynamic graphics remain future work.",
    },
    {
        "code": "dynamic_graphics_and_followers_pending",
        "status": "unsupported",
        "source": "src/event_object_movement.c:SetObjectEventDynamicGraphicsId + src/follower_npc.c",
        "detail": "OBJ_EVENT_GFX_VAR_* has a first-pass rival path, but the full dynamic graphics/follower Pokemon object-event system is not runtime-equivalent.",
    },
    {
        "code": "debug_object_movement_inspector_pending",
        "status": "unsupported",
        "source": "Godot-only debug lane",
        "detail": "The requested overworld debug toolkit should later expose object-event freeze/unfreeze and active movement-task inspection without mutating source-equivalent gameplay paths.",
    },
    {
        "code": "palette_affine_effects_godot_native",
        "status": "metadata_only",
        "source": "Project porting constraint",
        "detail": "Palette changes, reflection palette swaps, scaling, rotation, and affine-like effects must be implemented with Godot-native textures/materials/shaders/animation while preserving source timing and visible result, not by recreating GBA palette-bank/OAM limits.",
    },
    {
        "code": "audio_playback_pending",
        "status": "metadata_only",
        "source": "object movement, field effects, door/object cues, and shadow/reflection-related source calls",
        "detail": "Sound symbols and timing intent remain report metadata; real audio playback is intentionally out of scope for now.",
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
            "id": "object_event_data_model",
            "source_entry": "include/global.fieldmap.h:struct ObjectEventTemplate/ObjectEvent/ObjectEventGraphicsInfo",
            "status": "metadata_only",
            "critical_order": [
                "template data seeds local id, graphics id, map coords, elevation, movement type/range, trainer metadata, script pointer, and flag id",
                "runtime ObjectEvent owns movement state, current/previous coords, elevation, facing/movement directions, ground effect flags, reflection/shadow bits, and sprite id",
                "ObjectEventGraphicsInfo owns sheet/palette/reflection palette, frame size, OAM, subsprites, anim tables, affine anims, inanimate flag, shadow size, and track type",
            ],
            "godot_current": [
                "MapRuntime stores object events as dictionaries with current/template position, movement type, facing, runtime_hidden, active, source local-id aliases, and flag status.",
            ],
            "gaps": [
                "No source-shaped object-event runtime state object exists yet.",
            ],
        },
        {
            "id": "object_event_graphics_asset_model",
            "source_entry": "src/data/object_events/object_event_graphics*.h/object_event_pic_tables.h/object_event_anims.h",
            "status": "first_pass",
            "critical_order": [
                "graphics info points to image frame tables and animation tables",
                "palette index 0 is transparent at import time for Godot textures",
                "shadowSize, tracks, inanimate, reflectionPaletteTag, affineAnims, and subspriteTables remain required metadata for source-equivalent presentation",
            ],
            "godot_current": [
                "export_object_event_sprites.py imports 11 first-slice graphics records and records unsupported animation-task gaps.",
            ],
            "gaps": [
                "Full object graphics, follower graphics, tracks, shadow/reflection metadata, and affine metadata are not fully imported.",
            ],
        },
        {
            "id": "spawn_template_lifecycle",
            "source_entry": "src/event_object_movement.c:InitObjectEventStateFromTemplate/TrySetupObjectEventSprite/TrySpawnObjectEventTemplate/RemoveObjectEvent",
            "status": "first_pass",
            "critical_order": SPAWN_LIFECYCLE_ORDER,
            "godot_current": [
                "MapRuntime indexes generated object_events for the loaded map and rebuilds occupancy when object effects or saves mutate state.",
            ],
            "gaps": [
                "Camera-range spawn/despawn, template clone behavior, dynamic local ids, and real sprite lifecycle are pending.",
            ],
        },
        {
            "id": "camera_spawn_despawn",
            "source_entry": "src/event_object_movement.c:TrySpawnObjectEvents/UpdateObjectEventsForCameraUpdate",
            "status": "metadata_only",
            "critical_order": [
                "source spawns object events based on camera position and current map window",
                "object events outside the active camera/backup-map window can be removed",
                "obstacle template flags are touched for special tree/rock visibility edge cases",
            ],
            "godot_current": [
                "Loaded-map events stay resident for first-slice maps.",
            ],
            "gaps": [
                "Camera-window object lifecycle is not ported.",
            ],
        },
        {
            "id": "per_frame_update_order",
            "source_entry": "src/event_object_movement.c:UpdateObjectEventCurrentMovement",
            "status": "metadata_only",
            "critical_order": OBJECT_EVENT_FRAME_ORDER,
            "godot_current": [
                "ObjectEventPlaceholder is static unless MapRuntime has already fast-forwarded script effects.",
            ],
            "gaps": [
                "No object-event per-frame callback owner exists yet.",
            ],
        },
        {
            "id": "movement_type_callback_table",
            "source_entry": "src/event_object_movement.c:sMovementTypeCallbacks + src/data/object_events/movement_type_func_tables.h",
            "status": "metadata_only",
            "critical_order": [
                "movement type selects a sprite callback at spawn or SetTrainerMovementType time",
                "movement type callbacks run only when the object is not frozen and no held movement is active",
                "callback step tables loop while the current step returns true, which can consume multiple internal steps in one frame",
            ],
            "godot_current": [
                "Generated movement_type strings are preserved on object-event dictionaries.",
            ],
            "gaps": [
                "No movement type callback table is executed in Godot.",
            ],
        },
        {
            "id": "held_movement_action_queue",
            "source_entry": "src/event_object_movement.c:ObjectEventSetHeldMovement/ObjectEventExecHeldMovementAction",
            "status": "metadata_only",
            "critical_order": HELD_MOVEMENT_RULES,
            "godot_current": [
                "ScriptVM movement labels export net deltas and MapRuntime applies them synchronously.",
            ],
            "gaps": [
                "Held movement action ids, sActionFuncId, completion, and waitmovement are pending.",
            ],
        },
        {
            "id": "movement_action_timing_and_animation",
            "source_entry": "src/data/object_events/movement_action_func_tables.h + src/event_object_movement.c:MovementAction_*",
            "status": "metadata_only",
            "critical_order": [
                "movement actions are arrays of step functions indexed by sprite->sActionFuncId",
                "step 0 initializes direction, coords, sprite data, animation id, jump/ground-effect flags, or visibility/effect state",
                "step 1 usually advances the sprite until the movement/delay/jump is complete, then reports finished",
                "source action families are distinct for normal/fast/faster/run, jumps, slides, currents, stairs, diagonal movement, surf stillness, spin, Acro, affine, visibility, reflection, and field specials",
            ],
            "godot_current": [
                "PlayerController implements only source-timed normal player walk and turn-in-place through generated player sprite metadata.",
            ],
            "gaps": [
                "NPC/object movement actions and most player movement action families are pending.",
            ],
        },
        {
            "id": "script_movement_task_bridge",
            "source_entry": "src/script_movement.c:ScriptMovement_StartObjectMovementScript/ScriptMovement_MoveObjects/ScriptMovement_TakeStep",
            "status": "first_pass",
            "critical_order": SCRIPT_MOVEMENT_TASK_ORDER,
            "godot_current": [
                "ScriptVM exports movement effect records, and MapRuntime can apply current first-pass net deltas to objects or player position.",
            ],
            "gaps": [
                "Async task scheduling, held movement queueing, and waitmovement completion are pending.",
            ],
        },
        {
            "id": "collision_and_occupancy_pipeline",
            "source_entry": "src/event_object_movement.c:GetCollisionAtCoords/GetVanillaCollision/GetObjectObjectCollidesWith",
            "status": "first_pass",
            "critical_order": COLLISION_PIPELINE,
            "godot_current": [
                "MapRuntime.can_enter_cell checks bounds, generated collision == 0, and visible object occupancy.",
            ],
            "gaps": [
                "Source range, elevation, directional impassability, previous-coordinate occupancy, follower exceptions, camera gates, and sideways-stair direction overwrite are pending.",
            ],
        },
        {
            "id": "elevation_priority_subpriority",
            "source_entry": "src/event_object_movement.c:ObjectEventUpdateElevation/SetObjectSubpriorityByElevation",
            "status": "metadata_only",
            "critical_order": ELEVATION_AND_DEPTH_RULES,
            "godot_current": [
                "ObjectEventPlaceholder sets z_index to grid_position.y.",
            ],
            "gaps": [
                "Source-equivalent layer/elevation/subpriority interleaving is pending.",
            ],
        },
        {
            "id": "ground_effects_tracks_shadows_reflections",
            "source_entry": "src/event_object_movement.c:sGroundEffectFuncs/sGroundEffectTracksFuncs + src/field_effect_helpers.c",
            "status": "metadata_only",
            "critical_order": GROUND_EFFECT_RULES,
            "godot_current": [
                "ObjectEventPlaceholder draws a simple shadow under imported sprites.",
            ],
            "gaps": [
                "Ground effect sprites, source shadow gating, and reflection sprites are pending.",
            ],
        },
        {
            "id": "freeze_lock_visibility",
            "source_entry": "src/event_object_lock.c + src/event_object_movement.c:FreezeObjectEvent/UpdateObjectEventVisibility",
            "status": "metadata_only",
            "critical_order": FREEZE_LOCK_VISIBILITY_RULES,
            "godot_current": [
                "ScriptVM records lock/release effects and MapRuntime can hide/show object events.",
            ],
            "gaps": [
                "Full freeze/unfreeze callback semantics and sprite animation-pause restore are pending.",
            ],
        },
        {
            "id": "godot_current_object_event_mapping",
            "source_entry": "Godot runtime owner map",
            "status": "first_pass",
            "critical_order": [
                "MapRuntime owns current/template object event dictionaries, occupancy, object effects, first-pass movement-effect application, and save restore",
                "ObjectEventSpawner creates one ObjectEventPlaceholder per visible event",
                "ObjectEventPlaceholder resolves generated sprite metadata, static facing frame, hFlip, tile-center anchor, and simple z_index",
                "ScriptVM owns generated movement/object effect summaries until a real object-event task scheduler exists",
                "Future debug controls should inspect this runtime without becoming gameplay behavior",
            ],
            "godot_current": [
                "This is useful first-pass infrastructure but not source-equivalent object-event runtime.",
            ],
            "gaps": [
                "A real object-event runtime should be added before treating NPC movement, waitmovement, freeze, shadow, reflection, and depth as complete.",
            ],
        },
    ]


def manifest_entry_for(exported, output_path):
    stats = exported["stats"]
    return {
        "category": "overworld_object_event_movement_trace",
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
        "object_event_struct_fields": OBJECT_EVENT_STRUCT_FIELDS,
        "spawn_lifecycle_order": SPAWN_LIFECYCLE_ORDER,
        "object_event_frame_order": OBJECT_EVENT_FRAME_ORDER,
        "movement_type_groups": MOVEMENT_TYPE_GROUPS,
        "movement_action_groups": MOVEMENT_ACTION_GROUPS,
        "held_movement_rules": HELD_MOVEMENT_RULES,
        "script_movement_task_order": SCRIPT_MOVEMENT_TASK_ORDER,
        "collision_pipeline": COLLISION_PIPELINE,
        "elevation_and_depth_rules": ELEVATION_AND_DEPTH_RULES,
        "ground_effect_rules": GROUND_EFFECT_RULES,
        "freeze_lock_visibility_rules": FREEZE_LOCK_VISIBILITY_RULES,
        "visual_effect_policy": {
            "palette_and_affine": "Use Godot-native textures, materials, shaders, animation, and resources for palette, tint, scale, rotation, affine, and reflection-like presentation while preserving source timing and visible result where practical.",
            "gba_runtime_limits": "Do not recreate GBA palette-bank, VRAM, OAM, or compressed sheet limits at runtime unless a gameplay rule explicitly depends on them.",
            "audio": "Sound/music/fanfare symbols stay metadata_only/unsupported until audio scope is reopened.",
        },
        "source_flows": flow_rows,
        "godot_trace_owners": {
            "runtime": [
                "scripts/autoload/map_runtime.gd",
                "scripts/autoload/script_vm.gd",
                "scripts/autoload/event_manager.gd",
            ],
            "presentation": [
                "scripts/overworld/object_event_spawner.gd",
                "scripts/overworld/object_event_placeholder.gd",
                "scripts/overworld/player_controller.gd",
            ],
            "generated_assets": [
                "data/generated/object_events/object_event_sprites.json",
                "tools/importer/export_object_event_sprites.py",
            ],
            "debug_lane": [
                "wiki/overworld-parity-todo.md:Godot-only overworld debug toolkit",
            ],
            "tests": [
                "tools/godot_smoke/map_runtime_smoke.gd",
                "tools/godot_smoke/object_event_sprite_smoke.gd",
                "tools/godot_smoke/player_turn_input_smoke.tscn",
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

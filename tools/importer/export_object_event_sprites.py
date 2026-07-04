#!/usr/bin/env python3
"""Export first-pass object event sprite metadata and PNG sheets."""

import argparse
import copy
import json
import shutil
import struct
import sys
from pathlib import Path

from export_map import to_project_path, write_json, write_manifest
from source_probe import load_config


STANDARD_STATIC_FRAMES = {"down": 0, "up": 1, "left": 2, "right": 2}
STANDARD_STATIC_FRAME_FLIPS = {"right": {"h": True}}
STANDARD_ANIMATION_TABLE = {
    "source_symbol": "sAnimTable_Standard",
    "source_animation_ids": {
        "face_down": "ANIM_STD_FACE_SOUTH",
        "face_up": "ANIM_STD_FACE_NORTH",
        "face_left": "ANIM_STD_FACE_WEST",
        "face_right": "ANIM_STD_FACE_EAST",
        "walk_down": "ANIM_STD_GO_SOUTH",
        "walk_up": "ANIM_STD_GO_NORTH",
        "walk_left": "ANIM_STD_GO_WEST",
        "walk_right": "ANIM_STD_GO_EAST",
    },
    "face": {
        "down": [{"frame": 0, "duration_frames": 16}],
        "up": [{"frame": 1, "duration_frames": 16}],
        "left": [{"frame": 2, "duration_frames": 16}],
        "right": [{"frame": 2, "duration_frames": 16, "h_flip": True}],
    },
    "walk": {
        "down": [
            {"frame": 3, "duration_frames": 8},
            {"frame": 0, "duration_frames": 8},
            {"frame": 4, "duration_frames": 8},
            {"frame": 0, "duration_frames": 8},
        ],
        "up": [
            {"frame": 5, "duration_frames": 8},
            {"frame": 1, "duration_frames": 8},
            {"frame": 6, "duration_frames": 8},
            {"frame": 1, "duration_frames": 8},
        ],
        "left": [
            {"frame": 7, "duration_frames": 8},
            {"frame": 2, "duration_frames": 8},
            {"frame": 8, "duration_frames": 8},
            {"frame": 2, "duration_frames": 8},
        ],
        "right": [
            {"frame": 7, "duration_frames": 8, "h_flip": True},
            {"frame": 2, "duration_frames": 8, "h_flip": True},
            {"frame": 8, "duration_frames": 8, "h_flip": True},
            {"frame": 2, "duration_frames": 8, "h_flip": True},
        ],
    },
}
INANIMATE_ANIMATION_TABLE = {
    "source_symbol": "sAnimTable_Inanimate",
    "source_animation_ids": {"stay_still": "ANIM_STAY_STILL"},
    "stay_still": [
        {"frame": 0, "duration_frames": 8},
        {"frame": 0, "duration_frames": 8},
        {"frame": 0, "duration_frames": 8},
        {"frame": 0, "duration_frames": 8},
    ],
}
STATIC_RENDER_UNSUPPORTED = [
    {
        "code": "object_event_walk_animation_not_runtime_driven",
        "detail": "Facing frames and source animation metadata are exported; this runtime slice still renders object events as static facing frames until object-event animation tasks are ported.",
    }
]
RIVAL_RENDER_UNSUPPORTED = STATIC_RENDER_UNSUPPORTED + [
    {
        "code": "rival_running_spin_animation_not_runtime_driven",
        "detail": "The imported sheet preserves the source walking+running frame data and Brendan/May animation table metadata; this runtime slice does not yet drive run, fast-walk, or spin object-event animation commands.",
    }
]
PLAYER_RUNTIME_SUPPORTED = [
    {
        "code": "player_avatar_normal_walk_source_timed",
        "detail": "PlayerController drives normal on-foot walking from sAnimTable_BrendanMayNormal walk commands with SetStepAnimHandleAlternation gait phase handling while the 16-frame tile step follows SetSpriteDataForNormalStep/NpcTakeStep MOVE_SPEED_NORMAL timing.",
    },
    {
        "code": "player_avatar_turn_in_place_source_timed",
        "detail": "PlayerController drives on-foot turn-in-place through the source WalkInPlaceFast path: sAnimTable_BrendanMayNormal fast-walk commands, SetStepAnimHandleAlternation gait phase handling, and an 8-frame duration.",
    }
]
PLAYER_RENDER_UNSUPPORTED = [
    {
        "code": "player_avatar_run_continuous_fast_walk_spin_animation_not_runtime_driven",
        "detail": "The Brendan/May running, continuous fast-walk movement, and spin animation metadata is exported but those non-turn player movement states are not yet runtime-driven.",
    },
    {
        "code": "player_avatar_non_normal_state_graphics_not_runtime_driven",
        "detail": "Surfing, biking, underwater, acro-bike, field-effect, and other player avatar graphics states are outside the current normal on-foot runtime slice.",
    }
]


def _brendan_may_animation_table():
    table = copy.deepcopy(STANDARD_ANIMATION_TABLE)
    table["source_symbol"] = "sAnimTable_BrendanMayNormal"
    table["source_animation_ids"].update({
        "fast_walk_down": "ANIM_STD_GO_FAST_SOUTH",
        "fast_walk_up": "ANIM_STD_GO_FAST_NORTH",
        "fast_walk_left": "ANIM_STD_GO_FAST_WEST",
        "fast_walk_right": "ANIM_STD_GO_FAST_EAST",
        "run_down": "ANIM_RUN_SOUTH",
        "run_up": "ANIM_RUN_NORTH",
        "run_left": "ANIM_RUN_WEST",
        "run_right": "ANIM_RUN_EAST",
        "spin_down": "ANIM_SPIN_SOUTH",
        "spin_up": "ANIM_SPIN_NORTH",
        "spin_left": "ANIM_SPIN_WEST",
        "spin_right": "ANIM_SPIN_EAST",
    })
    table["fast_walk"] = {
        "down": [
            {"frame": 3, "duration_frames": 4},
            {"frame": 0, "duration_frames": 4},
            {"frame": 4, "duration_frames": 4},
            {"frame": 0, "duration_frames": 4},
        ],
        "up": [
            {"frame": 5, "duration_frames": 4},
            {"frame": 1, "duration_frames": 4},
            {"frame": 6, "duration_frames": 4},
            {"frame": 1, "duration_frames": 4},
        ],
        "left": [
            {"frame": 7, "duration_frames": 4},
            {"frame": 2, "duration_frames": 4},
            {"frame": 8, "duration_frames": 4},
            {"frame": 2, "duration_frames": 4},
        ],
        "right": [
            {"frame": 7, "duration_frames": 4, "h_flip": True},
            {"frame": 2, "duration_frames": 4, "h_flip": True},
            {"frame": 8, "duration_frames": 4, "h_flip": True},
            {"frame": 2, "duration_frames": 4, "h_flip": True},
        ],
    }
    table["run"] = {
        "down": [
            {"frame": 12, "duration_frames": 5},
            {"frame": 9, "duration_frames": 3},
            {"frame": 13, "duration_frames": 5},
            {"frame": 9, "duration_frames": 3},
        ],
        "up": [
            {"frame": 14, "duration_frames": 5},
            {"frame": 10, "duration_frames": 3},
            {"frame": 15, "duration_frames": 5},
            {"frame": 10, "duration_frames": 3},
        ],
        "left": [
            {"frame": 16, "duration_frames": 5},
            {"frame": 11, "duration_frames": 3},
            {"frame": 17, "duration_frames": 5},
            {"frame": 11, "duration_frames": 3},
        ],
        "right": [
            {"frame": 16, "duration_frames": 5, "h_flip": True},
            {"frame": 11, "duration_frames": 3, "h_flip": True},
            {"frame": 17, "duration_frames": 5, "h_flip": True},
            {"frame": 11, "duration_frames": 3, "h_flip": True},
        ],
    }
    table["spin"] = {
        "down": [
            {"frame": 0, "duration_frames": 2},
            {"frame": 2, "duration_frames": 2, "h_flip": True},
            {"frame": 1, "duration_frames": 2},
            {"frame": 2, "duration_frames": 2},
        ],
        "up": [
            {"frame": 1, "duration_frames": 2},
            {"frame": 2, "duration_frames": 2},
            {"frame": 0, "duration_frames": 2},
            {"frame": 2, "duration_frames": 2, "h_flip": True},
        ],
        "left": [
            {"frame": 2, "duration_frames": 2, "h_flip": True},
            {"frame": 1, "duration_frames": 2},
            {"frame": 2, "duration_frames": 2},
            {"frame": 0, "duration_frames": 2},
        ],
        "right": [
            {"frame": 2, "duration_frames": 2},
            {"frame": 0, "duration_frames": 2},
            {"frame": 2, "duration_frames": 2, "h_flip": True},
            {"frame": 1, "duration_frames": 2},
        ],
    }
    return table


BRENDAN_MAY_ANIMATION_TABLE = _brendan_may_animation_table()


def _standard_sprite(
    source_symbol,
    source_pic_table,
    source_image,
    asset_name,
    source_graphics_info,
    palette_tag,
    source_constant_value,
):
    return {
        "source_symbol": source_symbol,
        "source_pic_table": source_pic_table,
        "source_graphics_info": source_graphics_info,
        "source_constant_value": source_constant_value,
        "source_image": Path(source_image),
        "asset_name": asset_name,
        "frame_size": {"w": 16, "h": 32},
        "palette_tag": palette_tag,
        "shadow_size": "SHADOW_SIZE_M",
        "inanimate": False,
        "tracks": "TRACKS_FOOT",
        "oam": "&gObjectEventBaseOam_16x32",
        "subsprite_tables": "sOamTables_16x32",
        "static_frames": STANDARD_STATIC_FRAMES,
        "static_frame_flips": STANDARD_STATIC_FRAME_FLIPS,
        "animation_table": STANDARD_ANIMATION_TABLE,
        "source_trace": [
            "src/data/object_events/object_event_graphics.h:{}".format(source_symbol),
            "src/data/object_events/object_event_graphics_info.h:{}".format(source_graphics_info),
            "src/data/object_events/object_event_pic_tables.h:{}".format(source_pic_table),
            "src/data/object_events/object_event_anims.h:sAnimTable_Standard",
            "src/data/object_events/object_event_anims.h:sAnim_FaceSouth/sAnim_FaceNorth/sAnim_FaceWest/sAnim_FaceEast",
            "src/data/object_events/object_event_anims.h:sAnim_GoSouth/sAnim_GoNorth/sAnim_GoWest/sAnim_GoEast",
            "src/event_object_movement.c:sFaceDirectionAnimNums/sMoveDirectionAnimNums",
        ],
        "unsupported": STATIC_RENDER_UNSUPPORTED,
    }


def _inanimate_sprite(
    source_symbol,
    source_pic_table,
    source_image,
    asset_name,
    source_graphics_info,
    frame_size,
    palette_tag,
    source_constant_value,
):
    return {
        "source_symbol": source_symbol,
        "source_pic_table": source_pic_table,
        "source_graphics_info": source_graphics_info,
        "source_constant_value": source_constant_value,
        "source_image": Path(source_image),
        "asset_name": asset_name,
        "frame_size": frame_size,
        "palette_tag": palette_tag,
        "shadow_size": "SHADOW_SIZE_M",
        "inanimate": True,
        "tracks": "TRACKS_NONE",
        "oam": "&gObjectEventBaseOam_32x32",
        "subsprite_tables": "sOamTables_48x48",
        "static_frames": {"down": 0, "up": 0, "left": 0, "right": 0},
        "static_frame_flips": {},
        "animation_table": INANIMATE_ANIMATION_TABLE,
        "source_trace": [
            "src/data/object_events/object_event_graphics.h:{}".format(source_symbol),
            "src/data/object_events/object_event_graphics_info.h:{}".format(source_graphics_info),
            "src/data/object_events/object_event_pic_tables.h:{}".format(source_pic_table),
            "src/data/object_events/object_event_anims.h:sAnim_StayStill/sAnimTable_Inanimate",
        ],
        "unsupported": STATIC_RENDER_UNSUPPORTED,
    }


def _rival_sprite(
    graphics_id,
    source_symbol,
    source_pic_table,
    source_images,
    asset_name,
    source_graphics_info,
    palette_tag,
    source_constant_value,
):
    return {
        "source_symbol": source_symbol,
        "source_pic_table": source_pic_table,
        "source_graphics_info": source_graphics_info,
        "source_constant_value": source_constant_value,
        "source_images": [Path(source_image) for source_image in source_images],
        "asset_name": asset_name,
        "frame_size": {"w": 16, "h": 32},
        "palette_tag": palette_tag,
        "reflection_palette_tag": "OBJ_EVENT_PAL_TAG_BRIDGE_REFLECTION",
        "shadow_size": "SHADOW_SIZE_M",
        "inanimate": False,
        "tracks": "TRACKS_FOOT",
        "oam": "&gObjectEventBaseOam_16x32",
        "subsprite_tables": "sOamTables_16x32",
        "static_frames": STANDARD_STATIC_FRAMES,
        "static_frame_flips": STANDARD_STATIC_FRAME_FLIPS,
        "animation_table": BRENDAN_MAY_ANIMATION_TABLE,
        "source_trace": [
            "include/constants/event_objects.h:{}".format(graphics_id),
            "src/data/object_events/object_event_graphics.h:{}".format(source_symbol),
            "src/data/object_events/object_event_graphics_info.h:{}".format(source_graphics_info),
            "src/data/object_events/object_event_pic_tables.h:{}".format(source_pic_table),
            "src/data/object_events/object_event_anims.h:sAnimTable_BrendanMayNormal",
            "src/data/object_events/object_event_anims.h:sAnim_RunSouth/sAnim_RunNorth/sAnim_RunWest/sAnim_RunEast",
            "src/data/object_events/object_event_anims.h:sAnim_SpinSouth/sAnim_SpinNorth/sAnim_SpinWest/sAnim_SpinEast",
            "src/event_object_movement.c:sFaceDirectionAnimNums/sMoveDirectionAnimNums",
        ],
        "unsupported": RIVAL_RENDER_UNSUPPORTED,
    }


def _player_normal_sprite(
    graphics_id,
    source_symbol,
    source_pic_table,
    source_images,
    asset_name,
    source_graphics_info,
    palette_tag,
    source_constant_value,
):
    record = _rival_sprite(
        graphics_id,
        source_symbol,
        source_pic_table,
        source_images,
        asset_name,
        source_graphics_info,
        palette_tag,
        source_constant_value,
    )
    record["source_trace"] = [
        "include/constants/event_objects.h:{}".format(graphics_id),
        "include/constants/event_objects.h:PLAYER_AVATAR_GFX_MALE_NORMAL/PLAYER_AVATAR_GFX_FEMALE_NORMAL",
        "src/data/object_events/object_event_graphics.h:{}".format(source_symbol),
        "src/data/object_events/object_event_graphics_info.h:{}".format(source_graphics_info),
        "src/data/object_events/object_event_pic_tables.h:{}".format(source_pic_table),
        "src/data/object_events/object_event_anims.h:sAnimTable_BrendanMayNormal",
        "src/field_player_avatar.c:PlayerWalkNormal",
        "src/field_player_avatar.c:PlayerTurnInPlace",
        "src/event_object_movement.c:GetWalkNormalMovementAction",
        "src/event_object_movement.c:GetWalkInPlaceFastMovementAction",
        "src/event_object_movement.c:MovementAction_WalkNormal*_Step0/Step1",
        "src/event_object_movement.c:MovementAction_WalkInPlaceFast*_Step0/Step1",
        "src/event_object_movement.c:SetStepAnimHandleAlternation",
        "src/event_object_movement.c:SetSpriteDataForNormalStep/NpcTakeStep",
        "src/event_object_movement.c:sFaceDirectionAnimNums/sMoveDirectionAnimNums",
    ]
    record["runtime_supported"] = PLAYER_RUNTIME_SUPPORTED
    record["unsupported"] = PLAYER_RENDER_UNSUPPORTED
    return record


SPRITES = {
    "OBJ_EVENT_GFX_BRENDAN_NORMAL": _player_normal_sprite(
        "OBJ_EVENT_GFX_BRENDAN_NORMAL",
        "gObjectEventPic_BrendanNormalRunning",
        "sPicTable_BrendanNormal",
        [
            "graphics/object_events/pics/people/brendan/walking.png",
            "graphics/object_events/pics/people/brendan/running.png",
        ],
        "brendan_normal.png",
        "gObjectEventGraphicsInfo_BrendanNormal",
        "OBJ_EVENT_PAL_TAG_BRENDAN",
        0,
    ),
    "OBJ_EVENT_GFX_TWIN": _standard_sprite(
        "gObjectEventPic_Twin",
        "sPicTable_Twin",
        "graphics/object_events/pics/people/twin.png",
        "twin.png",
        "gObjectEventGraphicsInfo_Twin",
        "OBJ_EVENT_PAL_TAG_NPC_2",
        6,
    ),
    "OBJ_EVENT_GFX_BOY_1": _standard_sprite(
        "gObjectEventPic_Boy1",
        "sPicTable_Boy1",
        "graphics/object_events/pics/people/boy_1.png",
        "boy_1.png",
        "gObjectEventGraphicsInfo_Boy1",
        "OBJ_EVENT_PAL_TAG_NPC_3",
        7,
    ),
    "OBJ_EVENT_GFX_BOY_2": _standard_sprite(
        "gObjectEventPic_Boy2",
        "sPicTable_Boy2",
        "graphics/object_events/pics/people/boy_2.png",
        "boy_2.png",
        "gObjectEventGraphicsInfo_Boy2",
        "OBJ_EVENT_PAL_TAG_NPC_1",
        9,
    ),
    "OBJ_EVENT_GFX_FAT_MAN": _standard_sprite(
        "gObjectEventPic_FatMan",
        "sPicTable_FatMan",
        "graphics/object_events/pics/people/fat_man.png",
        "fat_man.png",
        "gObjectEventGraphicsInfo_FatMan",
        "OBJ_EVENT_PAL_TAG_NPC_1",
        17,
    ),
    "OBJ_EVENT_GFX_PROF_BIRCH": _standard_sprite(
        "gObjectEventPic_ProfBirch",
        "sPicTable_ProfBirch",
        "graphics/object_events/pics/people/prof_birch.png",
        "prof_birch.png",
        "gObjectEventGraphicsInfo_ProfBirch",
        "OBJ_EVENT_PAL_TAG_NPC_3",
        64,
    ),
    "OBJ_EVENT_GFX_TRUCK": _inanimate_sprite(
        "gObjectEventPic_Truck",
        "sPicTable_Truck",
        "graphics/object_events/pics/misc/truck.png",
        "truck.png",
        "gObjectEventGraphicsInfo_Truck",
        {"w": 48, "h": 48},
        "OBJ_EVENT_PAL_TAG_TRUCK",
        94,
    ),
    "OBJ_EVENT_GFX_MAY_NORMAL": _player_normal_sprite(
        "OBJ_EVENT_GFX_MAY_NORMAL",
        "gObjectEventPic_MayNormalRunning",
        "sPicTable_MayNormal",
        [
            "graphics/object_events/pics/people/may/walking.png",
            "graphics/object_events/pics/people/may/running.png",
        ],
        "may_normal.png",
        "gObjectEventGraphicsInfo_MayNormal",
        "OBJ_EVENT_PAL_TAG_MAY",
        89,
    ),
    "OBJ_EVENT_GFX_RIVAL_BRENDAN_NORMAL": _rival_sprite(
        "OBJ_EVENT_GFX_RIVAL_BRENDAN_NORMAL",
        "gObjectEventPic_BrendanNormalRunning",
        "sPicTable_BrendanNormal",
        [
            "graphics/object_events/pics/people/brendan/walking.png",
            "graphics/object_events/pics/people/brendan/running.png",
        ],
        "rival_brendan_normal.png",
        "gObjectEventGraphicsInfo_RivalBrendanNormal",
        "OBJ_EVENT_PAL_TAG_BRENDAN",
        100,
    ),
    "OBJ_EVENT_GFX_RIVAL_MAY_NORMAL": _rival_sprite(
        "OBJ_EVENT_GFX_RIVAL_MAY_NORMAL",
        "gObjectEventPic_MayNormalRunning",
        "sPicTable_MayNormal",
        [
            "graphics/object_events/pics/people/may/walking.png",
            "graphics/object_events/pics/people/may/running.png",
        ],
        "rival_may_normal.png",
        "gObjectEventGraphicsInfo_RivalMayNormal",
        "OBJ_EVENT_PAL_TAG_MAY",
        105,
    ),
    "OBJ_EVENT_GFX_MOM": _standard_sprite(
        "gObjectEventPic_Mom",
        "sPicTable_Mom",
        "graphics/object_events/pics/people/mom.png",
        "mom.png",
        "gObjectEventGraphicsInfo_Mom",
        "OBJ_EVENT_PAL_TAG_NPC_4",
        215,
    ),
}
VARIABLE_GRAPHICS = {
    "OBJ_EVENT_GFX_VAR_0": {
        "graphics_id": "OBJ_EVENT_GFX_VAR_0",
        "source_var": "VAR_OBJ_GFX_ID_0",
        "source_resolution": "src/event_object_movement.c:GetObjectEventGraphicsInfo -> VarGetObjectEventGraphicsId",
        "known_source_candidates": [
            "OBJ_EVENT_GFX_RIVAL_MAY_NORMAL",
            "OBJ_EVENT_GFX_RIVAL_BRENDAN_NORMAL",
        ],
        "source_constant_values": {
            "OBJ_EVENT_GFX_RIVAL_BRENDAN_NORMAL": 100,
            "OBJ_EVENT_GFX_RIVAL_MAY_NORMAL": 105,
        },
        "source_trace": [
            "include/constants/event_objects.h:OBJ_EVENT_GFX_VAR_0",
            "include/constants/vars.h:VAR_OBJ_GFX_ID_0",
            "src/event_object_movement.c:GetObjectEventGraphicsInfo",
            "data/scripts/rival_graphics.inc:Common_EventScript_SetupRivalGfxId",
        ],
        "requirements": [
            {
                "code": "object_event_var_graphics_requires_source_var",
                "detail": "Source resolves OBJ_EVENT_GFX_VAR_0 through VAR_OBJ_GFX_ID_0 at runtime, after Common_EventScript_SetupRivalGfxId runs on LittlerootTown transition.",
            }
        ],
        "unsupported": [],
    }
}


def _png_size(path):
    data = path.read_bytes()
    if len(data) < 24 or data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("{} is not a readable PNG".format(path))
    width, height = struct.unpack(">II", data[16:24])
    return width, height


def _write_sprite_asset(source_root, sprite, asset_path):
    try:
        from PIL import Image
    except ImportError as exc:
        if "source_images" not in sprite:
            shutil.copyfile(source_root / sprite["source_image"], asset_path)
            return
        raise RuntimeError("Pillow is required to stitch multi-PNG object event sheets") from exc

    if "source_images" not in sprite:
        image = _open_source_sprite_image(Image, source_root / sprite["source_image"])
        try:
            image.save(asset_path)
        finally:
            image.close()
        return

    source_paths = [source_root / source_image for source_image in sprite["source_images"]]
    opened_images = [_open_source_sprite_image(Image, source_path) for source_path in source_paths]
    try:
        heights = {image.height for image in opened_images}
        if len(heights) != 1:
            raise ValueError("Cannot stitch object event PNGs with mismatched heights: {}".format(source_paths))
        width = sum(image.width for image in opened_images)
        height = opened_images[0].height
        stitched = Image.new("RGBA", (width, height))
        x = 0
        for image in opened_images:
            stitched.paste(image, (x, 0))
            x += image.width
        stitched.save(asset_path)
    finally:
        for image in opened_images:
            image.close()


def _open_source_sprite_image(image_module, source_path):
    image = image_module.open(source_path)
    if image.mode == "P":
        alpha = image_module.new("L", image.size, 255)
        alpha.putdata([0 if pixel == 0 else 255 for pixel in image.getdata()])
        converted = image.convert("RGBA")
        converted.putalpha(alpha)
        image.close()
        return converted
    return image.convert("RGBA")


def export_object_event_sprites(source_root, output_data_root, output_asset_root):
    records = {}
    output_dir = output_asset_root / "object_events"
    output_dir.mkdir(parents=True, exist_ok=True)

    for graphics_id, sprite in SPRITES.items():
        asset_path = output_dir / sprite["asset_name"]
        _write_sprite_asset(source_root, sprite, asset_path)
        width, height = _png_size(asset_path)
        frame_size = sprite["frame_size"]
        frame_width = int(frame_size["w"])
        frame_height = int(frame_size["h"])
        source_trace = list(sprite["source_trace"])
        source_trace.append(
            "src/data/object_events/object_event_graphics_info_pointers.h:{}".format(graphics_id)
        )
        records[graphics_id] = {
            "graphics_id": graphics_id,
            "source_symbol": sprite["source_symbol"],
            "source_pic_table": sprite["source_pic_table"],
            "source_graphics_info": sprite.get("source_graphics_info", ""),
            "source_constant_value": int(sprite.get("source_constant_value", 0)),
            "source_image": to_project_path(sprite.get("source_image", sprite.get("source_images", [Path("")])[0])),
            "source_images": [
                to_project_path(source_image)
                for source_image in sprite.get("source_images", [sprite.get("source_image", Path(""))])
            ],
            "image": "res://{}".format(to_project_path(asset_path)),
            "image_project_path": to_project_path(asset_path),
            "image_size": {"w": width, "h": height},
            "frame_size": frame_size,
            "columns": width // frame_width if frame_width > 0 else 0,
            "rows": height // frame_height if frame_height > 0 else 0,
            "transparency": {
                "source_palette_index": 0,
                "rule": "gba_obj_palette_index_0_alpha_0",
                "source_trace": [
                    "tools/gbagfx/gfx.c:transparent palette index handling",
                    "GBA OBJ 4bpp palette index 0 is transparent",
                ],
            },
            "palette_tag": sprite.get("palette_tag", ""),
            "reflection_palette_tag": sprite.get("reflection_palette_tag", ""),
            "shadow_size": sprite.get("shadow_size", ""),
            "inanimate": bool(sprite.get("inanimate", False)),
            "tracks": sprite.get("tracks", ""),
            "oam": sprite.get("oam", ""),
            "subsprite_tables": sprite.get("subsprite_tables", ""),
            "static_frames": sprite["static_frames"],
            "static_frame_flips": sprite.get("static_frame_flips", {}),
            "animation_table": sprite.get("animation_table", {}),
            "source_trace": source_trace,
            "runtime_supported": sprite.get("runtime_supported", []),
            "unsupported": sprite["unsupported"],
        }

    data = {
        "schema_version": 1,
        "category": "object_events",
        "source": {
            "project": "pokeemerald-expansion",
            "kind": "first_pass_object_event_sprites",
        },
        "sprites": records,
        "variable_graphics": VARIABLE_GRAPHICS,
        "stats": {"sprite_count": len(records)},
    }
    output_path = output_data_root / "object_events" / "object_event_sprites.json"
    write_json(output_path, data)
    return output_path, data


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, help="JSON config with source and output roots.")
    parser.add_argument("--source", type=Path, help="pokeemerald-expansion source root.")
    parser.add_argument("--output-data-root", type=Path, help="Generated data output root.")
    parser.add_argument("--output-asset-root", type=Path, help="Generated asset output root.")
    args = parser.parse_args(argv)

    config = load_config(args.config)
    source_root = args.source or Path(config.get("source_root", ""))
    output_data_root = args.output_data_root or Path(config.get("generated_data_root", "data/generated"))
    output_asset_root = args.output_asset_root or Path(config.get("generated_asset_root", "assets/generated"))

    output_path, data = export_object_event_sprites(source_root, output_data_root, output_asset_root)
    manifest_entry = {
        "category": data["category"],
        "path": to_project_path(output_path),
        "sprite_count": data["stats"]["sprite_count"],
    }
    write_manifest(
        output_data_root / "import_manifest.json",
        exported_object_event_sprites=[manifest_entry],
        generator="tools/importer/export_object_event_sprites.py",
    )

    print(json.dumps({"exported": manifest_entry}, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

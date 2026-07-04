#!/usr/bin/env python3
"""Export first-pass object event sprite metadata and PNG sheets."""

import argparse
import json
import shutil
import struct
import sys
from pathlib import Path

from export_map import to_project_path, write_json, write_manifest
from source_probe import load_config


SPRITES = {
    "OBJ_EVENT_GFX_BOY_1": {
        "source_symbol": "gObjectEventPic_Boy1",
        "source_pic_table": "sPicTable_Boy1",
        "source_image": Path("graphics/object_events/pics/people/boy_1.png"),
        "asset_name": "boy_1.png",
        "frame_size": {"w": 16, "h": 32},
        "static_frames": {"down": 0, "up": 1, "left": 2, "right": 2},
        "static_frame_flips": {"right": {"h": True}},
        "animation_table": {
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
        },
        "source_trace": [
            "src/data/object_events/object_event_graphics.h:gObjectEventPic_Boy1",
            "src/data/object_events/object_event_graphics_info.h:gObjectEventGraphicsInfo_Boy1",
            "src/data/object_events/object_event_pic_tables.h:sPicTable_Boy1",
            "src/data/object_events/object_event_anims.h:sAnimTable_Standard",
            "src/data/object_events/object_event_anims.h:sAnim_FaceSouth/sAnim_FaceNorth/sAnim_FaceWest/sAnim_FaceEast",
            "src/data/object_events/object_event_anims.h:sAnim_GoSouth/sAnim_GoNorth/sAnim_GoWest/sAnim_GoEast",
            "src/event_object_movement.c:sFaceDirectionAnimNums/sMoveDirectionAnimNums",
            "src/data/object_events/object_event_graphics_info_pointers.h:OBJ_EVENT_GFX_BOY_1",
        ],
        "unsupported": [
            {
                "code": "object_event_walk_animation_not_runtime_driven",
                "detail": "Facing frames and source standard walk animation metadata are exported; this runtime slice still renders object events as static facing frames until object-event animation tasks are ported."
            }
        ],
    }
}


def _png_size(path):
    data = path.read_bytes()
    if len(data) < 24 or data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("{} is not a readable PNG".format(path))
    width, height = struct.unpack(">II", data[16:24])
    return width, height


def export_object_event_sprites(source_root, output_data_root, output_asset_root):
    records = {}
    output_dir = output_asset_root / "object_events"
    output_dir.mkdir(parents=True, exist_ok=True)

    for graphics_id, sprite in SPRITES.items():
        source_path = source_root / sprite["source_image"]
        asset_path = output_dir / sprite["asset_name"]
        shutil.copyfile(source_path, asset_path)
        width, height = _png_size(asset_path)
        frame_size = sprite["frame_size"]
        frame_width = int(frame_size["w"])
        frame_height = int(frame_size["h"])
        records[graphics_id] = {
            "graphics_id": graphics_id,
            "source_symbol": sprite["source_symbol"],
            "source_pic_table": sprite["source_pic_table"],
            "source_image": to_project_path(sprite["source_image"]),
            "image": "res://{}".format(to_project_path(asset_path)),
            "image_project_path": to_project_path(asset_path),
            "image_size": {"w": width, "h": height},
            "frame_size": frame_size,
            "columns": width // frame_width if frame_width > 0 else 0,
            "rows": height // frame_height if frame_height > 0 else 0,
            "static_frames": sprite["static_frames"],
            "static_frame_flips": sprite.get("static_frame_flips", {}),
            "animation_table": sprite.get("animation_table", {}),
            "source_trace": sprite["source_trace"],
            "unsupported": sprite["unsupported"],
        }

    data = {
        "schema_version": 1,
        "category": "object_events",
        "source": {
            "project": "pokeemerald-expansion",
            "kind": "first_pass_static_object_event_sprites",
        },
        "sprites": records,
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

"""Import exact transparent battle window-layer source captures.

This importer deliberately rejects full-scene emulator screenshots.  The
expected inputs are source-derived 240x160 RGBA images whose non-window area is
transparent, named action.png, message.png, and move.png.
"""

from __future__ import annotations

import argparse
import binascii
import json
import shutil
import struct
import sys
import tempfile
import zlib
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable, List, Sequence, Tuple


PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
PROJECT_ROOT = Path(__file__).resolve().parents[2]
EXPECTED_SIZE = (240, 160)
EXPECTED_CASES = ("action", "message", "move")
DEFAULT_OUTPUT_DIR = Path("assets/source/battle_window_captures")
DEFAULT_MANIFEST_NAME = "manifest.json"
TOP_TRANSPARENT_RECT = (0, 0, 240, 112)
BOTTOM_WINDOW_RECT = (0, 112, 240, 48)
MIN_BOTTOM_VISIBLE_PIXELS = {
    "action": 1500,
    "message": 1500,
    "move": 1500,
}


class CaptureValidationError(RuntimeError):
    pass


@dataclass(frozen=True)
class PngImage:
    path: Path
    width: int
    height: int
    pixels: bytes


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--source-dir",
        type=Path,
        help="Directory containing action.png, message.png, and move.png.",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=DEFAULT_OUTPUT_DIR,
        help="Destination directory inside the Godot project.",
    )
    parser.add_argument(
        "--manifest",
        type=Path,
        help="Manifest path. Defaults to <output-dir>/manifest.json.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Validate inputs and print the report without copying files.",
    )
    parser.add_argument(
        "--allow-overwrite",
        action="store_true",
        help="Allow replacing existing destination PNGs.",
    )
    parser.add_argument(
        "--self-test",
        action="store_true",
        help="Run importer contract checks using temporary synthetic PNGs.",
    )
    args = parser.parse_args(argv)

    if args.self_test:
        return _run_self_test()
    if args.source_dir is None:
        parser.error("--source-dir is required unless --self-test is used")

    source_dir = _resolve_path(args.source_dir)
    output_dir = _resolve_path(args.output_dir)
    manifest_path = _resolve_path(args.manifest) if args.manifest else output_dir / DEFAULT_MANIFEST_NAME
    report = import_captures(
        source_dir,
        output_dir,
        manifest_path,
        dry_run=args.dry_run,
        allow_overwrite=args.allow_overwrite,
    )
    print(json.dumps(report, indent=2, ensure_ascii=False))
    return 0


def import_captures(
    source_dir: Path,
    output_dir: Path,
    manifest_path: Path,
    *,
    dry_run: bool = False,
    allow_overwrite: bool = False,
) -> Dict[str, object]:
    rows: List[Dict[str, object]] = []
    for case_name in EXPECTED_CASES:
        source_path = source_dir / f"{case_name}.png"
        if not source_path.exists():
            raise CaptureValidationError(f"missing expected source capture: {source_path}")
        image = load_rgba_png(source_path)
        row = validate_capture(case_name, image)
        row["source_path"] = str(source_path)
        row["destination_path"] = str(output_dir / f"{case_name}.png")
        rows.append(row)

    if not dry_run:
        output_dir.mkdir(parents=True, exist_ok=True)
        for row in rows:
            source_path = Path(str(row["source_path"]))
            destination_path = Path(str(row["destination_path"]))
            if destination_path.exists() and not allow_overwrite:
                raise CaptureValidationError(
                    f"destination already exists, pass --allow-overwrite to replace: {destination_path}"
                )
            shutil.copyfile(source_path, destination_path)
        manifest_path.parent.mkdir(parents=True, exist_ok=True)
        manifest_path.write_text(
            json.dumps(
                {
                    "schema": "battle_window_source_captures.v1",
                    "expected_size": list(EXPECTED_SIZE),
                    "capture_count": len(rows),
                    "captures": rows,
                    "notes": [
                        "Exact source window-layer captures only; full-scene screenshots are invalid.",
                        "Transparent pixels outside source battle windows are part of the contract.",
                    ],
                },
                indent=2,
                ensure_ascii=False,
            )
            + "\n",
            encoding="utf-8",
        )

    return {
        "status": "ok",
        "dry_run": dry_run,
        "source_dir": str(source_dir),
        "output_dir": str(output_dir),
        "manifest": str(manifest_path),
        "expected_count": len(EXPECTED_CASES),
        "validated_count": len(rows),
        "imported_count": 0 if dry_run else len(rows),
        "captures": rows,
    }


def validate_capture(case_name: str, image: PngImage) -> Dict[str, object]:
    if (image.width, image.height) != EXPECTED_SIZE:
        raise CaptureValidationError(
            f"{case_name}.png must be {EXPECTED_SIZE[0]}x{EXPECTED_SIZE[1]}, got {image.width}x{image.height}"
        )
    top_visible = _rect_alpha_nonzero_count(image, TOP_TRANSPARENT_RECT)
    if top_visible != 0:
        raise CaptureValidationError(
            f"{case_name}.png is not a transparent window-layer capture: {top_visible} visible pixels in top scene area"
        )
    bottom_visible = _rect_alpha_nonzero_count(image, BOTTOM_WINDOW_RECT)
    min_bottom = MIN_BOTTOM_VISIBLE_PIXELS[case_name]
    if bottom_visible < min_bottom:
        raise CaptureValidationError(
            f"{case_name}.png has too few visible bottom-window pixels: {bottom_visible} < {min_bottom}"
        )
    transparent_pixels = _alpha_zero_count(image)
    if transparent_pixels < 240 * 112:
        raise CaptureValidationError(
            f"{case_name}.png does not preserve enough transparent non-window pixels: {transparent_pixels}"
        )

    row: Dict[str, object] = {
        "name": case_name,
        "status": "validated",
        "size": [image.width, image.height],
        "signature": _image_signature(image),
        "visible_pixel_count": _alpha_nonzero_count(image),
        "transparent_pixel_count": transparent_pixels,
        "top_visible_pixel_count": top_visible,
        "bottom_visible_pixel_count": bottom_visible,
    }
    if case_name == "action":
        _require_case_region(image, case_name, "action_prompt_region", (0, 112, 120, 48), 500, row)
        _require_case_region(image, case_name, "action_menu_region", (120, 112, 120, 48), 500, row)
    elif case_name == "move":
        _require_case_region(image, case_name, "move_name_region", (0, 112, 160, 48), 500, row)
        _require_case_region(image, case_name, "move_pp_type_region", (160, 112, 80, 48), 200, row)
    return row


def load_rgba_png(path: Path) -> PngImage:
    data = path.read_bytes()
    if not data.startswith(PNG_SIGNATURE):
        raise CaptureValidationError(f"not a PNG file: {path}")
    offset = len(PNG_SIGNATURE)
    width = height = bit_depth = color_type = interlace = None
    idat_parts: List[bytes] = []
    seen_iend = False
    while offset + 8 <= len(data):
        length = struct.unpack(">I", data[offset : offset + 4])[0]
        chunk_type = data[offset + 4 : offset + 8]
        chunk_data = data[offset + 8 : offset + 8 + length]
        crc_start = offset + 4
        crc_end = offset + 8 + length
        expected_crc = struct.unpack(">I", data[crc_end : crc_end + 4])[0]
        actual_crc = binascii.crc32(data[crc_start:crc_end]) & 0xFFFFFFFF
        if actual_crc != expected_crc:
            raise CaptureValidationError(f"PNG CRC mismatch in {path}: {chunk_type!r}")
        offset = crc_end + 4
        if chunk_type == b"IHDR":
            width, height, bit_depth, color_type, compression, filter_method, interlace = struct.unpack(
                ">IIBBBBB", chunk_data
            )
            if compression != 0 or filter_method != 0:
                raise CaptureValidationError(f"unsupported PNG compression/filter method: {path}")
        elif chunk_type == b"IDAT":
            idat_parts.append(chunk_data)
        elif chunk_type == b"IEND":
            seen_iend = True
            break
    if not seen_iend or width is None or height is None:
        raise CaptureValidationError(f"incomplete PNG file: {path}")
    if bit_depth != 8 or color_type != 6 or interlace != 0:
        raise CaptureValidationError(
            f"{path} must be non-interlaced 8-bit RGBA PNG, got bit_depth={bit_depth} color_type={color_type} interlace={interlace}"
        )
    pixels = _decode_png_rgba_pixels(width, height, b"".join(idat_parts), path)
    return PngImage(path=path, width=width, height=height, pixels=pixels)


def _decode_png_rgba_pixels(width: int, height: int, idat_data: bytes, path: Path) -> bytes:
    try:
        raw = zlib.decompress(idat_data)
    except zlib.error as exc:
        raise CaptureValidationError(f"could not decompress PNG IDAT data in {path}: {exc}") from exc
    row_size = width * 4
    expected_length = (row_size + 1) * height
    if len(raw) != expected_length:
        raise CaptureValidationError(f"unexpected decoded PNG length in {path}: {len(raw)} != {expected_length}")

    pixels = bytearray()
    previous = bytearray(row_size)
    offset = 0
    for _row in range(height):
        filter_type = raw[offset]
        offset += 1
        scanline = bytearray(raw[offset : offset + row_size])
        offset += row_size
        _unfilter_scanline(scanline, previous, filter_type, 4)
        pixels.extend(scanline)
        previous = scanline
    return bytes(pixels)


def _unfilter_scanline(scanline: bytearray, previous: bytearray, filter_type: int, bpp: int) -> None:
    if filter_type == 0:
        return
    if filter_type == 1:
        for index in range(len(scanline)):
            left = scanline[index - bpp] if index >= bpp else 0
            scanline[index] = (scanline[index] + left) & 0xFF
        return
    if filter_type == 2:
        for index in range(len(scanline)):
            scanline[index] = (scanline[index] + previous[index]) & 0xFF
        return
    if filter_type == 3:
        for index in range(len(scanline)):
            left = scanline[index - bpp] if index >= bpp else 0
            up = previous[index]
            scanline[index] = (scanline[index] + ((left + up) // 2)) & 0xFF
        return
    if filter_type == 4:
        for index in range(len(scanline)):
            left = scanline[index - bpp] if index >= bpp else 0
            up = previous[index]
            up_left = previous[index - bpp] if index >= bpp else 0
            scanline[index] = (scanline[index] + _paeth(left, up, up_left)) & 0xFF
        return
    raise CaptureValidationError(f"unsupported PNG filter type: {filter_type}")


def _paeth(left: int, up: int, up_left: int) -> int:
    estimate = left + up - up_left
    distance_left = abs(estimate - left)
    distance_up = abs(estimate - up)
    distance_up_left = abs(estimate - up_left)
    if distance_left <= distance_up and distance_left <= distance_up_left:
        return left
    if distance_up <= distance_up_left:
        return up
    return up_left


def _require_case_region(
    image: PngImage,
    case_name: str,
    label: str,
    rect: Tuple[int, int, int, int],
    minimum: int,
    row: Dict[str, object],
) -> None:
    visible = _rect_alpha_nonzero_count(image, rect)
    row[f"{label}_visible_pixel_count"] = visible
    if visible < minimum:
        raise CaptureValidationError(
            f"{case_name}.png has too few visible pixels in {label}: {visible} < {minimum}"
        )


def _alpha_nonzero_count(image: PngImage) -> int:
    return sum(1 for index in range(3, len(image.pixels), 4) if image.pixels[index] != 0)


def _alpha_zero_count(image: PngImage) -> int:
    return sum(1 for index in range(3, len(image.pixels), 4) if image.pixels[index] == 0)


def _rect_alpha_nonzero_count(image: PngImage, rect: Tuple[int, int, int, int]) -> int:
    x0, y0, width, height = rect
    count = 0
    for y in range(y0, y0 + height):
        for x in range(x0, x0 + width):
            if x < 0 or y < 0 or x >= image.width or y >= image.height:
                continue
            if image.pixels[(y * image.width + x) * 4 + 3] != 0:
                count += 1
    return count


def _image_signature(image: PngImage) -> str:
    value = 2166136261
    for channel in image.pixels:
        value = ((value ^ channel) * 16777619) & 0xFFFFFFFF
    return f"{value:08X}"


def _resolve_path(path: Path) -> Path:
    return path if path.is_absolute() else PROJECT_ROOT / path


def _run_self_test() -> int:
    with tempfile.TemporaryDirectory(prefix="battle_window_capture_import_") as temp_name:
        temp_root = Path(temp_name)
        source_dir = temp_root / "source"
        output_dir = temp_root / "out"
        source_dir.mkdir()
        _write_fixture_capture(source_dir / "action.png", "action")
        _write_fixture_capture(source_dir / "message.png", "message")
        _write_fixture_capture(source_dir / "move.png", "move")
        report = import_captures(source_dir, output_dir, output_dir / "manifest.json")
        if int(report["validated_count"]) != 3 or int(report["imported_count"]) != 3:
            raise AssertionError("expected self-test import to validate and copy 3 captures")
        _write_opaque_fixture(source_dir / "action.png")
        try:
            import_captures(source_dir, output_dir, output_dir / "manifest.json", dry_run=True, allow_overwrite=True)
        except CaptureValidationError as exc:
            if "transparent window-layer" not in str(exc):
                raise
        else:
            raise AssertionError("expected opaque full-scene-like capture to be rejected")
    print(json.dumps({"battle_window_capture_import_self_test": "ok", "validated_cases": len(EXPECTED_CASES)}))
    return 0


def _write_fixture_capture(path: Path, case_name: str) -> None:
    pixels = bytearray(EXPECTED_SIZE[0] * EXPECTED_SIZE[1] * 4)
    if case_name == "action":
        _fill_rect_rgba(pixels, (0, 112, 120, 48), (214, 74, 57, 255))
        _fill_rect_rgba(pixels, (128, 112, 112, 48), (248, 248, 224, 255))
    elif case_name == "message":
        _fill_rect_rgba(pixels, (0, 112, 240, 48), (107, 165, 165, 255))
    elif case_name == "move":
        _fill_rect_rgba(pixels, (0, 112, 160, 48), (248, 248, 224, 255))
        _fill_rect_rgba(pixels, (160, 128, 80, 32), (248, 248, 224, 255))
    _write_rgba_png(path, EXPECTED_SIZE[0], EXPECTED_SIZE[1], pixels)


def _write_opaque_fixture(path: Path) -> None:
    pixels = bytearray()
    pixels.extend(bytes((120, 160, 120, 255)) * (EXPECTED_SIZE[0] * EXPECTED_SIZE[1]))
    _write_rgba_png(path, EXPECTED_SIZE[0], EXPECTED_SIZE[1], pixels)


def _fill_rect_rgba(pixels: bytearray, rect: Tuple[int, int, int, int], rgba: Tuple[int, int, int, int]) -> None:
    x0, y0, width, height = rect
    for y in range(y0, y0 + height):
        for x in range(x0, x0 + width):
            offset = (y * EXPECTED_SIZE[0] + x) * 4
            pixels[offset : offset + 4] = bytes(rgba)


def _write_rgba_png(path: Path, width: int, height: int, pixels: Iterable[int]) -> None:
    raw_pixels = bytes(pixels)
    row_size = width * 4
    rows = []
    for y in range(height):
        start = y * row_size
        rows.append(b"\x00" + raw_pixels[start : start + row_size])
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    data = PNG_SIGNATURE
    data += _png_chunk(b"IHDR", ihdr)
    data += _png_chunk(b"IDAT", zlib.compress(b"".join(rows)))
    data += _png_chunk(b"IEND", b"")
    path.write_bytes(data)


def _png_chunk(chunk_type: bytes, chunk_data: bytes) -> bytes:
    crc = binascii.crc32(chunk_type + chunk_data) & 0xFFFFFFFF
    return struct.pack(">I", len(chunk_data)) + chunk_type + chunk_data + struct.pack(">I", crc)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except CaptureValidationError as exc:
        print(json.dumps({"status": "error", "error": str(exc)}, ensure_ascii=False), file=sys.stderr)
        raise SystemExit(1)

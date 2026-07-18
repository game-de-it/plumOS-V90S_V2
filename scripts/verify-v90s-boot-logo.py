#!/usr/bin/env python3
"""Validate the fixed BMP contract consumed by the V90S bootloader."""

from __future__ import annotations

import pathlib
import struct
import sys


def fail(message: str) -> None:
    raise SystemExit(f"boot-logo: FAIL: {message}")


def main() -> None:
    if len(sys.argv) != 2:
        fail("usage: verify-v90s-boot-logo.py PATH")

    path = pathlib.Path(sys.argv[1])
    try:
        data = path.read_bytes()
    except OSError as exc:
        fail(f"cannot read {path}: {exc}")

    if len(data) < 54 or data[:2] != b"BM":
        fail(f"{path} is not a Windows BMP")

    declared_size = struct.unpack_from("<I", data, 2)[0]
    pixel_offset = struct.unpack_from("<I", data, 10)[0]
    dib_size = struct.unpack_from("<I", data, 14)[0]
    width, height = struct.unpack_from("<ii", data, 18)
    planes, bits_per_pixel = struct.unpack_from("<HH", data, 26)
    compression = struct.unpack_from("<I", data, 30)[0]

    if dib_size != 40:
        fail(f"DIB header is {dib_size} bytes; expected Windows 3.x 40-byte header")
    if (width, height) != (640, 480):
        fail(f"dimensions are {width}x{height}; expected 640x480")
    if planes != 1 or bits_per_pixel != 24:
        fail(f"pixel format is planes={planes} bpp={bits_per_pixel}; expected 1x24-bit")
    if compression != 0:
        fail(f"compression is {compression}; expected uncompressed BI_RGB")
    if pixel_offset != 54:
        fail(f"pixel offset is {pixel_offset}; expected 54")
    if declared_size != len(data):
        fail(f"declared size is {declared_size}; actual size is {len(data)}")

    row_size = ((width * bits_per_pixel + 31) // 32) * 4
    expected_size = pixel_offset + row_size * height
    if len(data) != expected_size:
        fail(f"pixel payload size is {len(data)}; expected {expected_size}")

    print(
        f"boot-logo: PASS path={path} size={len(data)} "
        f"dimensions={width}x{height} bpp={bits_per_pixel}"
    )


if __name__ == "__main__":
    main()

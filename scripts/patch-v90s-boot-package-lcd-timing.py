#!/usr/bin/env python3
"""Patch LCD timing cells inside a V90S boot_package.fex in place-by-copy.

The tool preserves the original boot_package.fex layout and only changes the
selected 32-bit cells inside the embedded DTB block.
"""

import argparse
import struct
import sys
from pathlib import Path


BOOT_PACKAGE_ENTRIES = (
    {"name_offset": 0x40, "info_offset": 0x80},
    {"name_offset": 0x1B0, "info_offset": 0x1F0},
    {"name_offset": 0x320, "info_offset": 0x360},
    {"name_offset": 0x490, "info_offset": 0x4D0},
)

FDT_MAGIC = 0xD00DFEED
FDT_BEGIN_NODE = 1
FDT_END_NODE = 2
FDT_PROP = 3
FDT_NOP = 4
FDT_END = 9


def parse_int(text):
    return int(text, 0)


def align4(value):
    return (value + 3) & ~3


def c_string(data, offset, limit=None):
    end_limit = len(data) if limit is None else limit
    end = data.find(b"\0", offset, end_limit)
    if end < 0:
        raise ValueError(f"unterminated string at offset 0x{offset:x}")
    return data[offset:end].decode("ascii")


def find_dtb_entry(package):
    for entry in BOOT_PACKAGE_ENTRIES:
        name = c_string(package, entry["name_offset"], entry["name_offset"] + 16)
        offset, length = struct.unpack_from("<II", package, entry["info_offset"])
        if name == "dtb":
            if offset + length > len(package):
                raise ValueError("dtb entry extends past end of boot package")
            return offset, length
    raise ValueError("dtb entry not found in boot package header")


def parse_fdt_header(dtb):
    if len(dtb) < 40:
        raise ValueError("DTB block is too small")
    fields = struct.unpack_from(">10I", dtb, 0)
    if fields[0] != FDT_MAGIC:
        raise ValueError(f"bad DTB magic: 0x{fields[0]:08x}")
    header = {
        "totalsize": fields[1],
        "off_dt_struct": fields[2],
        "off_dt_strings": fields[3],
        "off_mem_rsvmap": fields[4],
        "version": fields[5],
        "last_comp_version": fields[6],
        "boot_cpuid_phys": fields[7],
        "size_dt_strings": fields[8],
        "size_dt_struct": fields[9],
    }
    if header["totalsize"] > len(dtb):
        raise ValueError("DTB totalsize extends past dtb entry length")
    return header


def fdt_path(stack):
    names = [name for name in stack if name]
    if not names:
        return "/"
    return "/" + "/".join(names)


def patch_dtb_cells(dtb, requested, expected):
    header = parse_fdt_header(dtb)
    struct_start = header["off_dt_struct"]
    struct_end = struct_start + header["size_dt_struct"]
    strings_start = header["off_dt_strings"]
    strings_end = strings_start + header["size_dt_strings"]
    if struct_end > header["totalsize"] or strings_end > header["totalsize"]:
        raise ValueError("DTB structure or strings block extends past totalsize")

    strings = dtb[strings_start:strings_end]
    pos = struct_start
    stack = []
    patched = []
    seen = {name: 0 for name in requested}

    while pos < struct_end:
        token = struct.unpack_from(">I", dtb, pos)[0]
        pos += 4

        if token == FDT_BEGIN_NODE:
            name = c_string(dtb, pos, struct_end)
            pos = align4(pos + len(name.encode("ascii")) + 1)
            stack.append(name)
            continue

        if token == FDT_END_NODE:
            if stack:
                stack.pop()
            continue

        if token == FDT_PROP:
            prop_len, nameoff = struct.unpack_from(">II", dtb, pos)
            pos += 8
            if nameoff >= len(strings):
                raise ValueError(f"bad property name offset: 0x{nameoff:x}")
            prop_name = c_string(strings, nameoff)
            value_pos = pos
            if prop_name in requested:
                if prop_len != 4:
                    raise ValueError(f"{prop_name} is {prop_len} bytes, expected one 32-bit cell")
                old_value = struct.unpack_from(">I", dtb, value_pos)[0]
                if prop_name in expected and old_value != expected[prop_name]:
                    raise ValueError(
                        f"{prop_name} expected {expected[prop_name]}, found {old_value}"
                    )
                new_value = requested[prop_name]
                struct.pack_into(">I", dtb, value_pos, new_value)
                seen[prop_name] += 1
                patched.append((fdt_path(stack), prop_name, old_value, new_value))
            pos = align4(pos + prop_len)
            continue

        if token == FDT_NOP:
            continue

        if token == FDT_END:
            break

        raise ValueError(f"unexpected FDT token {token} at offset 0x{pos - 4:x}")

    missing = [name for name, count in seen.items() if count == 0]
    if missing:
        raise ValueError("missing DTB properties: " + ", ".join(sorted(missing)))
    return patched


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, help="source boot_package.fex")
    parser.add_argument("--output", required=True, help="patched boot_package.fex")
    parser.add_argument("--lcd-dclk-freq", type=parse_int, help="new lcd_dclk_freq cell")
    parser.add_argument("--lcd-ht", type=parse_int, help="new lcd_ht cell")
    parser.add_argument("--lcd-vt", type=parse_int, help="new lcd_vt cell")
    parser.add_argument("--expect-lcd-dclk-freq", type=parse_int, help="expected old lcd_dclk_freq")
    parser.add_argument("--expect-lcd-ht", type=parse_int, help="expected old lcd_ht")
    parser.add_argument("--expect-lcd-vt", type=parse_int, help="expected old lcd_vt")
    args = parser.parse_args()

    requested = {}
    expected = {}
    for arg_name, prop_name in (
        ("lcd_dclk_freq", "lcd_dclk_freq"),
        ("lcd_ht", "lcd_ht"),
        ("lcd_vt", "lcd_vt"),
    ):
        value = getattr(args, arg_name)
        if value is not None:
            requested[prop_name] = value
        expect_value = getattr(args, f"expect_{arg_name}")
        if expect_value is not None:
            expected[prop_name] = expect_value

    if not requested:
        parser.error("at least one LCD timing value must be provided")

    package_path = Path(args.input)
    output_path = Path(args.output)
    package = bytearray(package_path.read_bytes())
    dtb_offset, dtb_length = find_dtb_entry(package)
    dtb = bytearray(package[dtb_offset : dtb_offset + dtb_length])
    patched = patch_dtb_cells(dtb, requested, expected)
    package[dtb_offset : dtb_offset + dtb_length] = dtb

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_bytes(package)

    print(f"dtb offset=0x{dtb_offset:x} length={dtb_length}")
    for path, name, old_value, new_value in patched:
        print(f"patched {path}:{name} {old_value} -> {new_value}")
    print(f"wrote {output_path}")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"error: {exc}", file=sys.stderr)
        sys.exit(1)

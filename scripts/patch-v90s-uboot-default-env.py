#!/usr/bin/env python3
"""Extract a V90S boot package and install a fixed U-Boot default bootcmd."""

import argparse
import hashlib
import json
import struct
import sys
from pathlib import Path


BOOT_PACKAGE_ENTRIES = (
    {"name_offset": 0x40, "info_offset": 0x80},
    {"name_offset": 0x1B0, "info_offset": 0x1F0},
    {"name_offset": 0x320, "info_offset": 0x360},
    {"name_offset": 0x490, "info_offset": 0x4D0},
)

OLD_DEFAULT_ENV = (
    b"bootcmd=run distro_bootcmd\0"
    b"bootdelay=2\0"
    b"baudrate=115200\0\0"
)
NEW_DEFAULT_ENV = b"bootcmd=sunxi_flash read 45000000 boot;bootm 45000000\0\0"


def c_string(data, offset, limit):
    end = data.find(b"\0", offset, limit)
    if end < 0:
        raise ValueError(f"unterminated string at 0x{offset:x}")
    return data[offset:end].decode("ascii")


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def extract_entries(package):
    result = {}
    for spec in BOOT_PACKAGE_ENTRIES:
        name = c_string(package, spec["name_offset"], spec["name_offset"] + 16)
        offset, length = struct.unpack_from("<II", package, spec["info_offset"])
        if not name:
            raise ValueError(f"empty entry name at 0x{spec['name_offset']:x}")
        if offset + length > len(package):
            raise ValueError(f"entry {name} extends past boot package")
        if name in result:
            raise ValueError(f"duplicate boot package entry: {name}")
        result[name] = bytes(package[offset : offset + length])
    expected = {"u-boot", "monitor", "scp", "dtb"}
    if set(result) != expected:
        raise ValueError(f"unexpected entries: {sorted(result)}")
    return result


def patch_uboot(uboot):
    occurrences = uboot.count(OLD_DEFAULT_ENV)
    if occurrences != 1:
        raise ValueError(
            f"expected one known default environment, found {occurrences}"
        )
    if len(NEW_DEFAULT_ENV) > len(OLD_DEFAULT_ENV):
        raise ValueError("replacement environment exceeds original allocation")
    replacement = NEW_DEFAULT_ENV.ljust(len(OLD_DEFAULT_ENV), b"\0")
    patched = uboot.replace(OLD_DEFAULT_ENV, replacement, 1)
    if OLD_DEFAULT_ENV in patched:
        raise ValueError("old default environment remains after patch")
    if patched.count(NEW_DEFAULT_ENV) != 1:
        raise ValueError("new default environment was not installed exactly once")
    return patched


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, help="source boot_package.fex")
    parser.add_argument("--output-dir", help="component output directory")
    parser.add_argument("--manifest", help="JSON extraction manifest")
    parser.add_argument(
        "--verify-fixed", action="store_true", help="verify a previously patched package"
    )
    args = parser.parse_args()

    package_path = Path(args.input)
    package = package_path.read_bytes()
    entries = extract_entries(package)

    if args.verify_fixed:
        uboot = entries["u-boot"]
        if OLD_DEFAULT_ENV in uboot:
            raise ValueError("old external-env default remains")
        if uboot.count(NEW_DEFAULT_ENV) != 1:
            raise ValueError("fixed bootcmd is not present exactly once")
        print("fixed_bootcmd=verified")
        print(f"boot_package_sha256={sha256(package)}")
        return

    if not args.output_dir or not args.manifest:
        parser.error("--output-dir and --manifest are required when patching")
    output_dir = Path(args.output_dir)
    manifest_path = Path(args.manifest)

    original_uboot = entries["u-boot"]
    entries["u-boot"] = patch_uboot(original_uboot)

    output_dir.mkdir(parents=True, exist_ok=True)
    filenames = {
        "u-boot": "u-boot.bin",
        "monitor": "monitor.bin",
        "scp": "scp.bin",
        "dtb": "dtb.bin",
    }
    entry_manifest = {}
    for name, data in entries.items():
        filename = filenames[name]
        (output_dir / filename).write_bytes(data)
        entry_manifest[name] = {
            "file": filename,
            "size": len(data),
            "sha256": sha256(data),
        }

    (output_dir / "u-boot.source.bin").write_bytes(original_uboot)

    entry_manifest["u-boot"]["source_sha256"] = sha256(original_uboot)
    entry_manifest["u-boot"]["source_file"] = "u-boot.source.bin"
    manifest = {
        "source": str(package_path),
        "source_size": len(package),
        "source_sha256": sha256(package),
        "bootcmd": "sunxi_flash read 45000000 boot;bootm 45000000",
        "entries": entry_manifest,
    }
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    print(f"extracted and patched: {package_path}")
    print(f"components: {output_dir}")
    print(f"manifest: {manifest_path}")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"error: {exc}", file=sys.stderr)
        sys.exit(1)

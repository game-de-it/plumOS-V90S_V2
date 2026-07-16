#!/usr/bin/env python3
"""Start the official PortMaster GUI with the plumOS V90S hardware contract."""

from __future__ import annotations

import builtins
import hashlib
import os
import shutil
import stat
import sys
import zipfile
from pathlib import Path, PurePosixPath


APP_ROOT = Path(os.environ.get("PLUMOS_PORTMASTER_APP_ROOT", "/mnt/plumos/apps/portmaster"))
PORTMASTER_DIR = APP_ROOT / "upstream" / "PortMaster"
SELF_UPDATE_CALL = b"            if portmaster_check_update(pm, config, temp_dir):"
PLUMOS_SELF_UPDATE_CALL = b"            if plumos_portmaster_check_update(pm, config, temp_dir):"


def safe_extract_pylibs() -> None:
    archive = PORTMASTER_DIR / "pylibs.zip"
    if not archive.is_file():
        return

    with zipfile.ZipFile(archive) as zf:
        for entry in zf.infolist():
            path = PurePosixPath(entry.filename)
            mode = entry.external_attr >> 16
            if path.is_absolute() or ".." in path.parts or stat.S_ISLNK(mode):
                raise RuntimeError(f"unsafe pylibs entry: {entry.filename}")

        for name in ("pylibs", "exlibs"):
            target = PORTMASTER_DIR / name
            if target.exists():
                shutil.rmtree(target)
        zf.extractall(PORTMASTER_DIR)
        os.sync()

    digest = hashlib.md5(archive.read_bytes()).hexdigest()
    digest_path = PORTMASTER_DIR / "pylibs.zip.md5"
    temp_digest = digest_path.with_name(f"{digest_path.name}.tmp.{os.getpid()}")
    with temp_digest.open("w", encoding="ascii") as output:
        output.write(digest + "\n")
        output.flush()
        os.fsync(output.fileno())
    temp_digest.replace(digest_path)
    archive.unlink()
    os.sync()


def install_v90s_contract() -> None:
    sys.path.insert(0, str(PORTMASTER_DIR / "exlibs"))
    sys.path.insert(0, str(PORTMASTER_DIR / "pylibs"))

    import harbourmaster  # type: ignore
    from harbourmaster import hardware, platform  # type: ignore

    hardware.DEVICES["Powkiddy V90S"] = {
        "device": "powkiddy-v90s",
        "manufacturer": "Powkiddy",
        "cfw": ["plumOS"],
    }
    hardware.HW_INFO["powkiddy-v90s"] = {
        "resolution": (640, 480),
        "analogsticks": 0,
        "cpu": "a133plus",
        "capabilities": [],
        "ram": 1024,
    }

    original_new_device_info = hardware.new_device_info

    def plumos_new_device_info():
        info = original_new_device_info()
        info.update(
            name="plumOS",
            version=os.environ.get("PLUMOS_PORTMASTER_CFW_VERSION", "unknown"),
            device="powkiddy-v90s",
        )
        return info

    hardware.new_device_info = plumos_new_device_info
    hardware.__root_info = None
    harbourmaster.HW_INFO["powkiddy-v90s"] = hardware.HW_INFO["powkiddy-v90s"]
    platform.HM_PLATFORMS["plumos"] = platform.PlatformBase
    harbourmaster.HM_PLATFORMS["plumos"] = platform.PlatformBase


def disable_upstream_self_update(source: bytes) -> bytes:
    """Keep catalog checks enabled while plumOS owns payload replacement."""
    if source.count(SELF_UPDATE_CALL) != 1:
        raise RuntimeError("unsupported PortMaster self-update call layout")
    return source.replace(SELF_UPDATE_CALL, PLUMOS_SELF_UPDATE_CALL, 1)


def plumos_portmaster_check_update(*_args, **_kwargs) -> bool:
    return False


def main() -> int:
    if not (PORTMASTER_DIR / "pugwash").is_file():
        raise SystemExit(f"PortMaster payload is incomplete: {PORTMASTER_DIR}")

    safe_extract_pylibs()
    install_v90s_contract()
    pugwash = PORTMASTER_DIR / "pugwash"
    sys.argv[0] = str(pugwash)
    globals_dict = {
        "__builtins__": builtins,
        "__file__": str(pugwash),
        "__name__": "__main__",
        "__package__": None,
        "plumos_portmaster_check_update": plumos_portmaster_check_update,
    }
    source = disable_upstream_self_update(pugwash.read_bytes())
    exec(compile(source, str(pugwash), "exec"), globals_dict)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

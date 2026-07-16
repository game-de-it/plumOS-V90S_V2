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

    digest = hashlib.md5(archive.read_bytes()).hexdigest()
    (PORTMASTER_DIR / "pylibs.zip.md5").write_text(digest + "\n", encoding="ascii")
    archive.unlink()


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
    }
    exec(compile(pugwash.read_bytes(), str(pugwash), "exec"), globals_dict)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

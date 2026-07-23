#!/usr/bin/env python3
"""Validate and fingerprint reusable V90S emulator build outputs."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import sys


COMPONENTS = ("retroarch", "cores", "picoarch", "standalone")
CACHE_FORMAT = 1


def component_inputs(root: Path, component: str, version: str):
    common = [
        "scripts/docker-build.sh",
        "docker/plumos-v90s-toolchain/Dockerfile",
    ]
    patterns = {
        "retroarch": [
            "scripts/build-retroarch-powervr.sh",
            "scripts/build-retroarch-knulli.sh",
            "patches/retroarch/**/*",
            "configs/retroarch/**/*",
            "package/frontend-v90s/plumos/factory-defaults/ra/**/*",
            f"artifacts/release-inputs/v90s-{version}/hardware-knulli-a133.tar.gz",
            f"artifacts/release-inputs/v90s-{version}/hardware-ge8300-glibc.tar.gz",
        ],
        "cores": [
            "docker/plumos-v90s-toolchain/scripts/build-libretro-cores.sh",
            "docker/plumos-v90s-toolchain/libretro-core-recipes.tsv",
            "docker/plumos-v90s-toolchain/patches/**/*",
        ],
        "picoarch": [
            "docker/plumos-v90s-toolchain/scripts/build-picoarch.sh",
            "docker/plumos-v90s-toolchain/picoarch/**/*",
            "package/picoarch-v90s/**/*",
        ],
        "standalone": [
            "docker/plumos-v90s-toolchain/scripts/build-standalone-emulators.sh",
            "docker/plumos-v90s-toolchain/patches/**/*",
            "docker/plumos-v90s-toolchain/standalone/**/*",
            "package/frontend-v90s/plumos/factory-defaults/sa/**/*",
            f"artifacts/release-inputs/v90s-{version}/sdl2-powervr.tar.gz",
        ],
    }
    files = set()
    for pattern in common + patterns[component]:
        for path in root.glob(pattern):
            if path.is_file():
                files.add(path)
    return sorted(files)


def relevant_environment():
    exact = {
        "AR",
        "AS",
        "BUILD_JOB_FALLBACKS",
        "CC",
        "CFLAGS",
        "CORE_INFO_REF",
        "CORE_INFO_REPO",
        "CORE_RECIPES",
        "CXX",
        "CXXFLAGS",
        "FAIL_ON_CORE_ERROR",
        "FAIL_ON_STANDALONE_ERROR",
        "JOBS",
        "LDFLAGS",
        "PLUMOS_CORE_FILTER",
        "PLUMOS_STANDALONE_FILTER",
        "RANLIB",
        "READELF",
        "SCUMMVM_ENGINES",
        "STRIP",
        "YABASANSHIRO_AS",
        "YABASANSHIRO_CC",
        "YABASANSHIRO_CXX",
    }
    suffixes = ("_REF", "_REPO", "_SHA256", "_MD5")
    prefixes = (
        "PLUMOS_V90S_DOCKER_",
        "PLUMOS_V90S_RETROARCH_",
        "PLUMOS_V90S_CORES_",
        "PLUMOS_V90S_PICOARCH_",
        "PLUMOS_V90S_STANDALONE_",
    )
    result = {}
    for key, value in os.environ.items():
        if key in exact or key.endswith(suffixes) or key.startswith(prefixes):
            result[key] = value
    return result


def input_fingerprint(root: Path, component: str, version: str):
    digest = hashlib.sha256()
    digest.update(f"cache-format={CACHE_FORMAT}\ncomponent={component}\n".encode())
    files = component_inputs(root, component, version)
    if not files:
        raise RuntimeError(f"no input files found for {component}")
    for path in files:
        relative = path.relative_to(root).as_posix()
        digest.update(f"file={relative}\n".encode())
        with path.open("rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(chunk)
    for key, value in sorted(relevant_environment().items()):
        digest.update(f"env={key}={value}\n".encode())
    return digest.hexdigest(), [path.relative_to(root).as_posix() for path in files]


def parse_checksum_file(checksum_file: Path, base: Path):
    entries = []
    for line in checksum_file.read_text().splitlines():
        if not line.strip():
            continue
        fields = line.split(maxsplit=1)
        if len(fields) != 2 or len(fields[0]) != 64:
            raise ValueError(f"invalid checksum line in {checksum_file}: {line}")
        relative = fields[1].lstrip("*")
        while relative.startswith("./"):
            relative = relative[2:]
        entries.append((fields[0].lower(), base / relative))
    return entries


def verify_entries(entries):
    for expected, path in entries:
        if not path.is_file():
            return False, f"missing output: {path}"
        digest = hashlib.sha256()
        with path.open("rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(chunk)
        actual = digest.hexdigest()
        if actual != expected:
            return False, f"checksum mismatch: {path}"
    return True, "ok"


def verify_output(root: Path, component: str):
    if component == "retroarch":
        output = root / "output/retroarch-powervr"
        manifest = output / "manifest.txt"
        checksum_files = sorted(output.glob("*.sha256"))
        if not manifest.is_file() or not checksum_files:
            return False, "RetroArch manifest or checksums are missing"
        entries = []
        for checksum_file in checksum_files:
            entries.extend(parse_checksum_file(checksum_file, root))
        return verify_entries(entries)

    output_map = {
        "cores": root / "output/libretro-cores/v90s",
        "picoarch": root / "output/picoarch/v90s",
        "standalone": root / "output/standalone-emulators/v90s",
    }
    manifest_map = {
        "cores": "libretro-cores.manifest",
        "picoarch": "picoarch.manifest",
        "standalone": "standalone-emulators.manifest",
    }
    output = output_map[component]
    manifest = output / manifest_map[component]
    checksum_file = output / "checksums.sha256"
    if not manifest.is_file() or not checksum_file.is_file():
        return False, f"{component} manifest or checksums are missing"
    manifest_text = manifest.read_text()
    if component == "cores" and (
        "built=114" not in manifest_text or "failed=0" not in manifest_text
    ):
        return False, "core output is not the complete 114-core set"
    if component == "standalone" and (
        "built=9" not in manifest_text or "failed=0" not in manifest_text
    ):
        return False, "standalone output is not the complete 9-emulator set"
    return verify_entries(parse_checksum_file(checksum_file, output))


def output_identity(root: Path, component: str):
    paths = {
        "retroarch": root / "output/retroarch-powervr/manifest.txt",
        "cores": root / "output/libretro-cores/v90s/checksums.sha256",
        "picoarch": root / "output/picoarch/v90s/checksums.sha256",
        "standalone": root / "output/standalone-emulators/v90s/checksums.sha256",
    }
    return hashlib.sha256(paths[component].read_bytes()).hexdigest()


def stamp_path(root: Path, component: str):
    return root / "output/release-cache/v90s" / f"{component}.json"


def record(root: Path, component: str, version: str):
    valid, reason = verify_output(root, component)
    if not valid:
        raise RuntimeError(reason)
    fingerprint, files = input_fingerprint(root, component, version)
    stamp = {
        "format": CACHE_FORMAT,
        "component": component,
        "input_sha256": fingerprint,
        "input_file_count": len(files),
        "output_sha256": output_identity(root, component),
    }
    target = stamp_path(root, component)
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = target.with_suffix(f".tmp.{os.getpid()}")
    temporary.write_text(json.dumps(stamp, indent=2, sort_keys=True) + "\n")
    temporary.replace(target)
    print(f"cache=recorded component={component} input={fingerprint}")


def check(root: Path, component: str, version: str):
    target = stamp_path(root, component)
    if not target.is_file():
        print(f"cache=miss component={component} reason=stamp-missing")
        return False
    try:
        stamp = json.loads(target.read_text())
        fingerprint, _ = input_fingerprint(root, component, version)
    except (OSError, ValueError, RuntimeError, json.JSONDecodeError) as error:
        print(f"cache=miss component={component} reason={error}")
        return False
    if stamp.get("format") != CACHE_FORMAT:
        print(f"cache=miss component={component} reason=format")
        return False
    if stamp.get("input_sha256") != fingerprint:
        print(f"cache=miss component={component} reason=input-changed")
        return False
    valid, reason = verify_output(root, component)
    if not valid:
        print(f"cache=miss component={component} reason={reason}")
        return False
    if stamp.get("output_sha256") != output_identity(root, component):
        print(f"cache=miss component={component} reason=output-identity")
        return False
    print(f"cache=hit component={component} input={fingerprint}")
    return True


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("check", "record", "verify"))
    parser.add_argument("component", choices=COMPONENTS)
    parser.add_argument("--version", required=True)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    root = args.root.resolve()
    try:
        if args.action == "check":
            return 0 if check(root, args.component, args.version) else 1
        if args.action == "record":
            record(root, args.component, args.version)
            return 0
        valid, reason = verify_output(root, args.component)
        print(f"output={'valid' if valid else 'invalid'} component={args.component} reason={reason}")
        return 0 if valid else 1
    except (OSError, ValueError, RuntimeError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

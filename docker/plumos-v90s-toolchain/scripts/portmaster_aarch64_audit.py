#!/usr/bin/env python3
"""Static PortMaster AArch64 compatibility audit for plumOS V90S."""

from __future__ import annotations

import argparse
import concurrent.futures
import csv
import hashlib
import json
import os
import re
import shutil
import stat
import struct
import subprocess
import sys
import tempfile
import urllib.request
import zipfile
from collections import Counter, defaultdict
from pathlib import Path, PurePosixPath
from typing import Any, Iterable


CATALOG_URL = (
    "https://github.com/PortsMaster/PortMaster-New/releases/latest/download/ports.json"
)
ELF_MAGIC = b"\x7fELF"
EM_NAMES = {3: "x86", 40: "armhf", 62: "x86_64", 183: "aarch64"}
SCRIPT_PATTERNS = {
    "armhf": re.compile(r"(?:PORT_32BIT\s*=\s*[Yy1]|\barmhf\b)"),
    "box64": re.compile(r"\bbox64\b", re.I),
    "box86": re.compile(r"\bbox86\b", re.I),
    "frt": re.compile(r"\bfrt[_ .-]?[0-9]|\bFRT\b"),
    "gl4es": re.compile(r"\bgl4es\b|LIBGL_", re.I),
    "godot": re.compile(r"\bgodot(?:[_ .-]|$)", re.I),
    "java": re.compile(r"\b(?:java|jdk|jre)[0-9_.-]*\b", re.I),
    "love": re.compile(r"\b(?:love|love2d)(?:[_ .-]|$)", re.I),
    "mono": re.compile(r"\bmono(?:[_ .-]|$)", re.I),
    "python": re.compile(r"\bpython(?:3|[_ .-]|$)", re.I),
    "renpy": re.compile(r"\brenpy\b", re.I),
    "weston": re.compile(r"\bweston(?:pack|wrap)?\b", re.I),
}


class AuditError(RuntimeError):
    pass


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def file_digest(path: Path, algorithm: str) -> str:
    digest = hashlib.new(algorithm)
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def is_library_name(name: str) -> bool:
    return bool(re.match(r"^lib[^/]*\.so(?:\..*)?$", name))


def has_foreign_arch_component(parts: Iterable[str]) -> bool:
    return any(
        re.search(r"(?:^|[._-])(?:armhf|x86|x86_64)(?:$|[._-])", part.lower())
        for part in parts
    )


def has_android_bionic_component(parts: Iterable[str]) -> bool:
    return any(part.lower() == "arm64-v8a" for part in parts)


def read_c_string(data: bytes, offset: int) -> str:
    if offset < 0 or offset >= len(data):
        return ""
    end = data.find(b"\0", offset)
    if end < 0:
        end = len(data)
    return data[offset:end].decode("utf-8", "replace")


def parse_elf(data: bytes) -> dict[str, Any] | None:
    """Parse the dynamic contract from a 32/64-bit little-endian ELF image."""
    if len(data) < 64 or data[:4] != ELF_MAGIC:
        return None
    elf_class = data[4]
    endian = data[5]
    if elf_class not in (1, 2) or endian != 1:
        return None
    prefix = "<"
    try:
        machine = struct.unpack_from(prefix + "H", data, 18)[0]
        if elf_class == 2:
            phoff = struct.unpack_from(prefix + "Q", data, 32)[0]
            phentsize = struct.unpack_from(prefix + "H", data, 54)[0]
            phnum = struct.unpack_from(prefix + "H", data, 56)[0]
            ph_format = prefix + "IIQQQQQQ"
            dyn_format = prefix + "qQ"
        else:
            phoff = struct.unpack_from(prefix + "I", data, 28)[0]
            phentsize = struct.unpack_from(prefix + "H", data, 42)[0]
            phnum = struct.unpack_from(prefix + "H", data, 44)[0]
            ph_format = prefix + "IIIIIIII"
            dyn_format = prefix + "iI"
    except struct.error:
        return None

    loads: list[tuple[int, int, int]] = []
    dynamic: tuple[int, int] | None = None
    interpreter = ""
    ph_size = struct.calcsize(ph_format)
    for index in range(phnum):
        offset = phoff + index * phentsize
        if offset < 0 or offset + ph_size > len(data):
            break
        fields = struct.unpack_from(ph_format, data, offset)
        if elf_class == 2:
            p_type, _, p_offset, p_vaddr, _, p_filesz, _, _ = fields
        else:
            p_type, p_offset, p_vaddr, _, p_filesz, _, _, _ = fields
        if p_type == 1:
            loads.append((p_vaddr, p_offset, p_filesz))
        elif p_type == 2:
            dynamic = (p_offset, p_filesz)
        elif p_type == 3 and p_offset + p_filesz <= len(data):
            interpreter = data[p_offset : p_offset + p_filesz].split(b"\0", 1)[0].decode(
                "utf-8", "replace"
            )

    def virtual_to_offset(address: int) -> int | None:
        for vaddr, offset, filesz in loads:
            if vaddr <= address < vaddr + filesz:
                return offset + address - vaddr
        return None

    tags: list[tuple[int, int]] = []
    if dynamic:
        dyn_offset, dyn_size = dynamic
        entry_size = struct.calcsize(dyn_format)
        limit = min(len(data), dyn_offset + dyn_size)
        cursor = dyn_offset
        while cursor + entry_size <= limit:
            tag, value = struct.unpack_from(dyn_format, data, cursor)
            cursor += entry_size
            if tag == 0:
                break
            tags.append((tag, value))

    strtab_address = next((value for tag, value in tags if tag == 5), None)
    strtab_offset = virtual_to_offset(strtab_address) if strtab_address is not None else None

    def dynamic_string(value: int) -> str:
        if strtab_offset is None:
            return ""
        return read_c_string(data, strtab_offset + value)

    needed = sorted(
        {dynamic_string(value) for tag, value in tags if tag == 1 and dynamic_string(value)}
    )
    soname = next(
        (dynamic_string(value) for tag, value in tags if tag == 14 and dynamic_string(value)),
        "",
    )
    rpath = next(
        (dynamic_string(value) for tag, value in tags if tag == 15 and dynamic_string(value)),
        "",
    )
    runpath = next(
        (dynamic_string(value) for tag, value in tags if tag == 29 and dynamic_string(value)),
        "",
    )
    return {
        "class": 64 if elf_class == 2 else 32,
        "machine": EM_NAMES.get(machine, f"elf-machine-{machine}"),
        "machine_id": machine,
        "interpreter": interpreter,
        "needed": needed,
        "soname": soname,
        "rpath": rpath,
        "runpath": runpath,
    }


def unwrap_catalog(document: dict[str, Any]) -> dict[str, dict[str, Any]]:
    ports = document.get("ports")
    if isinstance(ports, dict):
        return ports
    data = document.get("data")
    if isinstance(data, dict) and isinstance(data.get("info"), dict):
        return data["info"]
    raise AuditError("catalog does not contain a PortMaster ports mapping")


def is_aarch64_candidate(metadata: dict[str, Any]) -> bool:
    arch = metadata.get("attr", {}).get("arch") or []
    normalized = {str(item).lower() for item in arch}
    return not normalized or "aarch64" in normalized


def analyze_scripts(scripts: Iterable[str]) -> list[str]:
    text = "\n".join(scripts)
    return sorted(name for name, pattern in SCRIPT_PATTERNS.items() if pattern.search(text))


def safe_zip_member(name: str) -> bool:
    path = PurePosixPath(name)
    return not path.is_absolute() and ".." not in path.parts


def zip_member_is_symlink(entry: zipfile.ZipInfo) -> bool:
    return stat.S_ISLNK(entry.external_attr >> 16)


def audit_zip(path: Path) -> dict[str, Any]:
    scripts: list[str] = []
    binaries: list[dict[str, Any]] = []
    provided: set[str] = set()
    bionic_needed: set[str] = set()
    unsafe_entries: list[str] = []
    with zipfile.ZipFile(path) as archive:
        for entry in archive.infolist():
            if entry.is_dir():
                continue
            if not safe_zip_member(entry.filename):
                unsafe_entries.append(entry.filename)
                continue
            pure = PurePosixPath(entry.filename)
            foreign_arch = has_foreign_arch_component(pure.parts)
            basename = pure.name
            if zip_member_is_symlink(entry):
                if not foreign_arch and is_library_name(basename):
                    provided.add(basename)
                continue
            if pure.suffix.lower() == ".sh" and entry.file_size <= 2 * 1024 * 1024:
                scripts.append(archive.read(entry).decode("utf-8", "replace"))
                continue
            with archive.open(entry) as stream:
                if stream.read(4) != ELF_MAGIC:
                    if not foreign_arch and is_library_name(basename):
                        provided.add(basename)
                    continue
                payload = ELF_MAGIC + stream.read()
            elf = parse_elf(payload)
            if not elf:
                continue
            binary = {"path": entry.filename, **elf}
            binaries.append(binary)
            if elf["machine"] == "aarch64":
                if has_android_bionic_component(pure.parts):
                    bionic_needed.update(elf["needed"])
                if is_library_name(basename):
                    provided.add(basename)
                if elf["soname"]:
                    provided.add(elf["soname"])
    needed = sorted(
        {
            dependency
            for binary in binaries
            if binary["machine"] == "aarch64"
            and not has_android_bionic_component(PurePosixPath(binary["path"]).parts)
            for dependency in binary["needed"]
        }
    )
    machine_counts = Counter(binary["machine"] for binary in binaries)
    script_flags = set(analyze_scripts(scripts))
    if bionic_needed:
        script_flags.add("android-bionic")
    return {
        "bionic_needed": sorted(bionic_needed),
        "binaries": sorted(binaries, key=lambda item: item["path"]),
        "elf_machine_counts": dict(sorted(machine_counts.items())),
        "needed": needed,
        "provided": sorted(provided),
        "script_flags": sorted(script_flags),
        "script_count": len(scripts),
        "unsafe_entries": sorted(unsafe_entries),
    }


def scan_library_root(root: Path) -> set[str]:
    names: set[str] = set()
    if not root.exists():
        return names
    for current, dirs, files in os.walk(root):
        dirs[:] = [name for name in dirs if not has_foreign_arch_component([name])]
        for filename in files:
            if not is_library_name(filename):
                continue
            path = Path(current) / filename
            if path.is_symlink():
                names.add(filename)
                continue
            try:
                with path.open("rb") as stream:
                    if stream.read(4) != ELF_MAGIC:
                        names.add(filename)
                        continue
                    elf = parse_elf(ELF_MAGIC + stream.read())
            except OSError:
                continue
            if elf and elf["machine"] == "aarch64":
                names.add(filename)
                if elf["soname"]:
                    names.add(elf["soname"])
    return names


def scan_squashfs_names(path: Path) -> set[str]:
    if not path.is_file() or not shutil.which("unsquashfs"):
        return set()
    result = subprocess.run(
        ["unsquashfs", "-ll", str(path)],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
    )
    names: set[str] = set()
    for line in result.stdout.splitlines():
        for token in line.split():
            if "squashfs-root/" not in token:
                continue
            name = PurePosixPath(token.rstrip()).name
            if is_library_name(name):
                names.add(name)
            break
    return names


def load_source(source: str, cache_path: Path, offline: bool) -> tuple[bytes, str]:
    local = Path(source)
    if local.is_file():
        return local.read_bytes(), str(local.resolve())
    if not source.startswith(("https://", "http://")):
        raise AuditError(f"catalog does not exist: {source}")
    if offline:
        if not cache_path.is_file():
            raise AuditError(f"offline catalog cache is unavailable: {cache_path}")
        return cache_path.read_bytes(), source
    cache_path.parent.mkdir(parents=True, exist_ok=True)
    temporary = cache_path.with_suffix(cache_path.suffix + ".tmp")
    request = urllib.request.Request(source, headers={"User-Agent": "plumOS-V90S-audit/1"})
    with urllib.request.urlopen(request, timeout=60) as response, temporary.open("wb") as output:
        shutil.copyfileobj(response, output)
    temporary.replace(cache_path)
    return cache_path.read_bytes(), source


def validate_payload(path: Path, source: dict[str, Any]) -> bool:
    if not path.is_file():
        return False
    expected_size = int(source.get("size") or 0)
    expected_md5 = str(source.get("md5") or "").lower()
    if expected_size and path.stat().st_size != expected_size:
        return False
    if expected_md5 and file_digest(path, "md5") != expected_md5:
        return False
    try:
        return zipfile.is_zipfile(path)
    except OSError:
        return False


def download_payload(name: str, metadata: dict[str, Any], destination: Path) -> Path:
    source = metadata.get("source") or {}
    if validate_payload(destination, source):
        return destination
    url = source.get("url")
    if not url:
        raise AuditError(f"{name}: source URL is missing")
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_suffix(destination.suffix + ".part")
    temporary.unlink(missing_ok=True)
    request = urllib.request.Request(url, headers={"User-Agent": "plumOS-V90S-audit/1"})
    with urllib.request.urlopen(request, timeout=120) as response, temporary.open("wb") as output:
        shutil.copyfileobj(response, output, length=1024 * 1024)
    if not validate_payload(temporary, source):
        temporary.unlink(missing_ok=True)
        raise AuditError(f"{name}: downloaded payload failed size/MD5/ZIP validation")
    temporary.replace(destination)
    return destination


def find_payload(name: str, roots: Iterable[Path]) -> Path | None:
    for root in roots:
        candidate = root / name
        if candidate.is_file():
            return candidate
    return None


def runtime_status(runtimes: list[str], contract: dict[str, Any]) -> str:
    if not runtimes:
        return "not-required"
    unsupported = [re.compile(pattern, re.I) for pattern in contract["unsupported_runtime_patterns"]]
    if any(pattern.search(runtime) for runtime in runtimes for pattern in unsupported):
        return "unsupported"
    validated = set(contract["validated_runtimes"])
    if all(runtime in validated for runtime in runtimes):
        return "validated"
    return "unvalidated"


def classify_port(record: dict[str, Any]) -> str:
    if record["payload_status"] == "unavailable":
        return "payload-unavailable"
    if record["payload_status"] in {"error", "invalid"}:
        return "payload-" + record["payload_status"]
    if record["unsafe_entries"]:
        return "unsafe-archive"
    counts = record["elf_machine_counts"]
    if "armhf" in record["script_flags"] and not counts.get("aarch64"):
        return "unsupported-armhf"
    if record["missing_sonames"]:
        return "missing-libraries"
    if record["runtime_status"] == "unsupported":
        return "unsupported-runtime"
    if record["runtime_status"] == "unvalidated":
        return "runtime-unvalidated"
    if "android-bionic" in record["script_flags"]:
        return "runtime-unvalidated"
    if not counts.get("aarch64"):
        return "script-or-runtime-only"
    return "static-pass"


def write_tsv(path: Path, header: list[str], rows: Iterable[list[Any]]) -> None:
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.writer(stream, delimiter="\t", lineterminator="\n")
        writer.writerow(header)
        writer.writerows(rows)


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    root = Path(__file__).resolve().parents[3]
    parser = argparse.ArgumentParser(
        description="Audit every possible AArch64 PortMaster port without launching it."
    )
    parser.add_argument("--catalog", default=CATALOG_URL)
    parser.add_argument("--contract", type=Path, default=root / "docker/plumos-v90s-toolchain/portmaster-audit-contract.json")
    parser.add_argument("--output-dir", type=Path, default=root / "output/portmaster-audit/v90s")
    parser.add_argument("--cache-dir", type=Path, default=root / ".cache/portmaster-audit")
    parser.add_argument("--payload-dir", type=Path, action="append", default=[])
    parser.add_argument("--library-root", type=Path, action="append", default=[])
    parser.add_argument("--squashfs", type=Path, action="append", default=[])
    parser.add_argument("--port", action="append", default=[], help="Audit one ZIP name or stem; repeatable.")
    parser.add_argument("--download-payloads", action="store_true")
    parser.add_argument("--allow-large-download", action="store_true")
    parser.add_argument("--max-download-gib", type=float, default=2.0)
    parser.add_argument("--jobs", type=int, default=4)
    parser.add_argument("--offline", action="store_true")
    parser.add_argument("--allow-incomplete-contract", action="store_true")
    parser.add_argument("--fail-on-missing", action="store_true")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    root = Path(__file__).resolve().parents[3]
    contract = json.loads(args.contract.read_text(encoding="utf-8"))
    cache_catalog = args.cache_dir / "ports.json"
    catalog_bytes, catalog_source = load_source(args.catalog, cache_catalog, args.offline)
    catalog = json.loads(catalog_bytes)
    ports = unwrap_catalog(catalog)

    requested = {item if item.endswith(".zip") else item + ".zip" for item in args.port}
    selected = {
        name: metadata
        for name, metadata in ports.items()
        if is_aarch64_candidate(metadata) and (not requested or name in requested)
    }
    missing_requested = sorted(requested - set(selected))
    if missing_requested:
        raise AuditError("requested AArch64 candidates not found: " + ", ".join(missing_requested))

    payload_cache = args.cache_dir / "payloads"
    payload_roots = [payload_cache, *args.payload_dir]
    missing_downloads = [
        (name, metadata)
        for name, metadata in selected.items()
        if (
            (payload := find_payload(name, payload_roots)) is None
            or not validate_payload(payload, metadata.get("source") or {})
        )
    ]
    download_bytes = sum(int((metadata.get("source") or {}).get("size") or 0) for _, metadata in missing_downloads)
    if args.download_payloads and download_bytes > args.max_download_gib * 1024**3 and not args.allow_large_download:
        raise AuditError(
            f"payload download is {download_bytes / 1024**3:.2f} GiB; "
            "pass --allow-large-download after checking free space"
        )
    download_errors: dict[str, str] = {}
    if args.download_payloads and missing_downloads:
        with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, args.jobs)) as executor:
            futures = {
                executor.submit(download_payload, name, metadata, payload_cache / name): name
                for name, metadata in missing_downloads
            }
            for future in concurrent.futures.as_completed(futures):
                name = futures[future]
                try:
                    future.result()
                    print(f"downloaded: {name}", file=sys.stderr)
                except Exception as error:  # keep the complete audit running
                    download_errors[name] = str(error)
                    print(f"download failed: {name}: {error}", file=sys.stderr)

    default_library_roots = [
        root / "output/app-layer/v90s/lib",
        root / "output/app-layer/v90s/apps/nextcommander/lib",
        root / "output/portmaster/v90s/plumos/apps/portmaster/adapter/lib/aarch64",
        root / "output/portmaster/v90s/plumos/apps/portmaster/upstream/PortMaster/runtimes",
        root / "output/vendor/v90s-stockos-r1/root/usr/lib/powervr",
    ]
    missing_contract_inputs = [str(path) for path in default_library_roots if not path.exists()]
    library_roots = [path for path in [*default_library_roots, *args.library_root] if path.exists()]
    default_squashfs = root / "output/system-rootfs/v90s/plumos-v90s-system-rootfs.squashfs"
    if not default_squashfs.exists():
        missing_contract_inputs.append(str(default_squashfs))
    if missing_contract_inputs and not args.allow_incomplete_contract:
        raise AuditError(
            "target library contract inputs are missing; build vendor-runtime, portmaster, "
            "system-rootfs, and app-layer first, or pass --allow-incomplete-contract: "
            + ", ".join(missing_contract_inputs)
        )
    squashfs_paths = [path for path in ([default_squashfs] + args.squashfs) if path.exists()]
    target_sonames = set(contract["always_provided_sonames"])
    root_counts: dict[str, int] = {}
    for library_root in library_roots:
        names = scan_library_root(library_root)
        target_sonames.update(names)
        root_counts[str(library_root)] = len(names)
    for squashfs in squashfs_paths:
        names = scan_squashfs_names(squashfs)
        target_sonames.update(names)
        root_counts[str(squashfs)] = len(names)

    records: list[dict[str, Any]] = []
    missing_occurrences: dict[str, list[str]] = defaultdict(list)
    runtime_counts: Counter[str] = Counter()
    for name, metadata in sorted(selected.items()):
        attr = metadata.get("attr") or {}
        runtimes = [str(item) for item in (attr.get("runtime") or [])]
        for runtime in runtimes:
            runtime_counts[runtime] += 1
        payload = find_payload(name, payload_roots)
        payload_status = "unavailable"
        zip_audit = {
            "bionic_needed": [],
            "binaries": [],
            "elf_machine_counts": {},
            "needed": [],
            "provided": [],
            "script_flags": [],
            "script_count": 0,
            "unsafe_entries": [],
        }
        payload_error = download_errors.get(name, "")
        if payload:
            if validate_payload(payload, metadata.get("source") or {}):
                try:
                    zip_audit = audit_zip(payload)
                    payload_status = "audited"
                except (OSError, zipfile.BadZipFile, AuditError) as error:
                    payload_status = "error"
                    payload_error = str(error)
            else:
                payload_status = "invalid"
                payload_error = "payload failed size/MD5/ZIP validation"
        available = target_sonames | set(zip_audit["provided"])
        missing = sorted(set(zip_audit["needed"]) - available)
        for soname in missing:
            missing_occurrences[soname].append(name)
        source = metadata.get("source") or {}
        arch = [str(item) for item in (attr.get("arch") or [])]
        record = {
            "name": name,
            "title": str(attr.get("title") or name),
            "declared_arch": arch,
            "arch_declaration": "explicit" if arch else "undeclared",
            "ready_to_run": bool(attr.get("rtr")),
            "external_game_data_required": not bool(attr.get("rtr")),
            "requirements": [str(item) for item in (attr.get("reqs") or [])],
            "min_glibc": str(attr.get("min_glibc") or ""),
            "runtimes": runtimes,
            "runtime_status": runtime_status(runtimes, contract),
            "source": {
                "url": source.get("url", ""),
                "md5": source.get("md5", ""),
                "size": int(source.get("size") or 0),
                "date_updated": source.get("date_updated", ""),
            },
            "payload_status": payload_status,
            "payload_error": payload_error,
            "missing_sonames": missing,
            **zip_audit,
        }
        record["static_status"] = classify_port(record)
        records.append(record)

    protected_patterns = [re.compile(pattern) for pattern in contract["protected_soname_patterns"]]
    missing_rows = []
    for soname, names in sorted(missing_occurrences.items()):
        unique_names = sorted(set(names))
        if any(pattern.search(soname) for pattern in protected_patterns):
            classification = "target-contract-missing"
        elif len(unique_names) >= 2:
            classification = "common-abi-candidate"
        else:
            classification = "port-local-candidate"
        missing_rows.append(
            {
                "soname": soname,
                "classification": classification,
                "port_count": len(unique_names),
                "ports": unique_names,
            }
        )

    status_counts = Counter(record["static_status"] for record in records)
    args.output_dir.mkdir(parents=True, exist_ok=True)
    manifest = {
        "schema_version": 1,
        "target": contract["target"],
        "architecture": contract["architecture"],
        "catalog": {
            "source": catalog_source,
            "sha256": sha256_bytes(catalog_bytes),
            "total_ports": len(ports),
            "aarch64_candidates": len(selected),
            "selected_payload_bytes": sum(record["source"]["size"] for record in records),
        },
        "target_library_contract": {
            "contract_file": str(args.contract),
            "contract_sha256": file_digest(args.contract, "sha256"),
            "library_roots": root_counts,
            "missing_default_inputs": missing_contract_inputs,
            "soname_count": len(target_sonames),
        },
        "summary": {
            "payloads_audited": sum(record["payload_status"] == "audited" for record in records),
            "payloads_unavailable": sum(record["payload_status"] == "unavailable" for record in records),
            "missing_soname_count": len(missing_rows),
            "status_counts": dict(sorted(status_counts.items())),
        },
        "missing_libraries": missing_rows,
        "ports": records,
    }
    manifest_path = args.output_dir / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    write_tsv(
        args.output_dir / "summary.tsv",
        [
            "port", "title", "arch", "status", "payload", "runtime_status", "runtimes",
            "aarch64_elf", "armhf_elf", "missing_sonames", "script_flags", "external_data",
        ],
        (
            [
                record["name"], record["title"], ",".join(record["declared_arch"]) or "undeclared",
                record["static_status"], record["payload_status"], record["runtime_status"],
                ",".join(record["runtimes"]), record["elf_machine_counts"].get("aarch64", 0),
                record["elf_machine_counts"].get("armhf", 0), ",".join(record["missing_sonames"]),
                ",".join(record["script_flags"]), "yes" if record["external_game_data_required"] else "no",
            ]
            for record in records
        ),
    )
    write_tsv(
        args.output_dir / "missing-libraries.tsv",
        ["soname", "classification", "port_count", "ports"],
        ([row["soname"], row["classification"], row["port_count"], ",".join(row["ports"])] for row in missing_rows),
    )
    write_tsv(
        args.output_dir / "runtime-families.tsv",
        ["runtime", "validation_status", "port_count"],
        (
            [runtime, runtime_status([runtime], contract), count]
            for runtime, count in sorted(runtime_counts.items())
        ),
    )
    write_tsv(
        args.output_dir / "download-plan.tsv",
        ["port", "bytes", "url"],
        ([record["name"], record["source"]["size"], record["source"]["url"]] for record in records),
    )
    audit_manifest = args.output_dir / "portmaster-aarch64-audit.manifest"
    audit_manifest.write_text(
        "\n".join(
            [
                "component=portmaster-aarch64-audit",
                f"target={contract['target']}",
                f"catalog_sha256={sha256_bytes(catalog_bytes)}",
                f"catalog_ports={len(ports)}",
                f"aarch64_candidates={len(selected)}",
                f"payloads_audited={manifest['summary']['payloads_audited']}",
                f"selected_payload_bytes={manifest['catalog']['selected_payload_bytes']}",
                f"missing_sonames={len(missing_rows)}",
            ]
        )
        + "\n",
        encoding="utf-8",
    )
    checksum_path = args.output_dir / "checksums.sha256"
    checksum_lines = []
    for path in sorted(args.output_dir.iterdir()):
        if path.is_file() and path != checksum_path:
            checksum_lines.append(f"{file_digest(path, 'sha256')}  {path.name}")
    checksum_path.write_text("\n".join(checksum_lines) + "\n", encoding="ascii")

    print(f"created: {args.output_dir}")
    print(f"catalog ports: {len(ports)}")
    print(f"AArch64 candidates: {len(selected)}")
    print(f"payloads audited: {manifest['summary']['payloads_audited']}")
    print(f"payload download size: {manifest['catalog']['selected_payload_bytes'] / 1024**3:.2f} GiB")
    print(f"missing SONAMEs: {len(missing_rows)}")
    if args.fail_on_missing and missing_rows:
        return 3
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (AuditError, json.JSONDecodeError, OSError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1)

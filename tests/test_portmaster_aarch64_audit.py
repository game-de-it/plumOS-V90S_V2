import importlib.util
import json
import struct
import tempfile
import unittest
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "docker/plumos-v90s-toolchain/scripts/portmaster_aarch64_audit.py"
SPEC = importlib.util.spec_from_file_location("portmaster_aarch64_audit", MODULE_PATH)
AUDIT = importlib.util.module_from_spec(SPEC)
assert SPEC.loader
SPEC.loader.exec_module(AUDIT)


def make_elf(*, needed=(), soname="", machine=183):
    strings = bytearray(b"\0")
    offsets = {}
    for value in [*needed, soname]:
        if value and value not in offsets:
            offsets[value] = len(strings)
            strings.extend(value.encode("ascii") + b"\0")

    dynamic_entries = [(5, 0), (10, len(strings))]
    dynamic_entries.extend((1, offsets[value]) for value in needed)
    if soname:
        dynamic_entries.append((14, offsets[soname]))
    dynamic_entries.append((0, 0))

    header_size = 64
    ph_size = 56
    ph_count = 2
    dynamic_offset = header_size + ph_size * ph_count
    dynamic_size = 16 * len(dynamic_entries)
    string_offset = dynamic_offset + dynamic_size
    base = 0x400000
    dynamic_entries[0] = (5, base + string_offset)
    total_size = string_offset + len(strings)

    ident = b"\x7fELF" + bytes([2, 1, 1, 0]) + bytes(8)
    header = struct.pack(
        "<16sHHIQQQIHHHHHH",
        ident,
        3,
        machine,
        1,
        0,
        header_size,
        0,
        0,
        header_size,
        ph_size,
        ph_count,
        0,
        0,
        0,
    )
    load = struct.pack("<IIQQQQQQ", 1, 5, 0, base, base, total_size, total_size, 0x1000)
    dynamic = struct.pack(
        "<IIQQQQQQ",
        2,
        6,
        dynamic_offset,
        base + dynamic_offset,
        base + dynamic_offset,
        dynamic_size,
        dynamic_size,
        8,
    )
    tags = b"".join(struct.pack("<qQ", tag, value) for tag, value in dynamic_entries)
    return header + load + dynamic + tags + bytes(strings)


class ElfParserTests(unittest.TestCase):
    def test_dynamic_dependencies_and_soname(self):
        parsed = AUDIT.parse_elf(
            make_elf(needed=("libc.so.6", "libjpeg.so.8"), soname="libgame.so.1")
        )
        self.assertEqual(parsed["machine"], "aarch64")
        self.assertEqual(parsed["needed"], ["libc.so.6", "libjpeg.so.8"])
        self.assertEqual(parsed["soname"], "libgame.so.1")

    def test_zip_audit_resolves_aarch64_library_names(self):
        with tempfile.TemporaryDirectory() as temporary:
            archive_path = Path(temporary) / "sample.zip"
            with zipfile.ZipFile(archive_path, "w") as archive:
                archive.writestr(
                    "sample/game.aarch64",
                    make_elf(needed=("libprovided.so.1", "libmissing.so.8")),
                )
                archive.writestr(
                    "sample/libs.aarch64/libprovided.so.1",
                    make_elf(soname="libprovided.so.1"),
                )
                archive.writestr("Sample.sh", "PORT_32BIT=N\n$GAMEDIR/game.aarch64\n")
            result = AUDIT.audit_zip(archive_path)
        self.assertEqual(result["elf_machine_counts"], {"aarch64": 2})
        self.assertIn("libprovided.so.1", result["provided"])
        self.assertIn("libmissing.so.8", result["needed"])
        self.assertNotIn("armhf", result["script_flags"])


class CatalogTests(unittest.TestCase):
    def test_foreign_arch_path_components(self):
        self.assertTrue(AUDIT.has_foreign_arch_component(["libs.armhf"]))
        self.assertTrue(AUDIT.has_foreign_arch_component(["libs.x86_64"]))
        self.assertFalse(AUDIT.has_foreign_arch_component(["libs.aarch64"]))

    def test_direct_and_wrapped_catalogs(self):
        info = {"game.zip": {"attr": {"arch": ["aarch64"]}}}
        self.assertEqual(AUDIT.unwrap_catalog({"ports": info}), info)
        self.assertEqual(AUDIT.unwrap_catalog({"data": {"info": info}}), info)

    def test_undeclared_arch_is_kept_as_candidate(self):
        self.assertTrue(AUDIT.is_aarch64_candidate({"attr": {"arch": []}}))
        self.assertTrue(AUDIT.is_aarch64_candidate({"attr": {"arch": ["aarch64"]}}))
        self.assertFalse(AUDIT.is_aarch64_candidate({"attr": {"arch": ["armhf"]}}))

    def test_contract_is_valid_json(self):
        contract = json.loads(
            (ROOT / "docker/plumos-v90s-toolchain/portmaster-audit-contract.json").read_text()
        )
        self.assertEqual(contract["architecture"], "aarch64")
        self.assertIn("libc.so.6", contract["always_provided_sonames"])


if __name__ == "__main__":
    unittest.main()

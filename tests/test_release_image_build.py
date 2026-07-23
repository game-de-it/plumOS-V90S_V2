#!/usr/bin/env python3
import hashlib
import os
from pathlib import Path
import re
import subprocess
import tarfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
VENDOR = ROOT / "artifacts/vendor/v90s-stockos-r1"
LOCAL_BASELINE = ROOT / "artifacts/release-inputs/v90s-1.0.0"


class ReleaseImageBuildTests(unittest.TestCase):
    def run_release_image(self, *args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [str(ROOT / "scripts/docker-build.sh"), "release-image", *args],
            cwd=ROOT,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
            env={**os.environ, "PLUMOS_V90S_UPDATE_SIGNING_KEY": ""},
        )

    def test_image_only_graph_needs_no_signing_key(self) -> None:
        result = self.run_release_image("--version", "1.0.0", "--dry-run")
        self.assertEqual(result.returncode, 0, result.stderr)
        lines = result.stdout.splitlines()
        self.assertTrue(lines[0].startswith("release-image: "))
        self.assertIn("release-image: vendor-runtime", lines)
        self.assertIn("release-image: cores --filter all", lines)
        self.assertIn("release-image: app-layer --strict", lines)
        self.assertIn("release-image: verify-system-version 1.0.0", lines)
        self.assertFalse(any("userland" in line for line in lines))
        self.assertFalse(any("network-services" in line for line in lines))
        self.assertEqual(
            lines[-1],
            "release-image: sd-image --name plumos-v90s-release-1.0.0-vendor-r1.img",
        )
        self.assertFalse(any("update-package" in line for line in lines))

    def test_release_version_rejects_path_content(self) -> None:
        result = self.run_release_image("--version", "../1.0.0", "--dry-run")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unsafe release version", result.stderr)

        local_result = subprocess.run(
            [
                str(ROOT / "scripts/prepare-v90s-local-release-inputs.sh"),
                "--version",
                "../1.0.0",
            ],
            cwd=ROOT,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        self.assertNotEqual(local_result.returncode, 0)
        self.assertIn("unsafe release version", local_result.stderr)

    def test_vendor_checksum_manifest(self) -> None:
        entries = []
        for line in (VENDOR / "SHA256SUMS").read_text(encoding="ascii").splitlines():
            digest, relative = line.split(None, 1)
            path = VENDOR / relative.strip().removeprefix("./")
            entries.append(path)
            hasher = hashlib.sha256()
            with path.open("rb") as handle:
                for block in iter(lambda: handle.read(1024 * 1024), b""):
                    hasher.update(block)
            self.assertEqual(hasher.hexdigest(), digest, path)
        self.assertGreaterEqual(len(entries), 8)

    def test_local_baseline_checksum_manifest(self) -> None:
        self.assertEqual(
            (LOCAL_BASELINE / "VERSION").read_text(encoding="ascii").strip(),
            "1.0.0",
        )
        entries = []
        for line in (LOCAL_BASELINE / "SHA256SUMS").read_text(
            encoding="ascii"
        ).splitlines():
            digest, relative = line.split(None, 1)
            path = LOCAL_BASELINE / relative.strip().removeprefix("./")
            entries.append(path)
            self.assertLess(path.stat().st_size, 100_000_000, path)
            hasher = hashlib.sha256()
            with path.open("rb") as handle:
                for block in iter(lambda: handle.read(1024 * 1024), b""):
                    hasher.update(block)
            self.assertEqual(hasher.hexdigest(), digest, path)
        self.assertGreaterEqual(len(entries), 16)
        self.assertIn(
            LOCAL_BASELINE / "licenses/KNULLI-Buildroot-COPYING",
            entries,
        )
        self.assertIn(
            LOCAL_BASELINE / "licenses/GE8300-drivers-LICENSE",
            entries,
        )

    def test_vendor_config_has_no_active_captured_credentials(self) -> None:
        archive = VENDOR / "files/stockos-selected-files.tar.gz"
        patterns = [
            re.compile(r"^[\s#]*rootshadowpassword=.+$", re.MULTILINE),
            re.compile(r"^[\s#]*randomseed=.+$", re.MULTILINE),
            re.compile(r"^\s*wifi[0-9]*\.(?:ssid|key)=.+$", re.MULTILINE),
        ]
        members = [
            "./media/BATOCERA/batocera-boot.conf",
            "./media/BATOCERA/preinstall/batocera.conf",
        ]
        with tarfile.open(archive, "r:gz") as bundle:
            for member in members:
                extracted = bundle.extractfile(member)
                self.assertIsNotNone(extracted, member)
                text = extracted.read().decode("utf-8", errors="replace")
                for pattern in patterns:
                    self.assertIsNone(pattern.search(text), (member, pattern.pattern))

    def test_system_boot_loads_stockos_backlight_before_app_layer(self) -> None:
        script = (ROOT / "scripts/build-step1-rootfs.sh").read_text()
        runtime_start = script.index("mount -t sysfs sysfs /sys")
        load_call = script.index("\nload_v90s_backlight\n", runtime_start)
        app_layer = script.index("\nif prepare_plumos_app_layer; then", load_call)
        self.assertLess(runtime_start, load_call)
        self.assertLess(load_call, app_layer)
        self.assertIn("modprobe sunxi_backlight", script)
        self.assertIn(
            "module=/lib/modules/$(uname -r)/sunxi-backlight.ko",
            script,
        )
        self.assertIn('insmod "$module"', script)
        self.assertIn(
            "/sys/class/backlight/sunxi_backlight/brightness",
            script,
        )


if __name__ == "__main__":
    unittest.main()

#!/usr/bin/env python3
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
DISPLAY_CONTROL = (
    ROOT / "package/frontend-v90s/plumos/bin/plumos-display-control"
)


class DisplayControlTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.settings = self.root / "config/system/settings.json"
        self.settings.parent.mkdir(parents=True)
        self.settings.write_text(
            '{\n  "version": 1,\n  "brightness": 3,\n  "lumination": 5\n}\n'
        )
        self.runtime = self.root / "run/display/brightness"
        self.log = self.root / "run/display/last-apply.log"
        self.backlight = self.root / "sys/class/backlight/sunxi_backlight/brightness"
        self.backlight.parent.mkdir(parents=True)
        self.backlight.write_text("102\n")
        self.max_brightness = self.backlight.with_name("max_brightness")
        self.max_brightness.write_text("255\n")
        self.module = self.root / "lib/modules/4.9.191/sunxi-backlight.ko"
        self.module.parent.mkdir(parents=True)
        self.module.write_bytes(b"module")
        self.calls = self.root / "module-calls"
        self.modprobe = self.root / "bin/modprobe"
        self.insmod = self.root / "bin/insmod"
        self.modprobe.parent.mkdir()
        self.write_command(
            self.modprobe,
            f"printf 'modprobe %s\\n' \"$*\" >>'{self.calls}'\nexit 1\n",
        )
        self.write_command(
            self.insmod,
            f"printf 'insmod %s\\n' \"$*\" >>'{self.calls}'\nexit 1\n",
        )
        self.env = {
            **os.environ,
            "PLUMOS_ROOT": str(self.root),
            "PLUMOS_SYSTEM_SETTINGS_JSON": str(self.settings),
            "PLUMOS_DISPLAY_RUNTIME_STATE": str(self.runtime),
            "PLUMOS_DISPLAY_LOG": str(self.log),
            "PLUMOS_V90S_BACKLIGHT": str(self.backlight),
            "PLUMOS_V90S_MAX_BRIGHTNESS": str(self.max_brightness),
            "PLUMOS_V90S_KERNEL_RELEASE": "4.9.191",
            "PLUMOS_V90S_BACKLIGHT_MODULE": str(self.module),
            "PLUMOS_V90S_MODPROBE": str(self.modprobe),
            "PLUMOS_V90S_INSMOD": str(self.insmod),
        }

    @staticmethod
    def write_command(path: Path, body: str):
        path.write_text("#!/bin/sh\nset -eu\n" + body)
        path.chmod(0o755)

    def run_control(self, *args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [str(DISPLAY_CONTROL), *args],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
            env=self.env,
        )

    def assert_success(self, *args: str) -> subprocess.CompletedProcess[str]:
        result = self.run_control(*args)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result

    def test_six_levels_map_to_stockos_raw_values(self):
        expected = {1: 1, 2: 51, 3: 102, 4: 153, 5: 204, 6: 255}
        for level, raw in expected.items():
            with self.subTest(level=level):
                self.assert_success("apply", str(level))
                self.assertEqual(self.backlight.read_text().strip(), str(raw))
                log = self.log.read_text()
                self.assertIn(f"brightness={level}\n", log)
                self.assertIn(f"backlight_raw={raw}\n", log)
        self.assertFalse(self.calls.exists())

    def test_runtime_bounds_and_persistence_leave_lumination_separate(self):
        self.assert_success("runtime-up")
        self.assertEqual(self.runtime.read_text().strip(), "4")
        self.assertEqual(self.backlight.read_text().strip(), "153")
        for _ in range(10):
            self.assert_success("runtime-up")
        self.assertEqual(self.runtime.read_text().strip(), "6")
        self.assertEqual(self.backlight.read_text().strip(), "255")
        for _ in range(10):
            self.assert_success("runtime-down")
        self.assertEqual(self.runtime.read_text().strip(), "1")
        self.assertEqual(self.backlight.read_text().strip(), "1")

        self.runtime.write_text("2\n")
        self.assert_success("persist-runtime")
        saved = json.loads(self.settings.read_text())
        self.assertEqual(saved["brightness"], 2)
        self.assertEqual(saved["lumination"], 5)
        self.assertFalse(self.runtime.exists())
        self.assertEqual(self.backlight.read_text().strip(), "51")

    def test_legacy_brightness_above_six_migrates_to_six(self):
        self.settings.write_text(
            '{\n  "version": 1,\n  "brightness": 10,\n  "lumination": 5\n}\n'
        )
        result = self.assert_success("get")
        self.assertEqual(result.stdout.strip(), "6")
        saved = json.loads(self.settings.read_text())
        self.assertEqual(saved["brightness"], 6)
        self.assertEqual(saved["lumination"], 5)

    def test_existing_backend_skips_module_reload(self):
        result = self.assert_success("status")
        self.assertIn("backend=v90s-sunxi-backlight", result.stdout)
        self.assertIn("module_load=already-present", result.stdout)
        self.assertIn("max_brightness=255", result.stdout)
        self.assertFalse(self.calls.exists())

    def test_missing_backend_uses_modprobe_before_insmod(self):
        self.backlight.unlink()
        self.write_command(
            self.modprobe,
            (
                f"printf 'modprobe %s\\n' \"$*\" >>'{self.calls}'\n"
                'printf "255\\n" >"$PLUMOS_V90S_BACKLIGHT"\n'
            ),
        )
        result = self.assert_success("status")
        self.assertIn("module_load=modprobe-ok", result.stdout)
        self.assertEqual(self.calls.read_text().splitlines(), ["modprobe sunxi_backlight"])


if __name__ == "__main__":
    unittest.main()

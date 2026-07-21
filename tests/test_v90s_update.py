#!/usr/bin/env python3
from __future__ import annotations

import errno
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest import mock


REPO = Path(__file__).resolve().parents[1]
BUILDER = REPO / "scripts/build-v90s-update-package.py"
UPDATER = REPO / "scripts/plumos-system-update.py"


def load_updater_module():
    spec = importlib.util.spec_from_file_location("plumos_system_update", UPDATER)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load updater module: {UPDATER}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class V90SUpdateTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="plumos-v90s-update-test-")
        self.root = Path(self.temp.name)
        self.live = self.root / "plumos"
        self.user = self.root / "user"
        self.boot = self.root / "boot"
        self.system_abi = self.root / "system-abi"
        self.system_version = self.root / "system-version"
        self.private_key = self.root / "private.pem"
        self.public_key = self.root / "public.pem"
        subprocess.run(
            ["openssl", "genpkey", "-algorithm", "ED25519", "-out", str(self.private_key)],
            check=True,
        )
        subprocess.run(
            ["openssl", "pkey", "-in", str(self.private_key), "-pubout",
             "-out", str(self.public_key)],
            check=True,
        )
        (self.user / "updates").mkdir(parents=True)
        (self.boot / "System").mkdir(parents=True)
        self.system_abi.write_text("1\n", encoding="ascii")
        self.system_version.write_text("system-1\n", encoding="ascii")
        self.env = {
            **os.environ,
            "PLUMOS_ROOT": str(self.live),
            "PLUMOS_USERDATA_ROOT": str(self.user),
            "PLUMOS_BOOT_ROOT": str(self.boot),
            "PLUMOS_SYSTEM_ABI_FILE": str(self.system_abi),
            "PLUMOS_SYSTEM_VERSION_FILE": str(self.system_version),
            "PLUMOS_UPDATE_PUBLIC_KEY": str(self.public_key),
            "PLUMOS_UPDATE_LOCK_FILE": str(self.root / "update.lock"),
            "PLUMOS_UPDATE_BOOT_REMOUNT": "0",
            "PLUMOS_UPDATE_PROGRESS": "0",
        }

    def tearDown(self) -> None:
        self.temp.cleanup()

    def seed_runtime(self, version: str, tool: str) -> None:
        (self.live / "bin").mkdir(parents=True, exist_ok=True)
        (self.live / "config/frontend").mkdir(parents=True, exist_ok=True)
        (self.live / "VERSION").write_text(f"{version}\n", encoding="ascii")
        (self.live / "COMPAT_VENDOR").write_text("v90s-stockos-r1\n", encoding="ascii")
        (self.live / "RUNTIME_ABI").write_text("1\n", encoding="ascii")
        (self.live / "bin/tool").write_text(tool, encoding="ascii")
        (self.live / "config/user-choice.cfg").parent.mkdir(parents=True, exist_ok=True)
        (self.live / "config/user-choice.cfg").write_text("keep-me\n", encoding="ascii")

    def runtime_source(self, version: str, tool: str) -> Path:
        source = self.root / f"runtime-{version}"
        shutil.copytree(self.live, source)
        (source / "VERSION").write_text(f"{version}\n", encoding="ascii")
        (source / "bin/tool").write_text(tool, encoding="ascii")
        (source / "config/user-choice.cfg").write_text(
            "must-not-be-packaged\n", encoding="ascii"
        )
        return source

    def build_runtime(self, source: Path, version: str, base_version: str) -> Path:
        subprocess.run(
            [
                str(BUILDER), "--type", "runtime", "--input", str(source),
                "--version", version, "--base-version", base_version,
                "--signing-key", str(self.private_key), "--output-dir", str(self.user / "updates"),
            ],
            cwd=REPO,
            check=True,
            stdout=subprocess.DEVNULL,
        )
        return self.user / "updates" / f"plumos-v90s-runtime-{version}.tar.gz"

    def update(self, *args: str, expected: int = 0) -> subprocess.CompletedProcess[str]:
        result = subprocess.run(
            [str(UPDATER), *args],
            env=self.env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        self.assertEqual(result.returncode, expected, result.stderr)
        return result

    def test_runtime_retains_one_backup_and_rolls_back_unhealthy_update(self) -> None:
        self.seed_runtime("runtime-1", "one\n")

        package2 = self.build_runtime(self.runtime_source("runtime-2", "two\n"),
                                      "runtime-2", "runtime-1")
        self.update("request", str(package2))
        self.update("apply-pending")
        self.assertEqual((self.live / "bin/tool").read_text(), "two\n")
        self.assertEqual((self.live / "config/user-choice.cfg").read_text(), "keep-me\n")
        self.update("mark-healthy")
        self.assertEqual((self.live / "backups/update-previous/files/bin/tool").read_text(),
                         "one\n")

        package3 = self.build_runtime(self.runtime_source("runtime-3", "three\n"),
                                      "runtime-3", "runtime-2")
        self.update("request", str(package3))
        self.update("apply-pending")
        self.update("mark-healthy")
        self.assertEqual((self.live / "backups/update-previous/files/bin/tool").read_text(),
                         "two\n")
        self.assertEqual(len(list((self.live / "backups").iterdir())), 1)

        package4 = self.build_runtime(self.runtime_source("runtime-4", "four\n"),
                                      "runtime-4", "runtime-3")
        self.update("request", str(package4))
        self.update("apply-pending")
        self.assertEqual((self.live / "bin/tool").read_text(), "four\n")
        self.update("apply-pending")
        self.assertEqual((self.live / "bin/tool").read_text(), "three\n")
        result = json.loads((self.live / "update-state/last-result.json").read_text())
        self.assertEqual(result["result"], "rolled_back")

    def test_system_writes_only_inactive_slot_and_promotes_after_health(self) -> None:
        self.seed_runtime("runtime-1", "one\n")
        (self.boot / "System/active-slot").write_text("a\n", encoding="ascii")
        (self.boot / "System/system-a.squashfs").write_bytes(b"active-system")
        (self.boot / "System/system-b.squashfs").write_bytes(b"old-inactive")
        (self.live / "update-state").mkdir(parents=True)
        (self.live / "update-state/system-active").write_text("a\n", encoding="ascii")
        source = self.root / "system-2.squashfs"
        source.write_bytes(b"new-system-squashfs")
        subprocess.run(
            [
                str(BUILDER), "--type", "system", "--input", str(source),
                "--version", "system-2", "--base-version", "system-1",
                "--signing-key", str(self.private_key), "--output-dir", str(self.user / "updates"),
            ],
            cwd=REPO,
            env={**os.environ, "PLUMOS_UPDATE_SKIP_EMBEDDED_CHECK": "1"},
            check=True,
            stdout=subprocess.DEVNULL,
        )
        package = self.user / "updates/plumos-v90s-system-system-2.tar.gz"
        self.update("request", str(package))
        self.update("apply-pending", expected=20)
        self.assertEqual((self.boot / "System/system-a.squashfs").read_bytes(),
                         b"active-system")
        self.assertEqual((self.boot / "System/system-b.squashfs").read_bytes(),
                         b"new-system-squashfs")
        self.assertEqual((self.live / "update-state/system-pending").read_text(), "b\n")
        self.update("mark-healthy")
        self.assertEqual((self.live / "update-state/system-active").read_text(), "b\n")
        self.assertFalse((self.live / "update-state/system-pending").exists())

    def test_interrupted_runtime_journal_restores_old_and_removes_new_files(self) -> None:
        self.seed_runtime("runtime-1", "one\n")
        backup = self.live / "backups/update-previous/files/bin/tool"
        backup.parent.mkdir(parents=True)
        os.replace(self.live / "bin/tool", backup)
        (self.live / "bin/tool").write_text("partial-two\n", encoding="ascii")
        (self.live / "bin/new-tool").write_text("partial-new\n", encoding="ascii")
        state = self.live / "update-state"
        state.mkdir(parents=True)
        (state / "runtime-transaction.json").write_text(
            json.dumps({
                "status": "applying",
                "operations": [
                    {
                        "path": "bin/tool",
                        "existed": True,
                        "install_requested": True,
                        "installed": False,
                    },
                    {
                        "path": "bin/new-tool",
                        "existed": False,
                        "install_requested": True,
                        "installed": False,
                    },
                ],
            }),
            encoding="utf-8",
        )

        self.update("apply-pending")

        self.assertEqual((self.live / "bin/tool").read_text(), "one\n")
        self.assertFalse((self.live / "bin/new-tool").exists())
        result = json.loads((state / "last-result.json").read_text())
        self.assertEqual(result["result"], "rolled_back")

    def test_vendor_vfat_fsync_fallback_is_narrow(self) -> None:
        updater = load_updater_module()
        with mock.patch.object(updater.os, "fsync", side_effect=OSError(0, "Error")), \
             mock.patch.object(updater.os, "sync") as sync:
            updater.fsync_file_descriptor(1)
            sync.assert_called_once_with()

        with mock.patch.object(
            updater.os, "fsync", side_effect=OSError(errno.EIO, "I/O error")
        ), mock.patch.object(updater.os, "sync") as sync:
            with self.assertRaises(OSError):
                updater.fsync_file_descriptor(1)
            sync.assert_not_called()


if __name__ == "__main__":
    unittest.main()

#!/usr/bin/env python3
"""Tests for bounded PortMaster updater cleanup."""

from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = (
    ROOT
    / "package/portmaster-v90s/plumos/apps/portmaster/adapter"
    / "plumos_portmaster_update.py"
)


def load_updater():
    spec = importlib.util.spec_from_file_location("plumos_portmaster_update", MODULE_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load updater: {MODULE_PATH}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class CleanupStaleUpdatePathsTest(unittest.TestCase):
    def test_removes_only_owned_temporary_children(self) -> None:
        updater = load_updater()
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp) / "portmaster"
            external = Path(temp) / "external"
            root.mkdir()
            external.mkdir()

            keep = ("upstream", "upstream.previous", "state", "upstream.next")
            stale = ("portmaster-download-old", "upstream.next.1234")
            for name in keep + stale:
                (root / name).mkdir()
            (root / "portmaster-download-link").symlink_to(external, target_is_directory=True)

            updater.APP_ROOT = root
            removed = updater.cleanup_stale_update_paths()

            self.assertEqual(
                removed,
                ["portmaster-download-link", "portmaster-download-old", "upstream.next.1234"],
            )
            for name in keep:
                self.assertTrue((root / name).is_dir(), name)
            for name in stale:
                self.assertFalse((root / name).exists(), name)
            self.assertFalse((root / "portmaster-download-link").exists())
            self.assertTrue(external.is_dir())


if __name__ == "__main__":
    unittest.main()

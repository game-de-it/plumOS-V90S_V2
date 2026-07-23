import hashlib
import importlib.util
import json
import pathlib
import tempfile
import unittest
from unittest import mock


REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
MODULE_PATH = REPO_ROOT / "scripts" / "v90s_release_component_cache.py"
SPEC = importlib.util.spec_from_file_location("v90s_release_component_cache", MODULE_PATH)
CACHE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CACHE)


class ReleaseComponentCacheTests(unittest.TestCase):
    def make_root(self):
        temporary = tempfile.TemporaryDirectory()
        root = pathlib.Path(temporary.name)
        input_file = root / "docker/plumos-v90s-toolchain/scripts/build-picoarch.sh"
        input_file.parent.mkdir(parents=True)
        input_file.write_text("build-v1\n")
        (root / "scripts").mkdir()
        (root / "scripts/docker-build.sh").write_text("docker-v1\n")
        dockerfile = root / "docker/plumos-v90s-toolchain/Dockerfile"
        dockerfile.write_text("FROM test\n")
        package = root / "package/picoarch-v90s/bin/launch"
        package.parent.mkdir(parents=True)
        package.write_text("launch-v1\n")

        output = root / "output/picoarch/v90s"
        output.mkdir(parents=True)
        payload = output / "bin/picoarch"
        payload.parent.mkdir()
        payload.write_bytes(b"picoarch")
        manifest = output / "picoarch.manifest"
        manifest.write_text("name=test\n")
        checksums = output / "checksums.sha256"
        checksums.write_text(
            f"{hashlib.sha256(payload.read_bytes()).hexdigest()}  bin/picoarch\n"
            f"{hashlib.sha256(manifest.read_bytes()).hexdigest()}  picoarch.manifest\n"
        )
        return temporary, root

    def test_record_and_check_detect_input_change(self):
        temporary, root = self.make_root()
        self.addCleanup(temporary.cleanup)
        with mock.patch.dict(CACHE.os.environ, {}, clear=True):
            CACHE.record(root, "picoarch", "1.0.0")
            self.assertTrue(CACHE.check(root, "picoarch", "1.0.0"))
            (root / "package/picoarch-v90s/bin/launch").write_text("launch-v2\n")
            self.assertFalse(CACHE.check(root, "picoarch", "1.0.0"))

    def test_output_corruption_invalidates_cache(self):
        temporary, root = self.make_root()
        self.addCleanup(temporary.cleanup)
        with mock.patch.dict(CACHE.os.environ, {}, clear=True):
            CACHE.record(root, "picoarch", "1.0.0")
            (root / "output/picoarch/v90s/bin/picoarch").write_bytes(b"broken")
            self.assertFalse(CACHE.check(root, "picoarch", "1.0.0"))

    def test_stamp_contains_only_hashes_not_environment_values(self):
        temporary, root = self.make_root()
        self.addCleanup(temporary.cleanup)
        with mock.patch.dict(
            CACHE.os.environ,
            {"PLUMOS_V90S_PICOARCH_TEST": "sensitive-test-value"},
            clear=True,
        ):
            CACHE.record(root, "picoarch", "1.0.0")
        stamp = CACHE.stamp_path(root, "picoarch")
        parsed = json.loads(stamp.read_text())
        self.assertEqual(parsed["format"], CACHE.CACHE_FORMAT)
        self.assertNotIn("sensitive-test-value", stamp.read_text())


if __name__ == "__main__":
    unittest.main()

import hashlib
import os
import pathlib
import stat
import subprocess
import tempfile
import unittest


REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
FRT_WRAPPER = (
    REPO_ROOT
    / "package"
    / "portmaster-v90s"
    / "plumos"
    / "bin"
    / "plumos-portmaster-frt"
)
MOUNT_SHIM = (
    REPO_ROOT
    / "package"
    / "portmaster-v90s"
    / "plumos"
    / "apps"
    / "portmaster"
    / "adapter"
    / "shims"
    / "mount"
)


def make_executable(path: pathlib.Path, body: str):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(body)
    path.chmod(path.stat().st_mode | stat.S_IXUSR)


class FrtHandoffTests(unittest.TestCase):
    def make_runtime_environment(self, temp_root: pathlib.Path):
        plumos_root = temp_root / "plumos"
        run_root = temp_root / "run"
        input_root = temp_root / "sys" / "class" / "input"
        real = (
            plumos_root
            / "state"
            / "portmaster"
            / "runtime-cache"
            / "frt_3.5.2.squashfs.digest"
            / "frt_3.5.2"
        )
        make_executable(real, "#!/bin/sh\nprintf 'real:%s\\n' \"$*\"\n")
        run_root.mkdir(parents=True)
        (run_root / "frt-real.path").write_text(f"{real}\n")
        env = {
            **os.environ,
            "PLUMOS_ROOT": str(plumos_root),
            "PLUMOS_PORTMASTER_RUN_ROOT": str(run_root),
            "PLUMOS_PORTMASTER_INPUT_SYS_ROOT": str(input_root),
            "PLUMOS_PORTMASTER_FRT_INPUT_WAIT_ATTEMPTS": "2",
            "PLUMOS_PORTMASTER_FRT_INPUT_WAIT_INTERVAL": "0.01",
        }
        return env, input_root

    def test_runtime_starts_after_fake_keyboard_exists(self):
        with tempfile.TemporaryDirectory() as temp:
            env, input_root = self.make_runtime_environment(pathlib.Path(temp))
            device = input_root / "event5" / "device"
            device.mkdir(parents=True)
            (device / "name").write_text("Fake Keyboard\n")

            result = subprocess.run(
                [str(FRT_WRAPPER), "--resolution", "640x480"],
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("FRT input handoff: Fake Keyboard ready", result.stderr)
            self.assertIn("real:--resolution 640x480", result.stdout)

    def test_runtime_timeout_keeps_fallback(self):
        with tempfile.TemporaryDirectory() as temp:
            env, _ = self.make_runtime_environment(pathlib.Path(temp))

            result = subprocess.run(
                [str(FRT_WRAPPER), "--main-pack", "game.pck"],
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("handoff timed out", result.stderr)
            self.assertIn("real:--main-pack game.pck", result.stdout)

    def test_mount_shim_layers_wrapper_without_changing_runtime_cache(self):
        with tempfile.TemporaryDirectory() as temp:
            temp_root = pathlib.Path(temp)
            plumos_root = temp_root / "plumos"
            app_root = plumos_root / "apps" / "portmaster"
            state_root = plumos_root / "state" / "portmaster"
            run_root = temp_root / "run"
            source = app_root / "upstream" / "PortMaster" / "libs" / "frt_3.5.2.squashfs"
            target = state_root / "home" / "godot"
            source.parent.mkdir(parents=True)
            source.write_bytes(b"runtime-image")
            digest = hashlib.sha256(source.read_bytes()).hexdigest()
            cache = state_root / "runtime-cache" / f"{source.name}.{digest}"
            make_executable(cache / "frt_3.5.2", "#!/bin/sh\nexit 0\n")
            (cache / ".plumos-runtime-ready").write_text(f"{digest}\n")
            make_executable(
                plumos_root / "bin" / "plumos-portmaster-frt",
                "#!/bin/sh\nexit 0\n",
            )
            make_executable(
                app_root / "adapter" / "bin" / "aarch64" / "unsquashfs",
                "#!/bin/sh\nexit 1\n",
            )
            mount_log = temp_root / "mount.log"
            fake_mount = temp_root / "mount"
            make_executable(
                fake_mount,
                f"#!/bin/sh\nprintf '%s\\n' \"$*\" >> '{mount_log}'\n",
            )
            mounts_file = run_root / "port.mounts"
            run_root.mkdir(parents=True)
            env = {
                **os.environ,
                "PLUMOS_ROOT": str(plumos_root),
                "PLUMOS_PORTMASTER_APP_ROOT": str(app_root),
                "PLUMOS_PORTMASTER_RUN_ROOT": str(run_root),
                "PLUMOS_PORTMASTER_MOUNTS_FILE": str(mounts_file),
                "PLUMOS_PORTMASTER_MOUNT_BIN": str(fake_mount),
                "PLUMOS_PORTMASTER_UMOUNT_BIN": str(fake_mount),
            }

            result = subprocess.run(
                [str(MOUNT_SHIM), str(source), str(target)],
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((run_root / "frt-real.path").read_text(), f"{cache / 'frt_3.5.2'}\n")
            self.assertEqual(
                mounts_file.read_text().splitlines(),
                [str(target), str(target / "frt_3.5.2")],
            )
            calls = mount_log.read_text().splitlines()
            self.assertEqual(calls[0], f"--bind {cache} {target}")
            self.assertEqual(
                calls[1],
                f"--bind {plumos_root / 'bin' / 'plumos-portmaster-frt'} "
                f"{target / 'frt_3.5.2'}",
            )


if __name__ == "__main__":
    unittest.main()

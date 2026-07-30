#!/usr/bin/env python3
import os
from pathlib import Path
import subprocess
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parents[1]
NETWORK_CONTROL = (
    ROOT / "package/network-services/plumos/bin/plumos-network-control"
)
WIFI_UEVENT = ROOT / "package/network-services/plumos/bin/plumos-wifi-uevent"
WIFI_RECOVERY = (
    ROOT / "package/network-services/plumos/bin/plumos-wifi-recovery"
)


class NetworkControlModeSwitchTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.plumos = self.root / "plumos"
        self.run = self.root / "run"
        self.usb = self.root / "sys/bus/usb/devices"
        self.net = self.root / "sys/class/net"
        self.dev = self.root / "dev"
        self.modules = self.root / "lib/modules/4.9.191"
        for directory in (
            self.plumos / "bin",
            self.run,
            self.usb,
            self.net,
            self.dev,
            self.modules / "extra",
        ):
            directory.mkdir(parents=True, exist_ok=True)
        (self.modules / "modules.alias").write_text(
            "alias usb:v0BDApC811d*dc*dsc*dp*icFFiscFFipFFin* 8821cu\n"
        )
        (self.modules / "extra/8821cu.ko").write_bytes(b"module")
        self.calls = self.root / "calls.log"
        self.eject = self.plumos / "bin/eject"
        self.insmod = self.plumos / "bin/insmod"
        self.write_command(
            self.eject,
            (
                f"printf 'eject %s\\n' \"$*\" >>'{self.calls}'\n"
                f"printf 'c811\\n' >'{self.usb / '1-1/idProduct'}'\n"
            ),
        )
        self.write_command(
            self.insmod,
            (
                f"printf 'insmod %s\\n' \"$*\" >>'{self.calls}'\n"
                f"mkdir -p '{self.net / 'wlan0/wireless'}'\n"
            ),
        )
        self.env = {
            **os.environ,
            "PLUMOS_ROOT": str(self.plumos),
            "PLUMOS_RUNTIME_ROOT": str(self.run),
            "PLUMOS_USB_SYSFS_ROOT": str(self.usb),
            "PLUMOS_NET_SYSFS_ROOT": str(self.net),
            "PLUMOS_DEV_ROOT": str(self.dev),
            "PLUMOS_MODULES_DIR": str(self.modules),
            "PLUMOS_ALT_MODULES_DIR": str(self.modules),
            "PLUMOS_USB_MODE_SWITCH_WAIT_ATTEMPTS": "1",
            "PLUMOS_EJECT_BIN": str(self.eject),
        }

    @staticmethod
    def write_command(path: Path, body: str):
        path.write_text("#!/bin/sh\nset -eu\n" + body)
        path.chmod(0o755)

    def add_usb_device(self, product: str):
        device = self.usb / "1-1"
        interface = self.usb / "1-1:1.0"
        block = interface / "host0/target0:0:0/0:0:0:0/block/sr0"
        device.mkdir()
        block.mkdir(parents=True)
        (device / "idVendor").write_text("0bda\n")
        (device / "idProduct").write_text(f"{product}\n")
        (device / "product").write_text("DISK\n")
        (self.dev / "sr0").write_bytes(b"")

    def run_control(self, *args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [str(NETWORK_CONTROL), *args],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
            env=self.env,
        )

    def test_realtek_storage_mode_switches_before_driver_detection(self):
        self.add_usb_device("1a2b")

        result = self.run_control("--wifi", "on")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("result=ready", result.stdout)
        self.assertIn("iface=wlan0", result.stdout)
        self.assertEqual(
            self.calls.read_text().splitlines(),
            [
                f"eject -s {self.dev / 'sr0'}",
                f"insmod {self.modules / 'extra/8821cu.ko'}",
            ],
        )
        log = (self.plumos / "Logs/network-control.log").read_text()
        self.assertIn("usb wifi mode-switch detected id=0bda:1a2b", log)
        self.assertIn("usb wifi mode-switch complete id=0bda:c811", log)
        self.assertIn("usb wifi driver candidates=8821cu", log)

    def test_c811_is_idempotent_and_does_not_eject(self):
        self.add_usb_device("c811")

        result = self.run_control("--wifi", "on")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("eject ", self.calls.read_text())
        self.assertIn("insmod ", self.calls.read_text())

    def test_unrelated_storage_device_is_not_ejected(self):
        self.add_usb_device("1a2c")

        result = self.run_control("--wifi", "on")

        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.calls.exists())


class WifiUeventModeSwitchTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.calls = self.root / "recovery.log"
        recovery = self.root / "bin/plumos-wifi-recovery"
        recovery.parent.mkdir(parents=True)
        recovery.write_text(
            "#!/bin/sh\n"
            f"printf '%s\\n' \"$*\" >>'{self.calls}'\n"
        )
        recovery.chmod(0o755)

    def run_event(self, **event: str) -> subprocess.CompletedProcess[str]:
        env = {
            **os.environ,
            "PLUMOS_ROOT": str(self.root),
            "ACTION": "add",
            **event,
        }
        return subprocess.run(
            ["/bin/sh", str(WIFI_UEVENT)],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
            env=env,
        )

    def test_realtek_storage_usb_add_requests_bounded_recovery(self):
        result = self.run_event(SUBSYSTEM="usb", PRODUCT="bda/1a2b/200")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls.read_text().strip(), "recover")

    def test_wireless_net_add_remains_supported(self):
        result = self.run_event(SUBSYSTEM="net", INTERFACE="wlan0")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls.read_text().strip(), "recover")

    def test_unrelated_usb_add_is_ignored(self):
        result = self.run_event(SUBSYSTEM="usb", PRODUCT="1234/5678/100")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.calls.exists())


class WifiRecoveryColdBootTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.plumos = self.root / "plumos"
        self.run = self.root / "run"
        self.proc = self.root / "proc"
        self.calls = self.root / "network-control.log"
        for directory in (
            self.plumos / "bin",
            self.plumos / "config/system",
            self.run / "wifi-recovery",
            self.proc,
        ):
            directory.mkdir(parents=True, exist_ok=True)

        self.network_control = self.plumos / "bin/plumos-network-control"
        self.network_control.write_text(
            "#!/bin/sh\n"
            f"printf '%s\\n' \"$*\" >>'{self.calls}'\n"
        )
        self.network_control.chmod(0o755)
        (self.plumos / "bin/plumos-wifi-uevent").write_text("#!/bin/sh\n")
        (self.plumos / "bin/plumos-wifi-uevent").chmod(0o755)
        (self.plumos / "bin/busybox").write_text("#!/bin/sh\n")
        (self.plumos / "bin/busybox").chmod(0o755)

        self.monitor = subprocess.Popen(["sleep", "30"])
        self.addCleanup(self.stop_monitor)
        monitor_proc = self.proc / str(self.monitor.pid)
        monitor_proc.mkdir()
        monitor_proc.joinpath("cmdline").write_bytes(
            str(self.plumos / "bin/busybox").encode()
            + b"\0uevent\0"
            + str(self.plumos / "bin/plumos-wifi-uevent").encode()
            + b"\0"
        )
        (self.run / "wifi-recovery/uevent.pid").write_text(
            f"{self.monitor.pid}\n"
        )
        self.env = {
            **os.environ,
            "PLUMOS_ROOT": str(self.plumos),
            "PLUMOS_RUNTIME_ROOT": str(self.run),
            "PLUMOS_PROC_ROOT": str(self.proc),
            "PLUMOS_WIFI_RECOVERY_SETTLE_SECONDS": "0",
        }

    def stop_monitor(self):
        if self.monitor.poll() is None:
            self.monitor.terminate()
            self.monitor.wait(timeout=5)

    def write_wifi_setting(self, enabled: bool):
        value = "true" if enabled else "false"
        (self.plumos / "config/system/settings.json").write_text(
            f'{{"wifi_enabled": {value}}}\n'
        )

    def wait_for_calls(self):
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            if self.calls.exists() and self.calls.read_text().strip():
                return
            time.sleep(0.05)
        log = self.plumos / "Logs/wifi-recovery.log"
        detail = log.read_text() if log.exists() else "log missing"
        self.fail(f"initial Wi-Fi recovery did not run:\n{detail}")

    def test_sync_schedules_initial_recovery_for_saved_on_state(self):
        self.write_wifi_setting(True)

        result = subprocess.run(
            ["/bin/sh", str(WIFI_RECOVERY), "sync"],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
            env=self.env,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.wait_for_calls()
        self.assertEqual(self.calls.read_text().strip(), "--wifi on")
        log = (self.plumos / "Logs/wifi-recovery.log").read_text()
        self.assertIn("initial_recovery_scheduled", log)
        self.assertIn("recover_begin", log)
        self.assertIn("recover_complete", log)

    def test_sync_does_not_recover_for_saved_off_state(self):
        self.write_wifi_setting(False)

        result = subprocess.run(
            ["/bin/sh", str(WIFI_RECOVERY), "sync"],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
            env=self.env,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        time.sleep(0.1)
        self.assertFalse(self.calls.exists())


if __name__ == "__main__":
    unittest.main()

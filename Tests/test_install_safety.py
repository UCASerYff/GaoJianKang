#!/usr/bin/env python3
"""Filesystem transaction tests. Never call codesign, registration tools, or GUI.

Fake apps exist only inside a temporary .noindex root. Their fake signing data
does not prove production signatures or desktop/Spotlight registration.
"""
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import shutil
import stat
import struct
import tempfile
import unittest
import zipfile


SPEC = importlib.util.spec_from_file_location("health_install_safety", Path(__file__).resolve().parents[1] / "scripts/install_safety.py")
install = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(install)


def write_plist(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(plistlib.dumps(value))


def make_app(path, version, build, marker):
    components = [
        (path, path / "Contents/Info.plist", install.BUNDLE, "APPL", "GaoJianKang", path / "Contents/MacOS/GaoJianKang"),
        (path / "Contents/PlugIns/GaoJianKangWidgets.appex", path / "Contents/PlugIns/GaoJianKangWidgets.appex/Contents/Info.plist", install.BUNDLE + ".widgets", "XPC!", "GaoJianKangWidgets", path / "Contents/PlugIns/GaoJianKangWidgets.appex/Contents/MacOS/GaoJianKangWidgets"),
        (path / "Contents/Frameworks/Health.framework", path / "Contents/Frameworks/Health.framework/Versions/A/Resources/Info.plist", install.BUNDLE + ".framework", "FMWK", "Health", path / "Contents/Frameworks/Health.framework/Versions/A/Health"),
    ]
    for bundle, info, bundle_id, kind, executable, binary in components:
        value = {"CFBundleIdentifier": bundle_id, "CFBundlePackageType": kind,
                 "CFBundleExecutable": executable, "CFBundleShortVersionString": version,
                 "CFBundleVersion": build}
        if kind == "XPC!":
            value["NSExtension"] = {"NSExtensionPointIdentifier": "com.apple.widgetkit-extension"}
        write_plist(info, value)
        binary.parent.mkdir(parents=True, exist_ok=True)
        binary.write_bytes((marker + "-" + executable).encode())
        binary.chmod(0o755)
        entitlements = {}
        if kind == "APPL":
            entitlements = {"com.apple.security.application-groups": [install.GROUP, install.TEAM + ".com.gaojiezou.rhythm"]}
        if kind == "XPC!":
            entitlements = {"com.apple.security.application-groups": [install.GROUP], "com.apple.security.app-sandbox": True}
        (bundle / ".fixture-signature.json").write_text(json.dumps({"team": install.TEAM, "entitlements": entitlements}))
    framework = path / "Contents/Frameworks/Health.framework"
    (framework / "Versions/Current").symlink_to("A")
    (framework / "Health").symlink_to("Versions/Current/Health")
    (framework / "Resources").symlink_to("Versions/Current/Resources")


class FakeOps(install.Ops):
    def __init__(self, target):
        self.target = target
        self.calls = []
        self.fail_once = None
        self.interrupt = False

    def hit(self, operation, path):
        self.calls.append((operation, str(path)))
        if operation == self.fail_once:
            self.fail_once = None
            if self.interrupt:
                raise KeyboardInterrupt("fixture interrupted installation")
            raise install.InstallError("fixture failure: " + operation)

    def run(self, args):
        raise AssertionError("Tests must never invoke a real system command: " + repr(args))

    def signature(self, bundle):
        if bundle == self.target:
            version = install.plist(bundle / "Contents/Info.plist")["CFBundleShortVersionString"]
            self.hit("verify-new-installed" if version == "4.04" else "verify-old-installed", bundle)
        return json.loads((bundle / ".fixture-signature.json").read_text())["team"]

    def entitlements(self, bundle):
        return json.loads((bundle / ".fixture-signature.json").read_text())["entitlements"]

    def copy(self, source, target):
        if target == self.target:
            # Deliberately create partial output before the injected error.
            target.mkdir(parents=True, exist_ok=True)
            (target / "partial-copy").write_text("partial fixture")
            self.hit("copy-to-canonical", target)
            (target / "partial-copy").unlink()
        else:
            self.hit("copy-to-backup", target)
        shutil.copytree(source, target, symlinks=True, dirs_exist_ok=True)

    def archive(self, source, target):
        self.hit("archive-backup", target)
        self.zip(source, target)

    @staticmethod
    def zip(source, target):
        target.parent.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(target, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            for relative, entry in install.inventory(source).items():
                path = source / relative
                name = source.name + ("/" + relative if relative else "")
                kind = {"directory": stat.S_IFDIR, "file": stat.S_IFREG, "link": stat.S_IFLNK}[entry["type"]]
                info = zipfile.ZipInfo(name + ("/" if entry["type"] == "directory" else ""))
                info.create_system = 3
                info.external_attr = (kind | entry["mode"]) << 16
                info.compress_type = zipfile.ZIP_DEFLATED
                content = b"" if entry["type"] == "directory" else os.readlink(path).encode() if entry["type"] == "link" else path.read_bytes()
                archive.writestr(info, content)

    def extract(self, source, target):
        self.hit("extract", target)
        directory_modes = []
        with zipfile.ZipFile(source) as archive:
            for entry in archive.infolist():
                path = target / install.zip_name(entry)
                path.parent.mkdir(parents=True, exist_ok=True)
                mode = entry.external_attr >> 16
                if entry.is_dir():
                    path.mkdir(exist_ok=True)
                    directory_modes.append((path, stat.S_IMODE(mode)))
                elif stat.S_ISLNK(mode):
                    path.symlink_to(archive.read(entry).decode())
                else:
                    path.write_bytes(archive.read(entry))
                    path.chmod(stat.S_IMODE(mode))
        for path, mode in directory_modes:
            path.chmod(mode)

    def ensure_stopped(self, target):
        self.hit("ensure-stopped", target)

    def unregister(self, target):
        self.hit("unregister-plugin", target)
        self.hit("unregister-app", target)

    def register(self, target):
        self.hit("register-app", target)
        self.hit("register-plugin", target)


class InstallSafetyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="health-install-", suffix=".noindex")
        self.root = Path(self.temp.name)
        self.project = self.root / "project"
        self.project.mkdir()
        self.target = self.root / "Applications" / install.APP
        make_app(self.target, "4.03", "4", "old")
        self.old_digest = install.inventory_digest(self.target)
        self.ops = FakeOps(self.target)
        self.installer = install.Installer(self.project, self.target, self.ops)
        write_plist(self.project / "Info.plist", {"CFBundleIdentifier": install.BUNDLE, "CFBundleShortVersionString": "4.04", "CFBundleVersion": "5"})
        self.release("4.04", "5")
        # A stale build is intentionally present: only dist may be installed.
        make_app(self.project / "build.noindex" / install.APP, "4.03", "4", "stale-unpackaged")
        self.data = self.root / "UserData" / "health.sqlite"
        self.data.parent.mkdir()
        self.data.write_bytes(b"real-looking-user-data-must-not-be-touched")

    def tearDown(self):
        self.assertEqual(self.data.read_bytes(), b"real-looking-user-data-must-not-be-touched")
        self.temp.cleanup()

    def release(self, version, build, mutate=None):
        source = self.root / "source.noindex" / install.APP
        if source.exists():
            shutil.rmtree(source)
        make_app(source, version, build, "new")
        if mutate:
            mutate(source)
        self.new_digest = install.inventory_digest(source)
        archive = self.project / "dist/GaoJianKang-4.04.zip"
        FakeOps.zip(source, archive)
        archive.with_name(archive.name + ".sha256").write_text(install.digest(archive) + "  " + archive.name + "\n")
        shutil.rmtree(source)

    def latest(self):
        pointer = install.read_receipt(self.installer.backups / "latest.json")
        return self.installer.backups / pointer["receipt"]

    def assert_no_extra_apps(self):
        self.assertEqual(list(self.root.rglob("*.app")), [self.target])

    def test_release_install_archive_and_recovery_pointer(self):
        receipt = self.installer.install()
        data = install.read_receipt(receipt)
        self.assertEqual(install.inventory_digest(self.target), self.new_digest)
        self.assertEqual(data["phase"], "installed_awaiting_uniqueness")
        self.assertEqual(self.latest(), receipt)
        self.assertEqual(install.digest(receipt.parent / data["previous"]["archive"]), data["previous"]["sha256"])
        self.assertEqual(data["previous"]["inventory_sha256"], self.old_digest)
        self.assert_no_extra_apps()
        recovery = self.installer.recover(receipt)
        self.assertEqual(install.inventory_digest(self.target), self.old_digest)
        self.assertEqual(self.latest(), recovery)
        self.assertTrue((receipt.parent / "previous.zip").exists())
        # Recovering the recovery receipt must also work; no dangling pointer.
        self.installer.recover(recovery)
        self.assertEqual(install.inventory_digest(self.target), self.new_digest)
        self.assert_no_extra_apps()

    def test_every_post_backup_failure_restores_canonical(self):
        for operation in ("unregister-plugin", "unregister-app", "copy-to-canonical", "verify-new-installed", "register-app", "register-plugin"):
            with self.subTest(operation=operation):
                self.ops.fail_once = operation
                with self.assertRaises(install.InstallError):
                    self.installer.install()
                self.assertEqual(install.inventory_digest(self.target), self.old_digest)
                receipt = self.latest()
                data = install.read_receipt(receipt)
                self.assertEqual(data["phase"], "rolled_back")
                self.assertTrue((receipt.parent / data["previous"]["archive"]).is_file())
                self.assert_no_extra_apps()

    def test_interruption_during_copy_restores_program(self):
        self.ops.fail_once = "copy-to-canonical"
        self.ops.interrupt = True
        with self.assertRaises(KeyboardInterrupt):
            self.installer.install()
        self.assertEqual(install.inventory_digest(self.target), self.old_digest)
        self.assertEqual(install.read_receipt(self.latest())["phase"], "rolled_back")
        self.assert_no_extra_apps()

    def test_backup_failure_does_not_unregister_or_replace_original(self):
        self.ops.fail_once = "archive-backup"
        with self.assertRaises(install.InstallError):
            self.installer.install()
        self.assertEqual(install.inventory_digest(self.target), self.old_digest)
        self.assertFalse(any(operation.startswith(("register-", "unregister-")) for operation, _ in self.ops.calls))
        for app in self.root.rglob("*.app"):
            self.assertTrue(app == self.target or any(part.endswith(".noindex") for part in app.parts))

    def test_stale_release_build_is_rejected_before_any_change(self):
        self.release("4.04", "4")
        with self.assertRaisesRegex(install.InstallError, "版本/构建号"):
            self.installer.install()
        self.assertEqual(install.inventory_digest(self.target), self.old_digest)
        self.assertFalse(any(operation.startswith("unregister-") for operation, _ in self.ops.calls))

    def test_wrong_widget_identity_and_entitlements_rejected(self):
        def change(source):
            info_path = source / "Contents/PlugIns/GaoJianKangWidgets.appex/Contents/Info.plist"
            info = install.plist(info_path)
            info["CFBundleIdentifier"] = "other.independent.app"
            write_plist(info_path, info)
        self.release("4.04", "5", change)
        with self.assertRaises(install.InstallError):
            self.installer.install()
        self.assertEqual(install.inventory_digest(self.target), self.old_digest)
        def bad_group(source):
            path = source / "Contents/PlugIns/GaoJianKangWidgets.appex/.fixture-signature.json"
            value = json.loads(path.read_text())
            value["entitlements"]["com.apple.security.application-groups"] = ["wrong.group"]
            path.write_text(json.dumps(value))
        self.release("4.04", "5", bad_group)
        with self.assertRaisesRegex(install.InstallError, "App Group"):
            self.installer.install()
        self.assertEqual(install.inventory_digest(self.target), self.old_digest)

    def test_framework_version_and_team_checked(self):
        def bad_framework(source):
            path = source / "Contents/Frameworks/Health.framework/Versions/A/Resources/Info.plist"
            info = install.plist(path)
            info["CFBundleVersion"] = "3"
            write_plist(path, info)
        self.release("4.04", "5", bad_framework)
        with self.assertRaises(install.InstallError):
            self.installer.install()
        def bad_team(source):
            path = source / "Contents/Frameworks/Health.framework/.fixture-signature.json"
            value = json.loads(path.read_text())
            value["team"] = "OTHERTEAM"
            path.write_text(json.dumps(value))
        self.release("4.04", "5", bad_team)
        with self.assertRaisesRegex(install.InstallError, "签名团队"):
            self.installer.install()
        self.assertEqual(install.inventory_digest(self.target), self.old_digest)

    def test_tampered_recovery_archive_cannot_remove_current_install(self):
        receipt = self.installer.install()
        archive = receipt.parent / "previous.zip"
        archive.write_bytes(archive.read_bytes() + b"tampered")
        calls = len(self.ops.calls)
        with self.assertRaisesRegex(install.InstallError, "SHA-256"):
            self.installer.recover(receipt)
        self.assertEqual(install.inventory_digest(self.target), self.new_digest)
        self.assertFalse(any(operation.startswith("unregister-") for operation, _ in self.ops.calls[calls:]))

    def test_invalid_receipt_or_missing_archive_cannot_remove_current(self):
        receipt = self.installer.install()
        original = receipt.read_bytes()
        receipt.write_bytes(original.replace(b"health-install-recovery", b"other-install-recovery"))
        with self.assertRaises(install.InstallError):
            self.installer.recover(receipt)
        receipt.write_bytes(original)
        (receipt.parent / "previous.zip").unlink()
        with self.assertRaises(OSError):
            self.installer.recover(receipt)
        self.assertEqual(install.inventory_digest(self.target), self.new_digest)

    def test_first_install_failure_restores_absence(self):
        shutil.rmtree(self.target)
        self.ops.fail_once = "register-plugin"
        with self.assertRaises(install.InstallError):
            self.installer.install()
        self.assertFalse(self.target.exists())
        self.assertEqual(install.read_receipt(self.latest())["phase"], "rolled_back")

    def test_archive_path_escape_rejected_before_extract(self):
        path = self.root / "bad.zip"
        with zipfile.ZipFile(path, "w") as archive:
            archive.writestr(install.APP + "/Contents/Info.plist", b"fixture")
            archive.writestr(install.APP + "/../../outside", b"must not extract")
        before = len(self.ops.calls)
        with self.assertRaises(install.InstallError):
            self.installer.unpack_verified(path, self.root / "extract.noindex", install.digest(path))
        self.assertEqual(len(self.ops.calls), before)
        self.assertFalse((self.root / "outside").exists())

    def test_unflagged_ditto_utf8_archive_names(self):
        path = self.project / "dist/GaoJianKang-4.04.zip"
        # Clear both local and central language flags without changing UTF-8
        # filename bytes, matching the already-published ditto archives.
        raw = bytearray(path.read_bytes())
        with zipfile.ZipFile(path) as archive:
            for item in archive.infolist():
                offset = item.header_offset + 6
                struct.pack_into("<H", raw, offset, struct.unpack_from("<H", raw, offset)[0] & ~0x800)
            offset = archive.start_dir
            for _ in archive.infolist():
                self.assertEqual(raw[offset:offset+4], b"PK\x01\x02")
                struct.pack_into("<H", raw, offset+8, struct.unpack_from("<H", raw, offset+8)[0] & ~0x800)
                names, extras, comments = struct.unpack_from("<HHH", raw, offset+28)
                offset += 46 + names + extras + comments
        path.write_bytes(raw)
        path.with_name(path.name + ".sha256").write_text(install.digest(path) + "  " + path.name + "\n")
        install.check_zip(path)
        self.installer.install()
        self.assertEqual(install.inventory_digest(self.target), self.new_digest)

    def test_owned_partial_bundle_recovery_and_foreign_inode_rejection(self):
        receipt = self.installer.install()
        data = install.read_receipt(receipt)
        # Simulate an uncatchable process kill: keep the directory inode claimed
        # before ditto, but replace all copied content with a partial file.
        for child in self.target.iterdir():
            shutil.rmtree(child) if child.is_dir() and not child.is_symlink() else child.unlink()
        (self.target / "partial-copy").write_bytes(b"interrupted bytes")
        partial_digest = install.inventory_digest(self.target)
        self.installer.save(receipt, data, "replacing")
        recovery = self.installer.recover(receipt)
        recovered = install.read_receipt(recovery)
        self.assertEqual(install.inventory_digest(self.target), self.old_digest)
        evidence = recovered["interrupted_evidence"]
        self.assertEqual(evidence["inventory_sha256"], partial_digest)
        self.assertTrue((recovery.parent / evidence["archive"]).is_file())
        self.assert_no_extra_apps()
        # A different directory at the same canonical pathname is not ours.
        old_location = self.root / "foreign-evidence.noindex" / install.APP
        old_location.parent.mkdir()
        self.target.rename(old_location)
        self.target.mkdir()
        (self.target / "unrelated.txt").write_text("keep this directory")
        before = install.inventory_digest(self.target)
        with self.assertRaisesRegex(install.InstallError, "其他目录替换"):
            self.installer.recover(recovery)
        self.assertEqual(install.inventory_digest(self.target), before)

    def test_cleanup_rejects_symlink_ancestor_pointing_at_canonical(self):
        build = self.project / "build.noindex"
        shutil.rmtree(build)
        build.symlink_to(self.target.parent, target_is_directory=True)
        with self.assertRaisesRegex(install.InstallError, "恢复尚未完成"):
            self.installer.install()
        self.assertEqual(install.inventory_digest(self.target), self.old_digest)
        self.assertTrue(build.is_symlink())
        self.assertEqual(install.read_receipt(self.latest())["phase"], "recovery_required")


if __name__ == "__main__":
    unittest.main()

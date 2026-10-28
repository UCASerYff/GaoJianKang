#!/usr/bin/env python3
"""Install only the verified Health release; never open apps or touch user data.

The CLI uses the real canonical path. Tests inject filesystem paths and an Ops
implementation directly; there is no production --simulate or target override.
Recovery packages and every expanded staging app live below .noindex first.
"""
from __future__ import annotations

import argparse
import contextlib
import datetime as dt
import fcntl
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import plistlib
import re
import shutil
import stat
import subprocess
import sys
import uuid
import zipfile

APP = "搞健康.app"
BUNDLE = "com.gaoseries.GaoJianKang"
TEAM = "5G96498KGJ"
GROUP = TEAM + ".com.gaoseries.GaoJianKang"
TARGET = Path("/Applications") / APP
PROJECT = Path(__file__).resolve().parents[1]
LSREGISTER = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"


class InstallError(Exception):
    pass


def require(condition, message):
    if not condition:
        raise InstallError(message)


def digest(path: Path) -> str:
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(block)
    return result.hexdigest()


def encoded(value) -> bytes:
    return json.dumps(value, sort_keys=True, ensure_ascii=False, separators=(",", ":")).encode()


def atomic_receipt(path: Path, value):
    payload = encoded(value)
    envelope = {"version": 1, "payload": value, "sha256": hashlib.sha256(payload).hexdigest()}
    temporary = path.with_name(path.name + ".tmp-" + uuid.uuid4().hex)
    try:
        with temporary.open("xb") as stream:
            os.chmod(temporary, 0o600)
            stream.write(encoded(envelope))
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def read_receipt(path: Path):
    require(not path.is_symlink(), "恢复收据不能是链接")
    value = json.loads(path.read_bytes())
    require(value.get("version") == 1 and
            value.get("sha256") == hashlib.sha256(encoded(value.get("payload"))).hexdigest(),
            "恢复收据校验失败，尚未改动当前程序")
    return value["payload"]


def noindex_directory(path: Path):
    require(any(part.endswith(".noindex") for part in path.resolve().parts), "临时程序目录必须位于 .noindex")
    require(not path.is_symlink(), "不接受链接目录")
    path.mkdir(parents=True, exist_ok=True)


def inventory(path: Path) -> dict:
    """Code files, modes and framework links; never follow a bundle link outside."""
    require(path.is_dir() and not path.is_symlink(), "程序目录无效")
    result = {}
    def visit(item, name):
        info = item.lstat()
        mode = stat.S_IMODE(info.st_mode)
        if stat.S_ISLNK(info.st_mode):
            link = os.readlink(item)
            require(not os.path.isabs(link) and item.resolve().is_relative_to(path.resolve()), "程序含越界链接")
            result[name] = {"type": "link", "target": link, "mode": mode}
        elif stat.S_ISDIR(info.st_mode):
            result[name] = {"type": "directory", "mode": mode}
            for child in sorted(item.iterdir()):
                visit(child, (name + "/" if name else "") + child.name)
        elif stat.S_ISREG(info.st_mode):
            result[name] = {"type": "file", "mode": mode, "bytes": info.st_size, "sha256": digest(item)}
        else:
            raise InstallError("程序包含不支持的特殊文件")
    visit(path, "")
    return result


def inventory_digest(path: Path) -> str:
    return hashlib.sha256(encoded(inventory(path))).hexdigest()


def zip_name(item: zipfile.ZipInfo) -> str:
    # Older ditto releases store UTF-8 bytes without ZIP's language flag.
    # zipfile consequently decodes those bytes as CP437. Do not reinterpret a
    # correctly flagged name, or a legacy name which is not strict UTF-8.
    name = item.filename
    if not item.flag_bits & 0x800:
        try:
            name = name.encode("cp437").decode("utf-8", errors="strict")
        except (UnicodeEncodeError, UnicodeDecodeError):
            pass
    return name


def check_zip(path: Path, allow_incomplete=False):
    """Validate paths before ditto sees the archive, including framework symlinks."""
    require(path.is_file() and not path.is_symlink(), "安装归档不存在或为链接")
    with zipfile.ZipFile(path) as archive:
        names = set()
        links = set()
        for item in archive.infolist():
            for candidate in (item.filename, zip_name(item)):
                raw_parts = PurePosixPath(candidate).parts
                require(candidate and "\0" not in candidate and "\\" not in candidate and
                        not candidate.startswith("/") and ".." not in raw_parts, "归档路径越界")
            name = zip_name(item).rstrip("/")
            parts = PurePosixPath(name).parts
            require(name and "\0" not in name and "\\" not in name and
                    not name.startswith("/") and ".." not in parts and
                    parts[0] == APP and name not in names, "归档路径无效或重复")
            names.add(name)
            mode = item.external_attr >> 16
            require(stat.S_IFMT(mode) in (0, stat.S_IFREG, stat.S_IFDIR, stat.S_IFLNK), "归档含特殊文件")
            if stat.S_ISLNK(mode):
                link = archive.read(item).decode("utf-8")
                require(link and not link.startswith("/") and "\0" not in link and "\\" not in link, "归档链接无效")
                resolved = list(parts[:-1])
                for piece in PurePosixPath(link).parts:
                    if piece == "..":
                        require(len(resolved) > 1, "归档链接越界")
                        resolved.pop()
                    elif piece != ".":
                        resolved.append(piece)
                links.add(name)
        require(allow_incomplete or APP + "/Contents/Info.plist" in names, "归档未包含搞健康程序")
        for name in names:
            parents = PurePosixPath(name).parents
            require(not any(str(parent) in links for parent in parents), "归档不能通过链接写入文件")


def plist(path: Path) -> dict:
    with path.open("rb") as stream:
        return plistlib.load(stream)


class Ops:
    """Only this boundary executes macOS tools; fixture tests replace it wholly."""
    def run(self, args):
        done = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        require(done.returncode == 0, "命令失败：" + Path(args[0]).name + "\n" + done.stderr.decode("utf-8", "replace")[:1200])
        return done.stdout

    def signature(self, bundle: Path) -> str:
        self.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(bundle)])
        done = subprocess.run(["/usr/bin/codesign", "-dv", str(bundle)], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        require(done.returncode == 0, "签名详情不可读取")
        match = re.search(r"^TeamIdentifier=(.+)$", done.stderr.decode(), re.M)
        require(match is not None, "缺少签名团队")
        return match[1]

    def entitlements(self, bundle: Path) -> dict:
        return plistlib.loads(self.run(["/usr/bin/codesign", "-d", "--entitlements", ":-", str(bundle)]))

    def copy(self, source: Path, target: Path):
        self.run(["/usr/bin/ditto", str(source), str(target)])

    def archive(self, source: Path, target: Path):
        self.run(["/usr/bin/ditto", "-c", "-k", "--keepParent", "--norsrc", "--noextattr", str(source), str(target)])

    def extract(self, source: Path, target: Path):
        self.run(["/usr/bin/ditto", "-x", "-k", str(source), str(target)])

    def ensure_stopped(self, target: Path):
        pattern = "^" + re.escape(str(target / "Contents/MacOS/GaoJianKang")) + "($| )"
        result = subprocess.run(["/usr/bin/pgrep", "-f", pattern], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        require(result.returncode == 1, "请先退出正式安装的搞健康；安装器不会自动启动或退出应用")

    def unregister(self, target: Path):
        self.run(["/usr/bin/pluginkit", "-r", str(target / "Contents/PlugIns/GaoJianKangWidgets.appex")])
        self.run([LSREGISTER, "-u", str(target)])

    def register(self, target: Path):
        self.run([LSREGISTER, "-f", "-R", str(target)])
        self.run(["/usr/bin/pluginkit", "-a", str(target / "Contents/PlugIns/GaoJianKangWidgets.appex")])


def verify_bundle(app: Path, ops: Ops, expected: tuple[str, str] | None = None) -> dict:
    require(app.is_dir() and not app.is_symlink(), "程序必须是实际目录")
    components = [
        (app, app / "Contents/Info.plist", BUNDLE, "APPL", "GaoJianKang", app / "Contents/MacOS/GaoJianKang"),
        (app / "Contents/PlugIns/GaoJianKangWidgets.appex", app / "Contents/PlugIns/GaoJianKangWidgets.appex/Contents/Info.plist", BUNDLE + ".widgets", "XPC!", "GaoJianKangWidgets", app / "Contents/PlugIns/GaoJianKangWidgets.appex/Contents/MacOS/GaoJianKangWidgets"),
        (app / "Contents/Frameworks/Health.framework", app / "Contents/Frameworks/Health.framework/Versions/A/Resources/Info.plist", BUNDLE + ".framework", "FMWK", "Health", app / "Contents/Frameworks/Health.framework/Versions/A/Health"),
    ]
    found = None
    for bundle, info_path, bundle_id, kind, executable, binary in components:
        info = plist(info_path)
        require(info.get("CFBundleIdentifier") == bundle_id and info.get("CFBundlePackageType") == kind and
                info.get("CFBundleExecutable") == executable and binary.is_file(), "程序、扩展或框架身份不匹配")
        version = (info.get("CFBundleShortVersionString"), info.get("CFBundleVersion"))
        require(all(isinstance(part, str) and part for part in version), "程序缺少版本或构建号")
        found = found or version
        require(version == found and (expected is None or version == expected), "程序、扩展、框架与目标版本/构建号不一致")
        require(ops.signature(bundle) == TEAM, "程序、扩展或框架签名团队不匹配")
    extension = components[1][0]
    require(plist(components[1][1]).get("NSExtension", {}).get("NSExtensionPointIdentifier") == "com.apple.widgetkit-extension", "小组件扩展入口不匹配")
    app_entitlements = ops.entitlements(app)
    widget_entitlements = ops.entitlements(extension)
    require(set(app_entitlements.get("com.apple.security.application-groups", [])) ==
            {GROUP, TEAM + ".com.gaojiezou.rhythm"}, "主程序 App Group 权限不匹配")
    require(set(widget_entitlements.get("com.apple.security.application-groups", [])) == {GROUP} and
            widget_entitlements.get("com.apple.security.app-sandbox") is True, "小组件 App Group 或沙箱权限不匹配")
    inventory(app)
    return {"version": found[0], "build": found[1], "bundle_id": BUNDLE, "team": TEAM}


class Installer:
    def __init__(self, project: Path, target: Path = TARGET, ops: Ops | None = None):
        self.project, self.target, self.ops = project, target, ops or Ops()
        self.backups = project / "rollback.noindex"
        self.stage_root = project / ".install.noindex"

    @contextlib.contextmanager
    def locked(self):
        noindex_directory(self.backups)
        lockfile = self.backups / ".install.lock"
        fd = os.open(lockfile, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
        try:
            fcntl.flock(fd, fcntl.LOCK_EX)
            yield
        finally:
            os.close(fd)

    def unpack_verified(self, archive: Path, parent: Path, expected_hash: str, allow_incomplete=False) -> Path:
        require(digest(archive) == expected_hash, "归档 SHA-256 不匹配，未替换程序")
        check_zip(archive, allow_incomplete=allow_incomplete)
        noindex_directory(parent)
        require(not (parent / APP).exists(), "展开目录必须为空")
        self.ops.extract(archive, parent)
        require(digest(archive) == expected_hash, "归档在读取期间发生变化")
        return parent / APP

    def snapshot_program(self, source: Path, run: Path, name: str, evidence_only=False) -> dict:
        info = {"evidence_only": True} if evidence_only else verify_bundle(source, self.ops)
        before = inventory_digest(source)
        expanded = run / APP
        require(not expanded.exists(), "安全暂存已存在")
        self.ops.copy(source, expanded)
        require(inventory_digest(expanded) == before == inventory_digest(source), "旧程序复制前后校验不一致")
        archive = run / (name + ".zip")
        self.ops.archive(expanded, archive)
        checksum = digest(archive)
        (run / (name + ".zip.sha256")).write_text(checksum + "  " + archive.name + "\n")
        check = run / ("verify-" + uuid.uuid4().hex + ".noindex")
        restored = self.unpack_verified(archive, check, checksum, allow_incomplete=evidence_only)
        if not evidence_only:
            verify_bundle(restored, self.ops, (info["version"], info["build"]))
        require(inventory_digest(restored) == before, "旧程序压缩恢复校验不一致")
        shutil.rmtree(check)
        # Keep this expanded copy until the recovery pointer is durable.
        return {**info, "archive": archive.name, "sha256": checksum, "inventory_sha256": before}

    def save(self, receipt: Path, data: dict, phase: str):
        data["phase"] = phase
        data["updated_at"] = dt.datetime.now(dt.timezone.utc).isoformat()
        atomic_receipt(receipt, data)

    def owns_target(self, data: dict) -> bool:
        try:
            info = self.target.lstat()
            return stat.S_ISDIR(info.st_mode) and data.get("owned_target") == {"device": info.st_dev, "inode": info.st_ino}
        except FileNotFoundError:
            return False

    def claim_target(self, receipt: Path, data: dict, phase: str):
        # Persist the directory identity before it occupies the canonical path.
        # A kill before the rename leaves an absent target; after it, the recorded
        # inode identifies even a half-copied bundle. Neither state is ambiguous.
        reserved = self.stage_root / ("claim-" + uuid.uuid4().hex)
        noindex_directory(reserved)
        try:
            info = reserved.lstat()
            data["owned_target"] = {"device": info.st_dev, "inode": info.st_ino}
            self.save(receipt, data, phase)
            require(not self.target.exists() and not self.target.is_symlink(), "正式路径已被其他目录占用")
            self.target.parent.mkdir(parents=True, exist_ok=True)
            reserved.rename(self.target)
        finally:
            if reserved.exists():
                reserved.rmdir()

    def restore_previous(self, data: dict, run: Path, track=None):
        previous = data["previous"]
        if previous is None:
            if self.target.exists():
                with contextlib.suppress(Exception):
                    self.ops.unregister(self.target)
                shutil.rmtree(self.target)
            return
        archive = run / previous["archive"]
        stage = run / ("restore-" + uuid.uuid4().hex + ".noindex")
        restored = self.unpack_verified(archive, stage, previous["sha256"])
        verify_bundle(restored, self.ops, (previous["version"], previous["build"]))
        require(inventory_digest(restored) == previous["inventory_sha256"], "恢复程序内容不匹配")
        if self.target.exists():
            with contextlib.suppress(Exception):
                self.ops.unregister(self.target)
            if inventory_digest(self.target) != previous["inventory_sha256"]:
                shutil.rmtree(self.target)
        if not self.target.exists():
            if track:
                self.claim_target(track[0], track[1], "recovery_required")
            self.ops.copy(restored, self.target)
        verify_bundle(self.target, self.ops, (previous["version"], previous["build"]))
        require(inventory_digest(self.target) == previous["inventory_sha256"], "恢复后程序校验失败")
        self.ops.register(self.target)
        shutil.rmtree(stage)

    def cleanup_expanded(self, run: Path, stage: Path, evidence=None):
        for path in (run / APP, stage, self.project / "build.noindex" / APP):
            if path.exists():
                require(path.is_relative_to(self.project), "清理路径不在本工程")
                for ancestor in (path, *path.parents):
                    require(not ancestor.is_symlink(), "不能清理链接程序目录或链接祖先")
                    if ancestor == self.project:
                        break
                resolved, canonical = path.resolve(), self.target.resolve()
                require(resolved.is_relative_to(self.project.resolve()) and
                        any(part.endswith(".noindex") for part in resolved.relative_to(self.project.resolve()).parts) and
                        resolved != canonical and not canonical.is_relative_to(resolved), "清理路径越界或包含正式安装程序")
                if path.name == APP:
                    if path == run / APP and evidence is not None:
                        require(inventory_digest(path) == evidence["inventory_sha256"], "中断现场副本与已归档证据不一致")
                    else:
                        require(plist(path / "Contents/Info.plist").get("CFBundleIdentifier") == BUNDLE, "清理路径不是搞健康")
                shutil.rmtree(path)

    def install(self) -> Path:
        with self.locked():
            expected_info = plist(self.project / "Info.plist")
            expected = (expected_info["CFBundleShortVersionString"], expected_info["CFBundleVersion"])
            require(expected_info.get("CFBundleIdentifier") == BUNDLE, "工程标识不匹配")
            archive = self.project / "dist" / ("GaoJianKang-" + expected[0] + ".zip")
            checksum_file = archive.with_name(archive.name + ".sha256")
            parts = checksum_file.read_text().split()
            require(len(parts) == 2 and re.fullmatch(r"[a-fA-F0-9]{64}", parts[0]) and parts[1].lstrip("*") == archive.name, "发行包校验文件无效")
            self.ops.ensure_stopped(self.target)
            stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ") + "-" + uuid.uuid4().hex[:12]
            run, stage = self.backups / stamp, self.stage_root / stamp
            noindex_directory(run)
            noindex_directory(stage)
            receipt = run / "recover.json"
            data = {"format": 1, "kind": "health-install-recovery", "bundle_id": BUNDLE,
                    "canonical": str(self.target), "release_sha256": parts[0].lower(), "previous": None,
                    "new": {"version": expected[0], "build": expected[1]}, "uniqueness": "pending-user-session-verification"}
            changed = False
            try:
                incoming = self.unpack_verified(archive, stage, parts[0].lower())
                verify_bundle(incoming, self.ops, expected)
                new_digest = inventory_digest(incoming)
                data["new"]["inventory_sha256"] = new_digest
                self.save(receipt, data, "release_verified")
                if self.target.exists() or self.target.is_symlink():
                    data["previous"] = self.snapshot_program(self.target, run, "previous")
                    info = self.target.lstat()
                    data["owned_target"] = {"device": info.st_dev, "inode": info.st_ino}
                self.save(receipt, data, "backup_verified")
                atomic_receipt(self.backups / "latest.json", {"receipt": str(receipt.relative_to(self.backups))})
                # Persist intent before unregister/removal so an interruption can
                # always be recovered from the independently verified archive.
                self.save(receipt, data, "replacing")
                changed = True
                if self.target.exists():
                    self.ops.unregister(self.target)
                    shutil.rmtree(self.target)
                self.claim_target(receipt, data, "replacing")
                self.ops.copy(incoming, self.target)
                verify_bundle(self.target, self.ops, expected)
                require(inventory_digest(self.target) == new_digest, "安装内容与发行包不一致")
                self.ops.register(self.target)
                self.save(receipt, data, "installed_static_verified")
                self.cleanup_expanded(run, stage)
                self.save(receipt, data, "installed_awaiting_uniqueness")
                return receipt
            except BaseException as original:
                if changed:
                    try:
                        self.restore_previous(data, run, track=(receipt, data))
                        self.save(receipt, data, "rolled_back")
                        self.cleanup_expanded(run, stage)
                    except BaseException as recovery:
                        self.save(receipt, data, "recovery_required")
                        raise InstallError("安装失败，自动恢复尚未完成。安全归档和恢复收据已保留：" + str(receipt) + "；" + str(recovery)) from original
                else:
                    self.save(receipt, data, "failed_before_replacement")
                    if stage.exists():
                        shutil.rmtree(stage)
                raise

    def recover(self, receipt: Path) -> Path:
        with self.locked():
            require(not receipt.is_symlink() and receipt.resolve().is_relative_to(self.backups.resolve()), "恢复收据不在本应用回滚目录")
            data = read_receipt(receipt)
            require(data.get("format") == 1 and data.get("kind") == "health-install-recovery" and
                    data.get("bundle_id") == BUNDLE and data.get("canonical") == str(self.target), "恢复收据应用或目标不匹配")
            previous = data.get("previous")
            require(isinstance(previous, dict) and previous.get("archive") == "previous.zip", "没有可恢复的旧程序归档")
            run = receipt.parent
            # Validate the complete prior archive before touching the installed app.
            check = run / ("recover-check-" + uuid.uuid4().hex + ".noindex")
            old = self.unpack_verified(run / "previous.zip", check, previous["sha256"])
            verify_bundle(old, self.ops, (previous["version"], previous["build"]))
            require(inventory_digest(old) == previous["inventory_sha256"], "恢复归档内容校验失败")
            shutil.rmtree(check)
            self.ops.ensure_stopped(self.target)
            recovery_run = self.backups / ("recover-" + uuid.uuid4().hex)
            noindex_directory(recovery_run)
            current, evidence = None, None
            if self.target.exists() or self.target.is_symlink():
                require(self.owns_target(data), "正式路径已被其他目录替换，不能按旧事务收据清理")
                current_hash = inventory_digest(self.target)
                known = {previous["inventory_sha256"], data.get("new", {}).get("inventory_sha256")}
                if current_hash in known:
                    current = self.snapshot_program(self.target, recovery_run, "previous")
                else:
                    require(data.get("phase") in {"replacing", "recovering", "recovery_required"},
                            "当前程序不属于可恢复的中断安装状态，未改动当前目录")
                    # A partial copy cannot pass codesign. Its directory inode
                    # was recorded before copy began, and the old signed archive
                    # has already been verified. Preserve it as evidence only.
                    evidence = self.snapshot_program(self.target, recovery_run, "interrupted-copy", evidence_only=True)
            if current is None:
                # Missing or half-copied targets have no valid program to undo to.
                # Retain a second verified pointer to the known-good old program.
                shutil.copy2(run / "previous.zip", recovery_run / "previous.zip")
                require(digest(recovery_run / "previous.zip") == previous["sha256"], "恢复安全归档复制校验失败")
                (recovery_run / "previous.zip.sha256").write_text(previous["sha256"] + "  previous.zip\n")
                current = dict(previous)
            recovery_receipt = recovery_run / "recover.json"
            undo = {"format": 1, "kind": "health-install-recovery", "bundle_id": BUNDLE,
                    "canonical": str(self.target), "previous": current, "origin_receipt": str(receipt),
                    "new": {key: previous[key] for key in ("version", "build", "inventory_sha256")},
                    "owned_target": data.get("owned_target"), "interrupted_evidence": evidence,
                    "uniqueness": "pending-user-session-verification"}
            self.save(recovery_receipt, undo, "recovering")
            atomic_receipt(self.backups / "latest.json", {"receipt": str(recovery_receipt.relative_to(self.backups))})
            try:
                self.restore_previous(data, run, track=(recovery_receipt, undo))
                self.save(recovery_receipt, undo, "recovered_awaiting_uniqueness")
                data["owned_target"] = undo["owned_target"]
                self.save(receipt, data, "recovered_awaiting_uniqueness")
                self.cleanup_expanded(recovery_run, self.stage_root / "unused", evidence=evidence)
                atomic_receipt(self.backups / "latest.json", {"receipt": str(recovery_receipt.relative_to(self.backups))})
                return recovery_receipt
            except BaseException:
                try:
                    self.restore_previous(undo, recovery_run, track=(recovery_receipt, undo))
                    self.save(recovery_receipt, undo, "recovery_rolled_back")
                except BaseException as error:
                    self.save(recovery_receipt, undo, "recovery_required")
                    raise InstallError("恢复未完成，当前和旧版归档均已保留：" + str(recovery_receipt)) from error
                raise


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("install")
    recover = commands.add_parser("recover")
    recover.add_argument("receipt", type=Path)
    check = commands.add_parser("verify-bundle")
    check.add_argument("app", type=Path)
    args = parser.parse_args()
    try:
        if args.command == "verify-bundle":
            info = plist(PROJECT / "Info.plist")
            print(json.dumps(verify_bundle(args.app, Ops(), (info["CFBundleShortVersionString"], info["CFBundleVersion"])), ensure_ascii=False))
            return 0
        installer = Installer(PROJECT)
        receipt = installer.install() if args.command == "install" else installer.recover(args.receipt)
        print(json.dumps({"ok": True, "canonical": str(TARGET), "recovery_receipt": str(receipt),
                          "uniqueness": "尚需实际用户会话核验 Spotlight 与 LaunchServices，不代表交付完成"}, ensure_ascii=False))
        return 0
    except (InstallError, OSError, ValueError, KeyError, zipfile.BadZipFile) as error:
        print(str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Privately snapshot and verify Health data without modifying live files.

Quit Health and Rhythm before each check so shared sleep writes cannot race the copy:
  python3 scripts/upgrade_data.py snapshot --version 4.01
  python3 scripts/upgrade_data.py verify-live /path/returned/as/backup

All data-root and App Group files, including attachments and database sidecars,
are copied and SHA-256 checked. Preferences are exported read-only. Keychain
credentials stay in the existing system Keychain and are never exported.
The current data format/path is preserved; no restoration, migration or deletion
of live data is performed. Missing/unreadable required data fails closed.

Verification is strict: advancing sleep or game state is reported as a
separate difference, never silently accepted. JSON whitespace and Swift Set
ordering are immaterial. Only aggregate counts and public error codes are printed.
Fixture roots can be supplied without accessing real user data or preferences.
"""

from __future__ import annotations

import argparse
import copy
from contextlib import closing
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import sqlite3
import stat
import subprocess
import sys
import tempfile
from urllib.parse import quote
from xml.parsers.expat import ExpatError

FORMAT = 1
APP_ID = "com.gaoseries.GaoJianKang"
DOMAINS = (APP_ID, APP_ID + ".Health")
MANIFEST = "manifest.json"
ATTACHMENT_EXTENSIONS = {".pdf", ".doc", ".docx", ".xls", ".xlsx", ".ppt", ".pptx",
                         ".jpg", ".jpeg", ".png", ".heic", ".gif", ".webp", ".tiff",
                         ".mov", ".mp4", ".mp3", ".m4a", ".wav", ".zip"}
HEALTH_DATABASE = "Health/health.sqlite"


class SafetyError(Exception):
    """The message is a public, non-sensitive error code."""


def fail(code: str) -> None:
    raise SafetyError(code)


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def canonical(value: object) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":"),
                      ensure_ascii=False, allow_nan=False).encode("utf-8")


def parse_json(data: bytes) -> object:
    def unique_keys(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                fail("duplicate_json_key")
            result[key] = value
        return result

    def reject_constant(_):
        fail("nonfinite_json_number")

    try:
        return json.loads(data, object_pairs_hook=unique_keys, parse_constant=reject_constant)
    except (ValueError, UnicodeError):
        fail("invalid_json")


def file_hash(path: Path) -> str:
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
    checksum = hashlib.sha256()
    with os.fdopen(os.open(path, flags), "rb") as source:
        before = os.fstat(source.fileno())
        if not stat.S_ISREG(before.st_mode):
            fail("unsupported_file_type")
        while data := source.read(1024 * 1024):
            checksum.update(data)
        after = os.fstat(source.fileno())
        if (before.st_size, before.st_mtime_ns, before.st_ino) != (
                after.st_size, after.st_mtime_ns, after.st_ino):
            fail("source_changed_during_read")
    return checksum.hexdigest()


def read_file(path: Path) -> bytes:
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
    with os.fdopen(os.open(path, flags), "rb") as source:
        if not stat.S_ISREG(os.fstat(source.fileno()).st_mode):
            fail("unsupported_file_type")
        return source.read()


def inventory(root: Path) -> dict:
    if root.is_symlink() or not root.is_dir():
        fail("required_data_root_missing_or_unsafe")
    files, directories = {}, []
    def traversal_error(error):
        raise error

    for current, names, filenames in os.walk(root, followlinks=False, onerror=traversal_error):
        names.sort()
        filenames.sort()
        base = Path(current)
        for name in names:
            entry = base / name
            if entry.is_symlink() or not entry.is_dir():
                fail("unsafe_directory_entry")
            directories.append(entry.relative_to(root).as_posix())
        for name in filenames:
            entry = base / name
            metadata = entry.lstat()
            if not stat.S_ISREG(metadata.st_mode):
                fail("unsupported_file_type")
            relative = entry.relative_to(root).as_posix()
            files[relative] = {"sha256": file_hash(entry), "bytes": metadata.st_size}
    return {"files": files, "directories": sorted(directories)}


def private_write(path: Path, data: bytes) -> None:
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0)
    with os.fdopen(os.open(path, flags, 0o600), "wb") as target:
        target.write(data)
        target.flush()
        os.fsync(target.fileno())


def mirror(source: Path, target: Path, listing: dict) -> None:
    target.mkdir(mode=0o700, parents=True)
    for relative in listing["directories"]:
        (target / relative).mkdir(mode=0o700, parents=True, exist_ok=True)
    for relative, expected in listing["files"].items():
        original, destination = source / relative, target / relative
        destination.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
        with os.fdopen(os.open(original, flags), "rb") as reader:
            if not stat.S_ISREG(os.fstat(reader.fileno()).st_mode):
                fail("unsupported_file_type")
            with destination.open("xb") as writer:
                os.chmod(destination, 0o600)
                shutil.copyfileobj(reader, writer, 1024 * 1024)
                writer.flush()
                os.fsync(writer.fileno())
        if file_hash(destination) != expected["sha256"]:
            fail("snapshot_copy_checksum_failed")


def normalize_state(value: object) -> object:
    # Swift Set iteration order may change after an otherwise identical save.
    value = copy.deepcopy(value)
    if isinstance(value, dict):
        for key in ("requests",):
            if key in value:
                value[key] = sorted(value[key])
        island = value.get("island")
        if isinstance(island, dict):
            for key in ("tools", "buildings", "rewardedSleepIDs"):
                if key in island:
                    island[key] = sorted(island[key])
        for key in ("records", "events"):
            if key in value:
                value[key] = sorted(value[key], key=lambda row: row["id"])
    return value


def quoted_identifier(value: str) -> str:
    return '"' + value.replace('"', '""') + '"'


def sqlite_summary(path: Path) -> dict:
    uri = "file:" + quote(str(path), safe="/") + "?mode=ro&immutable=1"
    with closing(sqlite3.connect(uri, uri=True, timeout=10)) as connection:
        objects = connection.execute("SELECT type,name,tbl_name,sql FROM sqlite_master ORDER BY type,name").fetchall()
        tables = {}
        for kind, name, _, _ in objects:
            if kind != "table":
                continue
            columns = connection.execute("PRAGMA table_info(" + quoted_identifier(name) + ")").fetchall()
            rows = connection.execute("SELECT * FROM " + quoted_identifier(name)).fetchall()
            normalized = []
            for row in rows:
                values = []
                for column, cell in zip(columns, row):
                    if column[1] == "json" and isinstance(cell, (str, bytes)):
                        values.append({"json": normalize_state(parse_json(cell))})
                    elif isinstance(cell, bytes):
                        values.append({"blob_sha256": digest(cell), "bytes": len(cell)})
                    else:
                        values.append(cell)
                normalized.append(canonical(values).decode("utf-8"))
            tables[name] = {"count": len(rows), "sha256": digest(canonical(sorted(normalized))),
                            "columns_sha256": digest(canonical(columns))}
        return {"user_version": connection.execute("PRAGMA user_version").fetchone()[0],
                "schema_sha256": digest(canonical(objects)), "tables": tables}


def health_summary(path: Path) -> dict:
    uri = "file:" + quote(str(path), safe="/") + "?mode=ro&immutable=1"
    with closing(sqlite3.connect(uri, uri=True, timeout=10)) as connection:
        rows = connection.execute("SELECT id,json FROM state").fetchall()
        if len(rows) != 1 or rows[0][0] != 1:
            fail("health_core_state_missing_or_invalid")
        state = parse_json(rows[0][1])
        if not isinstance(state, dict) or state.get("schemaVersion") not in (1, 2):
            fail("unsupported_health_schema")
        if any(not isinstance(state.get(key), dict) for key in ("island", "preferences", "ledgers")):
            fail("health_state_missing_or_invalid")
        version = connection.execute("PRAGMA user_version").fetchone()[0]
        if version not in (0, 1):
            fail("unsupported_health_database_schema")
        records = {}
        for table in ("records", "events"):
            if version == 0:
                values = state.get(table, [])
            else:
                values = [parse_json(row[0]) for row in connection.execute("SELECT json FROM " + table)]
            if not isinstance(values, list) or any(not isinstance(value, dict) or not value.get("id") for value in values):
                fail("invalid_health_business_records")
            identifiers = [value["id"] for value in values]
            if len(set(identifiers)) != len(identifiers):
                fail("duplicate_health_business_record")
            records[table] = {"count": len(values), "sha256": digest(canonical(sorted(values, key=lambda value: value["id"])))}
        state = normalize_state(state)
        return {"records": records, "core_sha256": digest(canonical(state)),
                "game_sha256": digest(canonical({key: state[key] for key in ("island", "ledgers")})),
                "settings_sha256": digest(canonical(state["preferences"]))}


def database_summaries(target: Path, databases: dict) -> dict:
    if "app_group/" + HEALTH_DATABASE not in databases:
        fail("existing_health_database_missing")
    return {"health": health_summary(target / "app_group" / HEALTH_DATABASE),
            "databases": {key: sqlite_summary(target / key) for key in databases}}


def parse_preferences(data: bytes) -> dict:
    try:
        value = plistlib.loads(data)
    except (ValueError, plistlib.InvalidFileException, ExpatError):
        fail("invalid_preferences")
    if not isinstance(value, dict):
        fail("invalid_preferences")
    return value


def preference_digest(value: dict) -> str:
    return digest(plistlib.dumps(value, fmt=plistlib.FMT_BINARY, sort_keys=True))


def preferences(preferences_dir: Path | None) -> dict:
    if preferences_dir is not None and not preferences_dir.is_dir():
        fail("fixture_preferences_directory_missing")
    result = {}
    for domain in DOMAINS:
        if preferences_dir is not None:
            path = preferences_dir / (domain + ".plist")
            if not path.exists() and not path.is_symlink():
                result[domain] = None
                continue
            result[domain] = parse_preferences(read_file(path))
        else:
            command = subprocess.run(["/usr/bin/defaults", "export", domain, "-"],
                                     stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                     env={**os.environ, "LC_ALL": "C"}, check=False)
            if command.returncode:
                # Absence is explicit. Authorization, I/O and export errors
                # never become an empty preferences dictionary.
                error = command.stderr.decode("utf-8", "replace")
                if "does not exist" in error:
                    result[domain] = None
                    continue
                fail("preferences_export_failed")
            result[domain] = parse_preferences(command.stdout)
    return result


def sqlite_snapshots(roots: dict[str, Path], listings: dict, target: Path) -> dict:
    databases = {}
    group_listing = listings["app_group"]
    if "SharedSleep" in group_listing["directories"] and "SharedSleep/sleep-records.sqlite" not in group_listing["files"]:
        fail("existing_shared_sleep_database_missing")
    for namespace, root in roots.items():
        files = listings[namespace]["files"]
        for relative, metadata in files.items():
            source = root / relative
            with source.open("rb") as handle:
                sqlite_header = handle.read(16) == b"SQLite format 3\0"
            if not sqlite_header:
                if source.suffix.lower() in (".sqlite", ".sqlite3"):
                    fail("invalid_sqlite_header")
                continue
            # Preserve raw db/WAL/SHM in the payload. Open a disposable copy so
            # SQLite can update its shared-memory files without touching live
            # data or changing the byte-for-byte archive.
            with tempfile.TemporaryDirectory(prefix="gao-health-sqlite-") as scratch:
                scratch_path = Path(scratch)
                copied = scratch_path / "database"
                shutil.copyfile(source, copied)
                for suffix in ("-wal", "-shm", "-journal"):
                    sidecar = relative + suffix
                    if sidecar in files:
                        shutil.copyfile(root / sidecar, Path(str(copied) + suffix))
                uri = "file:" + quote(str(copied), safe="/") + "?mode=ro"
                destination = target / namespace / relative
                destination.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
                with closing(sqlite3.connect(uri, uri=True, timeout=10)) as reader:
                    if reader.execute("PRAGMA integrity_check").fetchall() != [("ok",)]:
                        fail("sqlite_source_integrity_failed")
                    with closing(sqlite3.connect(destination)) as writer:
                        reader.backup(writer)
                        writer.commit()
                os.chmod(destination, 0o600)
                check_sqlite(destination)
                databases[namespace + "/" + relative] = {
                    "sha256": file_hash(destination), "bytes": destination.stat().st_size,
                }
    return databases


def check_sqlite(path: Path) -> None:
    uri = "file:" + quote(str(path), safe="/") + "?mode=ro&immutable=1"
    with closing(sqlite3.connect(uri, uri=True, timeout=10)) as connection:
        if connection.execute("PRAGMA integrity_check").fetchall() != [("ok",)]:
            fail("sqlite_snapshot_integrity_failed")


def resolve_roots(args, saved: dict | None = None) -> dict[str, Path]:
    home = Path.home()
    defaults = {"health": home / "Library/Application Support/GaoSeries/Health",
                "app_group": home / "Library/Group Containers/5G96498KGJ.com.gaoseries.GaoJianKang"}
    result = {}
    for name, argument in (("health", args.health_root), ("app_group", args.group_root)):
        path = Path(argument or (saved[name] if saved else defaults[name])).expanduser().absolute()
        if path.is_symlink():
            fail("unsafe_data_root_symlink")
        # Resolve macOS /var -> /private/var for test fixtures. Symlinks inside
        # each data tree remain forbidden by inventory().
        result[name] = path.resolve()
    if result["health"] == result["app_group"] or any(
            a in b.parents for a in result.values() for b in result.values() if a != b):
        fail("overlapping_data_roots")
    return result


def public_counts(listings: dict, summaries: dict, sqlite_count: int) -> dict:
    return {"files": sum(len(v["files"]) for v in listings.values()),
            "bytes": sum(f["bytes"] for v in listings.values() for f in v["files"].values()),
            "business_records": {key: value["count"] for key, value in summaries["health"]["records"].items()},
            "attachment_files": sum(Path(name).suffix.lower() in ATTACHMENT_EXTENSIONS
                                    for listing in listings.values() for name in listing["files"]),
            "sqlite_databases": sqlite_count}


def verify_backup(backup: Path) -> dict:
    if backup.is_symlink() or not backup.is_dir():
        fail("invalid_backup_directory")
    data = read_file(backup / MANIFEST)
    if read_file(backup / "manifest.sha256").decode("ascii").strip() != digest(data):
        fail("backup_manifest_checksum_failed")
    manifest = parse_json(data)
    if not isinstance(manifest, dict) or manifest.get("format") != FORMAT or manifest.get("app_id") != APP_ID:
        fail("unsupported_backup_format")
    if set(manifest["roots"]) != {"health", "app_group"}:
        fail("invalid_backup_roots")
    actual = inventory(backup)
    actual["files"].pop(MANIFEST, None)
    actual["files"].pop("manifest.sha256", None)
    if actual != manifest["archive"]:
        fail("backup_file_checksum_failed")
    roots = {name: backup / "payload" / name for name in manifest["roots"]}
    listings = {name: inventory(root) for name, root in roots.items()}
    if listings != manifest["sources"]:
        fail("backup_source_inventory_failed")
    if database_summaries(backup / "sqlite-consistent", manifest["sqlite"]) != manifest["summaries"]:
        fail("backup_business_integrity_failed")
    for key in manifest["sqlite"]:
        check_sqlite(backup / "sqlite-consistent" / key)
    return manifest


def snapshot(args) -> dict:
    if not re.fullmatch(r"V?[0-9]+(?:\.[0-9]+){1,2}", args.version):
        fail("invalid_version")
    roots = resolve_roots(args)
    preferences_dir = Path(args.preferences_dir).expanduser().resolve() if args.preferences_dir else None
    backup_root = Path(args.backup_root).expanduser().resolve() if args.backup_root else (
        Path.home() / "Library/Application Support/GaoSeries/UpgradeBackups/Health")
    project = Path(__file__).resolve().parents[1]
    if backup_root == project or project in backup_root.parents:
        fail("backup_must_not_enter_source_repository")
    if any(backup_root == root or root in backup_root.parents or backup_root in root.parents for root in roots.values()):
        fail("backup_must_not_overlap_live_data")
    listings = {name: inventory(root) for name, root in roots.items()}
    settings = preferences(preferences_dir)
    backup_root.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(backup_root, 0o700)
    stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ")
    final = backup_root / (stamp + "-V" + args.version.lstrip("V"))
    stage = Path(tempfile.mkdtemp(prefix=".incomplete-", dir=backup_root))
    try:
        copied_roots = {}
        for name, root in roots.items():
            copied_roots[name] = stage / "payload" / name
            mirror(root, copied_roots[name], listings[name])
        for domain, value in settings.items():
            if value is not None:
                private_write(stage / "preferences" / (domain + ".plist"),
                              plistlib.dumps(value, fmt=plistlib.FMT_BINARY, sort_keys=True))
        databases = sqlite_snapshots(copied_roots, listings, stage / "sqlite-consistent")
        summaries = database_summaries(stage / "sqlite-consistent", databases)
        if {name: inventory(root) for name, root in roots.items()} != listings:
            fail("live_data_changed_during_snapshot")
        if preferences(preferences_dir) != settings:
            fail("preferences_changed_during_snapshot")
        manifest = {"format": FORMAT, "app_id": APP_ID, "target_version": args.version,
                    "created_at": stamp, "roots": {name: str(root) for name, root in roots.items()},
                    "preferences_dir": str(preferences_dir) if preferences_dir else None,
                    "preferences_present": {domain: value is not None for domain, value in settings.items()},
                    "sources": listings, "summaries": summaries, "sqlite": databases,
                    "archive": inventory(stage)}
        encoded = canonical(manifest)
        private_write(stage / MANIFEST, encoded)
        private_write(stage / "manifest.sha256", (digest(encoded) + "\n").encode("ascii"))
        verify_backup(stage)
        os.rename(stage, final)
        return {"ok": True, "command": "snapshot", "backup": str(final),
                "counts": public_counts(listings, summaries, len(databases))}
    finally:
        if stage.exists():
            shutil.rmtree(stage)


def verify_live(args) -> dict:
    backup = Path(args.backup).expanduser().resolve()
    manifest = verify_backup(backup)
    roots = resolve_roots(args, manifest["roots"])
    preferences_dir = (Path(args.preferences_dir).expanduser().resolve() if args.preferences_dir else
                       Path(manifest["preferences_dir"]) if manifest.get("preferences_dir") else None)
    listings = {name: inventory(root) for name, root in roots.items()}
    differences = {"files_added": 0, "files_missing": 0, "files_changed": 0,
                   "directories": 0, "preferences": 0}
    for name, root in roots.items():
        old, new = manifest["sources"][name], listings[name]
        old_files, new_files = old["files"], new["files"]
        differences["files_added"] += len(new_files.keys() - old_files.keys())
        differences["files_missing"] += len(old_files.keys() - new_files.keys())
        differences["directories"] += len(set(old["directories"]) ^ set(new["directories"]))
        for relative in old_files.keys() & new_files.keys():
            database_key = name + "/" + relative
            if database_key in manifest["sqlite"] or any(database_key == key + suffix for key in manifest["sqlite"] for suffix in ("-wal", "-shm", "-journal")):
                continue  # Logical contents of every SQLite table are checked below.
            path = Path(relative)
            if path.suffix == ".plist" and path.stem in DOMAINS:
                before = parse_preferences(read_file(backup / "payload" / name / relative))
                after = parse_preferences(read_file(root / relative))
                differences["preferences"] += int(preference_digest(before) != preference_digest(after))
                continue
            differences["files_changed"] += int(old_files[relative] != new_files[relative])
    settings = preferences(preferences_dir)
    for domain, current in settings.items():
        present = manifest["preferences_present"][domain]
        original = parse_preferences(read_file(backup / "preferences" / (domain + ".plist"))) if present else None
        differences["preferences"] += int((original is None) != (current is None) or
                                          preference_digest(original or {}) != preference_digest(current or {}))
    # SQLite may update scratch shared memory; only disposable copies are opened.
    with tempfile.TemporaryDirectory(prefix="gao-health-verify-") as scratch:
        databases = sqlite_snapshots(roots, listings, Path(scratch) / "sqlite")
        summaries = database_summaries(Path(scratch) / "sqlite", databases)
    if {name: inventory(root) for name, root in roots.items()} != listings:
        fail("live_data_changed_during_verification")
    if preferences(preferences_dir) != settings:
        fail("preferences_changed_during_verification")
    previous = manifest["summaries"]
    changed = {"business_records": sum(previous["health"]["records"][key] != value for key, value in summaries["health"]["records"].items()),
               "game_progress": int(previous["health"]["game_sha256"] != summaries["health"]["game_sha256"]),
               "settings": int(previous["health"]["settings_sha256"] != summaries["health"]["settings_sha256"]),
               "core_state": int(previous["health"]["core_sha256"] != summaries["health"]["core_sha256"]),
               "database_contents": sum(previous["databases"].get(key) != summaries["databases"].get(key) for key in previous["databases"].keys() | summaries["databases"].keys())}
    ok = not any(differences.values()) and not any(changed.values())
    return {"ok": ok, "command": "verify-live",
            "counts": public_counts(listings, summaries, len(databases)),
            "difference_counts": differences, "data_difference_counts": changed}


def main() -> int:
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)
    make = commands.add_parser("snapshot", help="Validate and privately snapshot existing data")
    make.add_argument("--version", required=True, help="Target app version, e.g. 4.01")
    make.add_argument("--backup-root", help="Private backup parent; never a source repository")
    check = commands.add_parser("verify-live", help="Verify snapshot and compare all live data")
    check.add_argument("backup", help="Snapshot directory returned by snapshot")
    for command in (make, check):
        command.add_argument("--health-root", help="Override data root for fixtures")
        command.add_argument("--group-root", help="Override App Group root for fixtures")
        command.add_argument("--preferences-dir", help="Read fixture plists instead of macOS defaults")
    args = parser.parse_args()
    try:
        result = snapshot(args) if args.command == "snapshot" else verify_live(args)
        print(json.dumps(result, ensure_ascii=False, sort_keys=True))
        return 0 if result["ok"] else 1
    except SafetyError as error:
        print(json.dumps({"ok": False, "command": args.command, "error": str(error)}), file=sys.stderr)
        return 1
    except (OSError, sqlite3.Error, ValueError, KeyError, TypeError, OverflowError) as error:
        # Keep personal filenames, business content, settings and credentials
        # out of terminal logs and eventual GitHub descriptions.
        print(json.dumps({"ok": False, "command": args.command,
                          "error": "read_or_integrity_check_failed", "error_type": type(error).__name__}), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())

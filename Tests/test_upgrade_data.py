#!/usr/bin/env python3
"""Fixture-only regression checks for private Health upgrade snapshots."""
import argparse
import importlib.util
import json
from pathlib import Path
import plistlib
import sqlite3
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/upgrade_data.py"
spec = importlib.util.spec_from_file_location("health_upgrade", SCRIPT)
upgrade = importlib.util.module_from_spec(spec)
spec.loader.exec_module(upgrade)


class UpgradeSnapshotTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="health-upgrade-test-")
        self.root = Path(self.temp.name).resolve()
        self.health, self.group, self.prefs = (self.root / name for name in ("health", "group", "preferences"))
        for directory in (self.health, self.group / "Health", self.prefs):
            directory.mkdir(parents=True)
        self.db = self.group / "Health/health.sqlite"
        self.state = {"schemaVersion": 2, "island": {"energy": 17, "buildings": ["b", "a"], "tools": [], "rewardedSleepIDs": []},
                      "preferences": {"cup": 250}, "ledgers": {}, "requests": [], "records": [], "events": []}
        with sqlite3.connect(self.db) as connection:
            connection.executescript("CREATE TABLE state(id INTEGER PRIMARY KEY,json BLOB NOT NULL);"
                                     "CREATE TABLE records(id TEXT PRIMARY KEY,kind TEXT,occurred_at REAL,json BLOB);"
                                     "CREATE TABLE events(id TEXT PRIMARY KEY,type_id TEXT,occurred_at REAL,json BLOB);"
                                     "PRAGMA user_version=1;")
            connection.execute("INSERT INTO state VALUES(1,?)", (json.dumps(self.state).encode(),))
            connection.execute("INSERT INTO records VALUES('record','water',10,?)", (json.dumps({"id": "record", "amount": 250}).encode(),))
        (self.health / "paper.pdf").write_bytes(b"private fixture attachment")
        (self.prefs / (upgrade.APP_ID + ".plist")).write_bytes(plistlib.dumps({"appearance": "dark"}))
        self.args = argparse.Namespace(version="4.02", backup_root=str(self.root / "backup"),
                                      health_root=str(self.health), group_root=str(self.group),
                                      preferences_dir=str(self.prefs))

    def tearDown(self):
        self.temp.cleanup()

    def snapshot(self):
        result = upgrade.snapshot(self.args)
        self.args.backup = result["backup"]
        return result

    def test_roundtrip_and_all_data_counts(self):
        result = self.snapshot()
        self.assertEqual(result["counts"]["business_records"], {"records": 1, "events": 0})
        self.assertEqual(result["counts"]["attachment_files"], 1)
        self.assertTrue(upgrade.verify_live(self.args)["ok"])
        self.assertEqual(Path(result["backup"]).stat().st_mode & 0o777, 0o700)

    def test_record_loss_game_and_preferences_are_reported(self):
        self.snapshot()
        self.state["island"]["energy"] = 3
        with sqlite3.connect(self.db) as connection:
            connection.execute("DELETE FROM records")
            connection.execute("UPDATE state SET json=?", (json.dumps(self.state).encode(),))
        (self.prefs / (upgrade.APP_ID + ".plist")).write_bytes(plistlib.dumps({"appearance": "light"}))
        result = upgrade.verify_live(self.args)
        self.assertFalse(result["ok"])
        self.assertEqual(result["data_difference_counts"]["business_records"], 1)
        self.assertEqual(result["data_difference_counts"]["game_progress"], 1)
        self.assertEqual(result["difference_counts"]["preferences"], 1)

    def test_json_whitespace_and_set_order_do_not_look_like_data_loss(self):
        self.snapshot()
        self.state["island"]["buildings"].reverse()
        with sqlite3.connect(self.db) as connection:
            connection.execute("UPDATE state SET json=?", (json.dumps(self.state, indent=2).encode(),))
        self.assertTrue(upgrade.verify_live(self.args)["ok"])

    def test_raw_attachment_changes_and_archive_tampering_fail(self):
        self.snapshot()
        (self.health / "paper.pdf").write_bytes(b"changed")
        self.assertEqual(upgrade.verify_live(self.args)["difference_counts"]["files_changed"], 1)
        (Path(self.args.backup) / "payload/health/paper.pdf").write_bytes(b"tampered")
        with self.assertRaises(upgrade.SafetyError):
            upgrade.verify_live(self.args)

    def test_missing_corrupt_or_symlink_data_never_becomes_empty(self):
        self.db.unlink()
        with self.assertRaises(upgrade.SafetyError):
            self.snapshot()
        self.db.write_bytes(b"invalid database")
        with self.assertRaises(upgrade.SafetyError):
            self.snapshot()
        self.db.unlink()
        self.db.symlink_to(self.health / "paper.pdf")
        with self.assertRaises(upgrade.SafetyError):
            self.snapshot()

    def test_present_shared_directory_without_database_is_not_empty_data(self):
        shared = self.group / "SharedSleep"
        shared.mkdir()
        (shared / ".initialized").write_text("SharedSleep schema 1\n")
        with self.assertRaises(upgrade.SafetyError):
            self.snapshot()

    def test_committed_wal_and_shared_sleep_are_preserved(self):
        shared = self.group / "SharedSleep"
        shared.mkdir()
        connection = sqlite3.connect(shared / "sleep-records.sqlite")
        try:
            connection.executescript("PRAGMA journal_mode=WAL;CREATE TABLE sleep(id TEXT);INSERT INTO sleep VALUES('sleep-id');")
            connection.commit()
            result = self.snapshot()
            self.assertEqual(result["counts"]["sqlite_databases"], 2)
            snapshot = Path(result["backup"]) / "sqlite-consistent/app_group/SharedSleep/sleep-records.sqlite"
            with sqlite3.connect(snapshot.as_uri() + "?mode=ro&immutable=1", uri=True) as copied:
                self.assertEqual(copied.execute("SELECT COUNT(*) FROM sleep").fetchone()[0], 1)
            self.assertTrue(upgrade.verify_live(self.args)["ok"])
        finally:
            connection.close()


if __name__ == "__main__":
    unittest.main()

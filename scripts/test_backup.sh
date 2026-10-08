#!/bin/zsh
set -euo pipefail
ROOT=${0:A:h:h}
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
[[ -d "$DEVELOPER_DIR" ]] || { echo 'Backup test requires Xcode'; exit 1; }
TEST_WORK=$(mktemp -d "${TMPDIR:-/tmp}/gao-health-backup-test.XXXXXXXX")
trap 'rm -rf "$TEST_WORK"' EXIT INT TERM
TEST_APP="$TEST_WORK/BackupSafetyRegression.app"
mkdir -p "$TEST_APP/Contents/MacOS" "$TEST_WORK/tmp" "$TEST_WORK/cache"
python3 - "$ROOT/Info.plist" "$TEST_APP/Contents/Info.plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'rb') as source:
    version = plistlib.load(source)['CFBundleShortVersionString']
with open(sys.argv[2], 'wb') as target:
    plistlib.dump({
        'CFBundleIdentifier': 'com.gao.health.tests.backup-safety',
        'CFBundleName': 'BackupSafetyRegression',
        'CFBundleExecutable': 'BackupSafetyRegression',
        'CFBundlePackageType': 'APPL',
        'CFBundleShortVersionString': version,
        'CFBundleVersion': '1',
    }, target)
PY
SDK=$(xcrun --sdk macosx --show-sdk-path)
swiftc -swift-version 5 -parse-as-library -Onone -D BACKUP_SAFETY_TEST \
    -sdk "$SDK" -target "$(uname -m)-apple-macosx14.0" \
    -module-cache-path "$TEST_WORK/cache" -framework AppKit -framework CryptoKit -lsqlite3 \
    "$ROOT/Tests/BackupSafetyRegression.swift" \
    "$ROOT/Host/AppBackupExport.swift" "$ROOT/Host/AppBackupRestore.swift" \
    "$ROOT/Host/BackupIntegrity.swift" "$ROOT/Host/DailyBackup.swift" \
    -o "$TEST_APP/Contents/MacOS/BackupSafetyRegression"
# Verify the Host sources compiled against the module-local in-memory fake.
if nm -u "$TEST_APP/Contents/MacOS/BackupSafetyRegression" | /usr/bin/c++filt | \
    /usr/bin/grep -E 'NSUserDefaults|Foundation.*UserDefaults'; then
    echo 'Unsafe test binary: references real UserDefaults'; exit 1
fi
TMPDIR="$TEST_WORK/tmp/" GQ_BACKUP_TEST_ROOT="$TEST_WORK/data" \
    "$TEST_APP/Contents/MacOS/BackupSafetyRegression"
[[ ! -e "$TEST_WORK/data" ]] || { echo 'Fixture data was not cleaned'; exit 1; }

#!/bin/zsh
set -euo pipefail
ROOT=${0:A:h:h}
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
[[ -d "$DEVELOPER_DIR" ]] || { echo 'Backup test requires Xcode'; exit 1; }
TEST_PARENT=$(mktemp -d "${TMPDIR:-/tmp}/gao-health-backup-test.XXXXXXXX")
trap 'rm -rf "$TEST_PARENT"' EXIT INT TERM
TEST_WORK="$TEST_PARENT/Fixture.noindex"
TEST_BINARY="$TEST_WORK/BackupSafetyRegression"
mkdir -p "$TEST_WORK/tmp" "$TEST_WORK/cache"
python3 - "$ROOT/Info.plist" "$TEST_WORK/Info.plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'rb') as source:
    version = plistlib.load(source)['CFBundleShortVersionString']
with open(sys.argv[2], 'wb') as target:
    plistlib.dump({
        'CFBundleIdentifier': 'com.gao.health.tests.backup-safety',
        'CFBundleName': 'BackupSafetyRegression',
        'CFBundleExecutable': 'BackupSafetyRegression',
        'CFBundleShortVersionString': version,
        'CFBundleVersion': '1',
    }, target)
PY
SDK=$(xcrun --sdk macosx --show-sdk-path)
swiftc -swift-version 5 -parse-as-library -Onone -D BACKUP_SAFETY_TEST \
    -sdk "$SDK" -target "$(uname -m)-apple-macosx14.0" \
    -module-cache-path "$TEST_WORK/cache" -framework AppKit -framework CryptoKit -framework WidgetKit -lsqlite3 \
    "$ROOT/Tests/BackupSafetyRegression.swift" \
    "$ROOT/Host/AppBackupExport.swift" "$ROOT/Host/AppBackupRestore.swift" \
    "$ROOT/Host/BackupIntegrity.swift" "$ROOT/Host/DailyBackup.swift" "$ROOT/Host/RestorePreferences.swift" \
    "$ROOT"/Shared/*.swift "$ROOT/Sources/SharedSleepStore.swift" \
    -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker "$TEST_WORK/Info.plist" \
    -o "$TEST_BINARY"
# Verify the Host sources compiled against the module-local in-memory fake.
if nm -u "$TEST_BINARY" | /usr/bin/c++filt | \
    /usr/bin/grep -E 'NSUserDefaults|Foundation.*UserDefaults'; then
    echo 'Unsafe test binary: references real UserDefaults'; exit 1
fi
TMPDIR="$TEST_WORK/tmp/" GQ_BACKUP_TEST_ROOT="$TEST_WORK/data" \
    "$TEST_BINARY" "$@"
[[ ! -e "$TEST_WORK/data" ]] || { echo 'Fixture data was not cleaned'; exit 1; }

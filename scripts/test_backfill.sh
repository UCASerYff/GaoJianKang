#!/bin/zsh
set -euo pipefail
ROOT=${0:A:h:h}
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
TEST_BUILD=$(mktemp -d "${TMPDIR:-/tmp/}health-backfill-build.XXXXXX")
trap 'rm -rf "$TEST_BUILD"' EXIT
swiftc -swift-version 5 -parse-as-library -module-cache-path "$TEST_BUILD/cache" -lsqlite3 \
  "$ROOT/Sources/SharedSleepStore.swift" "$ROOT/Sources/HealthSleepImport.swift" \
  "$ROOT/Shared/Models.swift" "$ROOT/Shared/Engine.swift" "$ROOT/Tests/BackfillRegression.swift" \
  -o "$TEST_BUILD/health-backfill"
"$TEST_BUILD/health-backfill"

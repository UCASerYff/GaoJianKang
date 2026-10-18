#!/bin/zsh
set -euo pipefail
ROOT=${0:A:h:h}
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
TEST_BUILD=$(mktemp -d "${TMPDIR:-/tmp/}health-widget-data-build.XXXXXX")
trap 'rm -rf "$TEST_BUILD"' EXIT
swiftc -swift-version 5 -parse-as-library -module-cache-path "$TEST_BUILD/cache" -lsqlite3 -framework WidgetKit \
    "$ROOT"/Shared/*.swift \
    "$ROOT/Sources/SharedSleepStore.swift" \
    "$ROOT/Tests/WidgetDataRegression.swift" -o "$TEST_BUILD/widget-data-regression"
"$TEST_BUILD/widget-data-regression"

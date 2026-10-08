#!/bin/zsh
set -euo pipefail
ROOT=${0:A:h:h}
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
TEST_BUILD=$(mktemp -d "${TMPDIR:-/tmp/}gao-shared-sleep-build.XXXXXX")
trap 'rm -rf "$TEST_BUILD"' EXIT
SDK=$(xcrun --sdk macosx --show-sdk-path)
swiftc -swift-version 5 -parse-as-library \
    -sdk "$SDK" -target arm64-apple-macosx14.0 \
    -module-cache-path "$TEST_BUILD/cache" -lsqlite3 \
    "$ROOT/Sources/SharedSleepStore.swift" "$ROOT/Tests/SharedSleepRegression.swift" \
    -o "$TEST_BUILD/shared-sleep-regression"
"$TEST_BUILD/shared-sleep-regression"

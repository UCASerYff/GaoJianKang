#!/bin/zsh
set -euo pipefail
ROOT=${0:A:h:h}
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
BUILD="$ROOT/build.noindex"
mkdir -p "$BUILD/PlugIns" "$BUILD/widget-cache"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Info.plist")
NUMBER=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$ROOT/Info.plist")

xcodebuild -quiet -project "$ROOT/Widgets/GaoJianKangWidgets.xcodeproj" -target GaoJianKangWidgets -configuration Release CODE_SIGNING_ALLOWED=NO ARCHS=arm64 ONLY_ACTIVE_ARCH=YES SYMROOT="$BUILD/widget-products" OBJROOT="$BUILD/widget-objects" CLANG_MODULE_CACHE_PATH="$BUILD/widget-cache" build
ditto "$BUILD/widget-products/Release/GaoJianKangWidgets.appex" "$BUILD/PlugIns/GaoJianKangWidgets.appex"
cp "$ROOT/Widgets/Info.plist" "$BUILD/PlugIns/GaoJianKangWidgets.appex/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$BUILD/PlugIns/GaoJianKangWidgets.appex/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NUMBER" "$BUILD/PlugIns/GaoJianKangWidgets.appex/Contents/Info.plist"

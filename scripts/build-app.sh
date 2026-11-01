#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-${TMPDIR:-/tmp}/diskscope-module-cache}"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
BUILD_PATH="${DISKSCOPE_BUILD_PATH:-.build}"
swift build -c release --product DiskScope --disable-sandbox --cache-path "${TMPDIR:-/tmp}/diskscope-cache" --scratch-path "$BUILD_PATH"
APP="dist/DiskScope.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD_PATH/release/DiskScope" "$APP/Contents/MacOS/DiskScope"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>DiskScope</string>
<key>CFBundleDisplayName</key><string>DiskScope</string>
<key>CFBundleIdentifier</key><string>com.romeoprojectdeploy.diskscope</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleExecutable</key><string>DiskScope</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSDownloadsFolderUsageDescription</key><string>Analyze the size of files you choose to review.</string>
<key>NSDocumentsFolderUsageDescription</key><string>Analyze the size of files you choose to review.</string>
<key>NSDesktopFolderUsageDescription</key><string>Analyze the size of files you choose to review.</string>
</dict></plist>
PLIST
codesign --force --deep --sign - "$APP"
echo "Built $APP"

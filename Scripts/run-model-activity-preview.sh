#!/bin/zsh
set -euo pipefail
project_dir=${0:A:h:h}
cd "$project_dir"
export CLANG_MODULE_CACHE_PATH=/private/tmp/codex-limits-clang-cache
export SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/codex-limits-swiftpm-cache
xcrun swift build -c release --product CodexWidgetKit --disable-sandbox
bin_dir=$(xcrun swift build -c release --show-bin-path --disable-sandbox)
app_dir="$project_dir/.build/model-activity-preview/Model Activity Preview.app"
mkdir -p "$app_dir/Contents/MacOS"
app_sources=(Sources/CodexLimits/*.swift)
app_sources=(${app_sources:#Sources/CodexLimits/CodexLimitsApp.swift})
xcrun swiftc -O -parse-as-library -target "$(uname -m)-apple-macosx14.0" \
    -I "$bin_dir/Modules" -L "$bin_dir" -lCodexWidgetKit \
    "${app_sources[@]}" Scripts/ModelActivityPreview.swift \
    -o "$app_dir/Contents/MacOS/ModelActivityPreview"
cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.github.nserfan.CodexLimits.activity-preview</string>
<key>CFBundleName</key><string>Model Activity Preview</string>
<key>CFBundleExecutable</key><string>ModelActivityPreview</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$app_dir"
pkill -TERM -x ModelActivityPreview 2>/dev/null || true
for _ in {1..25}; do
    pgrep -x ModelActivityPreview >/dev/null || break
    sleep 0.2
done
open "$app_dir"

#!/bin/zsh
set -euo pipefail

project_dir=${0:A:h:h}
app_dir="$project_dir/.build/release/Codex Limits.app"

cd "$project_dir"
export DEVELOPER_DIR=${DEVELOPER_DIR:-$(xcode-select -p)}
export CLANG_MODULE_CACHE_PATH=/private/tmp/codex-limits-clang-cache
export SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/codex-limits-swiftpm-cache

xcrun swift build -c release --disable-sandbox
rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp .build/release/CodexLimits "$app_dir/Contents/MacOS/CodexLimits"
cp Resources/Info.plist "$app_dir/Contents/Info.plist"
codesign --force --sign - "$app_dir"

print -r -- "$app_dir"

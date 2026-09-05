#!/bin/zsh
set -euo pipefail
project_dir=${0:A:h:h}
cd "$project_dir"
export CLANG_MODULE_CACHE_PATH=/private/tmp/codex-limits-clang-cache
export SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/codex-limits-swiftpm-cache
xcrun swift build --product CodexWidgetKit --disable-sandbox
bin_dir=$(xcrun swift build --show-bin-path --disable-sandbox)
# Exclude the app entry point: previewing must not register login/background jobs.
app_sources=(Sources/CodexLimits/*.swift)
app_sources=(${app_sources:#Sources/CodexLimits/CodexLimitsApp.swift})
xcrun swiftc -parse-as-library -target "$(uname -m)-apple-macosx14.0" \
    -I "$bin_dir/Modules" -L "$bin_dir" -lCodexWidgetKit \
    "${app_sources[@]}" Scripts/MenuPreviewRenderer.swift -o "$bin_dir/MenuPreviewRenderer"
"$bin_dir/MenuPreviewRenderer" "${1:-$project_dir/.build/menu-previews}"

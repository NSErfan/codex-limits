#!/bin/zsh
set -euo pipefail
project_dir=${0:A:h:h}
configuration=${CONFIGURATION:-release}
[[ "$configuration" == release || "$configuration" == debug ]] || { print -u2 "CONFIGURATION must be debug or release"; exit 2; }
cd "$project_dir"
export CLANG_MODULE_CACHE_PATH=/private/tmp/codex-limits-clang-cache
export SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/codex-limits-swiftpm-cache
xcrun swift build -c "$configuration" --product CodexWidgetKit --disable-sandbox
bin_dir=$(xcrun swift build -c "$configuration" --show-bin-path --disable-sandbox)
benchmark_dir="$project_dir/.build/history-scroll-benchmark/$configuration"
app_dir="$benchmark_dir/HistoryScrollBenchmark.app"
mkdir -p "$app_dir/Contents/MacOS"
optimization=(-O)
[[ "$configuration" == debug ]] && optimization=(-Onone -g)
app_sources=(Sources/CodexLimits/*.swift)
app_sources=(${app_sources:#Sources/CodexLimits/CodexLimitsApp.swift})
xcrun swiftc "${optimization[@]}" -parse-as-library -target "$(uname -m)-apple-macosx14.0" \
    -I "$bin_dir/Modules" -L "$bin_dir" -lCodexWidgetKit \
    "${app_sources[@]}" Scripts/HistoryScrollBenchmark.swift \
    -o "$app_dir/Contents/MacOS/HistoryScrollBenchmark"
cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
    <key>CFBundleExecutable</key><string>HistoryScrollBenchmark</string>
    <key>CFBundleIdentifier</key><string>com.github.nserfan.CodexLimits.scroll-benchmark</string>
    <key>CFBundleName</key><string>History Scroll Benchmark</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
# Sequential runs avoid competing benchmark windows and overlapping workloads.
for run in {1..3}; do
    log="$benchmark_dir/run-$run.log"
    errors="$benchmark_dir/run-$run.err"
    : > "$log"
    : > "$errors"
    /usr/bin/open -n -W --stdout "$log" --stderr "$errors" "$app_dir"
    cat "$log"
    if ! grep -q '^RESULT ' "$log"; then
        cat "$errors" >&2
        exit 1
    fi
done

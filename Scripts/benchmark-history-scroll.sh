#!/bin/zsh
set -euo pipefail
project_dir=${0:A:h:h}
cd "$project_dir"
export CLANG_MODULE_CACHE_PATH=/private/tmp/codex-limits-clang-cache
export SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/codex-limits-swiftpm-cache
xcrun swift build -c release --product CodexWidgetKit --disable-sandbox
bin_dir=$(xcrun swift build -c release --show-bin-path --disable-sandbox)
benchmark_dir="$project_dir/.build/history-scroll-benchmark"
mkdir -p "$benchmark_dir"
app_sources=(Sources/CodexLimits/*.swift)
app_sources=(${app_sources:#Sources/CodexLimits/CodexLimitsApp.swift})
xcrun swiftc -O -parse-as-library -target "$(uname -m)-apple-macosx14.0" \
    -I "$bin_dir/Modules" -L "$bin_dir" -lCodexWidgetKit \
    "${app_sources[@]}" Scripts/HistoryScrollBenchmark.swift \
    -o "$benchmark_dir/HistoryScrollBenchmark"
# Sequential runs avoid competing benchmark windows and overlapping workloads.
for run in {1..3}; do
    "$benchmark_dir/HistoryScrollBenchmark" | tee "$benchmark_dir/run-$run.log"
done

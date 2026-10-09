#!/bin/zsh
set -euo pipefail
project_dir=${0:A:h:h}
cd "$project_dir"
export CLANG_MODULE_CACHE_PATH=/private/tmp/codex-limits-clang-cache
export SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/codex-limits-swiftpm-cache
xcrun swift build --disable-sandbox
bin_dir=$(xcrun swift build --show-bin-path --disable-sandbox)
output=${1:-$project_dir/.build/menu-bar-labels}
probe_bundle="$output/MenuBarLabelProbe.app"
mkdir -p "$probe_bundle/Contents/MacOS" "$probe_bundle/Contents/Resources"
cat > "$probe_bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>MenuBarLabelProbe</string>
<key>CFBundleIdentifier</key><string>com.github.nserfan.MenuBarLabelProbe</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
app_sources=(Sources/CodexLimits/*.swift)
app_sources=(${app_sources:#Sources/CodexLimits/CodexLimitsApp.swift})
xcrun swiftc -parse-as-library -target "$(uname -m)-apple-macosx14.0" \
    -I "$bin_dir/Modules" -L "$bin_dir" -lCodexWidgetKit \
    "${app_sources[@]}" Scripts/MenuBarLabelProbe.swift \
    -o "$probe_bundle/Contents/MacOS/MenuBarLabelProbe"
ditto "$bin_dir/CodexLimits_CodexWidgetKit.bundle" "$probe_bundle/Contents/Resources/CodexLimits_CodexWidgetKit.bundle"
codesign --force --sign - "$probe_bundle"
suite="MenuBarLabelProbe.$(uuidgen)"
trap '"$probe_bundle/Contents/MacOS/MenuBarLabelProbe" --cleanup "$suite"' EXIT
launch_count=0

run_probe() {
    local provider=$1 mode=$2 selection=$3 fixture=$4 phase=${5:-single}
    local scenario="$output/$provider-$mode-$selection-$fixture-$phase"
    mkdir -p "$scenario"
    rm -f "$scenario/result.txt"
    open -n -W "$probe_bundle" --args "$provider" "$mode" "$scenario" "$selection" "$fixture" "$suite" "$phase"
    if [[ ! -f "$scenario/result.txt" ]] || ! rg --quiet '^PASS:' "$scenario/result.txt"; then
        print -u2 -- "Native menu-bar check failed: $scenario"
        if [[ -f "$scenario/result.txt" ]]; then cat "$scenario/result.txt" >&2; fi
        return 1
    fi
    rg '^PASS:' "$scenario/result.txt"
    launch_count=$((launch_count + 1))
}

for provider in codex claude copilot; do
    selections=(automatic)
    if [[ "$provider" != copilot ]]; then selections+=(fiveHour weekly); fi
    for mode in iconOnly textOnly iconAndText; do
        for selection in "${selections[@]}"; do
            run_probe "$provider" "$mode" "$selection" complete
        done
        run_probe "$provider" "$mode" automatic unavailable
        if [[ "$provider" != copilot ]]; then
            run_probe "$provider" "$mode" automatic fiveHourLowest
            run_probe "$provider" "$mode" fiveHour missingFiveHour
            run_probe "$provider" "$mode" weekly missingWeekly
            run_probe "$provider" "$mode" fiveHour unavailable
            run_probe "$provider" "$mode" weekly unavailable
            run_probe "$provider" "$mode" automatic complete switching
        fi
    done
done

for provider in codex claude; do
    for selection in fiveHour weekly; do
        run_probe "$provider" iconOnly "$selection" complete write
        run_probe "$provider" iconOnly "$selection" complete read
    done
done

print -r -- "Passed $launch_count native menu-bar probe launches, including repeated switching and preferences read after relaunch."

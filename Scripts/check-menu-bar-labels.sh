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
for provider in codex claude; do
    for mode in iconOnly textOnly iconAndText; do
        scenario="$output/$provider-$mode"
        mkdir -p "$scenario"
        rm -f "$scenario/result.txt"
        open -n -W "$probe_bundle" --args "$provider" "$mode" "$scenario"
        title="46%"
        if [[ "$mode" != iconOnly ]]; then
            if [[ "$provider" == codex ]]; then title="Codex 46%"; else title="Claude Code 46%"; fi
        fi
        if [[ "$mode" == textOnly ]]; then image="nil"; else image="Optional((25.0, 18.0))"; fi
        rg --fixed-strings "button title: $title; image: $image;" "$scenario/result.txt"
    done
done

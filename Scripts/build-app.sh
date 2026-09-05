#!/bin/zsh
set -euo pipefail

project_dir=${0:A:h:h}
configuration=${CONFIGURATION:-release}
[[ "$configuration" == release || "$configuration" == debug ]] || { print -u2 "CONFIGURATION must be debug or release"; exit 2; }
app_dir="$project_dir/.build/$configuration/Codex Limits.app"
signing_config="$project_dir/.env.signing.plist"
configured_identity="-"
configured_team=""
if [[ -f "$signing_config" ]]; then
    configured_identity=$(/usr/libexec/PlistBuddy -c 'Print :CodeSignIdentity' "$signing_config")
    configured_team=$(/usr/libexec/PlistBuddy -c 'Print :DevelopmentTeam' "$signing_config")
fi
signing_identity=${CODE_SIGN_IDENTITY:-$configured_identity}
development_team=${DEVELOPMENT_TEAM:-$configured_team}
if [[ "$signing_identity" != "-" && -z "$development_team" ]]; then
    print -u2 "Set DEVELOPMENT_TEAM to your Apple team ID for widget data sharing."
    exit 2
fi
if [[ "$signing_identity" == "-" && -n "$development_team" ]]; then
    print -u2 "DEVELOPMENT_TEAM also requires a valid CODE_SIGN_IDENTITY."
    exit 2
fi

cd "$project_dir"
export DEVELOPER_DIR=${DEVELOPER_DIR:-$(xcode-select -p)}
export CLANG_MODULE_CACHE_PATH=/private/tmp/codex-limits-clang-cache
export SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/codex-limits-swiftpm-cache

xcrun swift build -c "$configuration" --disable-sandbox
bin_dir=$(xcrun swift build -c "$configuration" --show-bin-path --disable-sandbox)
rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$bin_dir/CodexLimits" "$app_dir/Contents/MacOS/CodexLimits"
cp Resources/Info.plist "$app_dir/Contents/Info.plist"
mkdir -p "$app_dir/Contents/Library/LaunchAgents"
cp Resources/com.github.nserfan.CodexLimits.collector.plist \
    "$app_dir/Contents/Library/LaunchAgents/"
widget_dir="$app_dir/Contents/PlugIns/CodexLimitsWidgets.appex"
# A real extension target supplies the extension entry point and launch metadata.
# Wrapping a plain swiftc executable in .appex can register but exit before it
# serves WidgetKit's descriptor request on macOS 26.
widget_products="$project_dir/.build/$configuration/widget-products"
xcodebuild -project Widgets/CodexLimitsWidgets.xcodeproj \
    -target CodexLimitsWidgets -configuration Release \
    "ARCHS=$(uname -m)" ONLY_ACTIVE_ARCH=YES \
    "CODEX_WIDGET_LIBRARY_DIR=$bin_dir" \
    "CONFIGURATION_BUILD_DIR=$widget_products" \
    "OBJROOT=$project_dir/.build/$configuration/widget-intermediates" \
    CODE_SIGNING_ALLOWED=NO build
mkdir -p "$app_dir/Contents/PlugIns"
ditto "$widget_products/CodexLimitsWidgets.appex" "$widget_dir"

app_entitlements="$project_dir/.build/$configuration/App.entitlements"
widget_entitlements="$project_dir/.build/$configuration/Widget.entitlements"
cat > "$app_entitlements" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict/></plist>
PLIST
cp "$app_entitlements" "$widget_entitlements"
/usr/libexec/PlistBuddy -c 'Add :com.apple.security.app-sandbox bool true' "$widget_entitlements"
if [[ -n "$development_team" ]]; then
    # Team-prefixed groups are supported on macOS without provisioning profiles.
    widget_group="$development_team.com.github.nserfan.CodexLimits"
    for entitlements in "$app_entitlements" "$widget_entitlements"; do
        /usr/libexec/PlistBuddy -c 'Add :com.apple.security.application-groups array' "$entitlements"
        /usr/libexec/PlistBuddy -c "Add :com.apple.security.application-groups:0 string $widget_group" "$entitlements"
    done
    for plist in "$app_dir/Contents/Info.plist" "$widget_dir/Contents/Info.plist"; do
        /usr/libexec/PlistBuddy -c "Add :CodexWidgetAppGroup string $widget_group" "$plist"
    done
else
    print -u2 "Ad-hoc build: widget previews work; desktop data sharing requires developer signing."
fi
codesign --force --sign "$signing_identity" --entitlements "$widget_entitlements" "$widget_dir"
if [[ -n "$development_team" ]]; then
    signed_team=$(codesign -dv --verbose=4 "$widget_dir" 2>&1 | sed -n 's/^TeamIdentifier=//p')
    if [[ "$signed_team" != "$development_team" ]]; then
        print -u2 "DEVELOPMENT_TEAM must match the signing identity's team ($signed_team)."
        exit 2
    fi
fi
codesign --force --sign "$signing_identity" --entitlements "$app_entitlements" "$app_dir"
codesign --verify --deep --strict "$app_dir"

print -r -- "$app_dir"

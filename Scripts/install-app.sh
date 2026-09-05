#!/bin/zsh
set -euo pipefail

project_dir=${0:A:h:h}
destination="/Applications/Codex Limits.app"

# build-app.sh prints the bundle path on its final line.
app_dir=$("$project_dir/Scripts/build-app.sh" | tail -n1)

# Stop both processes, including the independently hosted widget extension.
"$project_dir/Scripts/stop-app.sh"

rm -rf "$destination"
ditto "$app_dir" "$destination"
codesign --verify --deep --strict "$destination"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$destination"
/usr/bin/pluginkit -a "$destination/Contents/PlugIns/CodexLimitsWidgets.appex"
open "$destination"

print -r -- "$destination"

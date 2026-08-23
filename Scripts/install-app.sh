#!/bin/zsh
set -euo pipefail

project_dir=${0:A:h:h}
destination="/Applications/Codex Limits.app"

# build-app.sh prints the bundle path on its final line.
app_dir=$("$project_dir/Scripts/build-app.sh" | tail -n1)

# Quit gracefully so the running instance persists its state first.
osascript -e 'tell application "Codex Limits" to quit' 2>/dev/null || true
for _ in {1..25}; do
    pgrep -qf "Codex Limits.app/Contents/MacOS/CodexLimits" || break
    sleep 0.2
done

rm -rf "$destination"
ditto "$app_dir" "$destination"
open "$destination"

print -r -- "$destination"

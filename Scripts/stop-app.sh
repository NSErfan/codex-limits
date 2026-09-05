#!/bin/zsh
set -euo pipefail

# WidgetKit keeps the extension alive independently of the menu-bar app.
# Replacing its bundle without stopping it leaves the old code serving reloads.
for process_name in CodexLimits CodexLimitsWidgets; do
    pkill -TERM -x "$process_name" 2>/dev/null || true
    for _ in {1..25}; do
        pgrep -x "$process_name" >/dev/null || break
        sleep 0.2
    done
    if pgrep -x "$process_name" >/dev/null; then
        print -u2 "Could not stop $process_name; leaving the installed app unchanged."
        exit 1
    fi
done

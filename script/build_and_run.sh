#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
PROCESS_NAME="CodexLimits"
BUNDLE_ID="com.github.nserfan.CodexLimits"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
case "$MODE" in
  run|--debug|debug|--logs|logs|--telemetry|telemetry|--verify|verify) ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac

export DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}"
export CLANG_MODULE_CACHE_PATH=/private/tmp/codex-limits-clang-cache
export SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/codex-limits-swiftpm-cache

# The installer stops the app after building, updates Applications, and registers
# the app and widget. Its final line is the installed bundle path.
APP_BUNDLE=$(CONFIGURATION=debug "$ROOT_DIR/Scripts/install-app.sh" --no-launch | tail -n1)
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$PROCESS_NAME"

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$PROCESS_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    for process_id in $(pgrep -x "$PROCESS_NAME"); do
      if [[ "$(ps -p "$process_id" -o comm=)" == "$APP_BINARY" ]]; then
        exit 0
      fi
    done
    echo "The installed app did not launch: $APP_BINARY" >&2
    exit 1
    ;;
esac

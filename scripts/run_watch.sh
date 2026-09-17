#!/usr/bin/env bash
# Builds and launches the VoxbriefWatch app on an Apple Watch simulator.
#
# Usage:
#   ./scripts/run_watch.sh
#   WATCH_NAME="Apple Watch Ultra 3 (49mm)" ./scripts/run_watch.sh
#
# Note: this launches the watch app standalone. WatchConnectivity sync to an
# iPhone requires the paired iPhone simulator to also be booted and running
# Voxbrief — use scripts/run_all.sh for that. Simulator-to-simulator
# WatchConnectivity file transfer is also known to be less reliable than on
# real hardware, so treat sync testing on the simulator as best-effort.
#
# List available device names with: xcrun simctl list devices available

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"

WATCH_NAME="${WATCH_NAME:-Apple Watch Series 11 (46mm)}"

regenerate_project

udid="$(find_simulator_udid "$WATCH_NAME")"
if [[ -z "$udid" ]]; then
  echo "error: no simulator named '$WATCH_NAME' found." >&2
  echo "List available devices with: xcrun simctl list devices available" >&2
  exit 1
fi

boot_simulator "$udid"
build_app "VoxbriefWatch" "$udid"

app_path="$(find_app_path "VoxbriefWatch")"
if [[ -z "$app_path" ]]; then
  echo "error: could not locate built VoxbriefWatch.app under $DERIVED_DATA_PATH" >&2
  exit 1
fi

install_and_launch "$udid" "$app_path" "com.jacksonzhou666.voxbrief.app.watchkitapp"
echo "✅ VoxbriefWatch is running on '$WATCH_NAME' ($udid)."

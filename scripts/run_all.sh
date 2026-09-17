#!/usr/bin/env bash
# Builds and launches both the Voxbrief iPhone app and the VoxbriefWatch app
# on a paired iPhone + Apple Watch simulator, so you can exercise the full
# watch-capture -> iPhone-processing flow end to end.
#
# Usage:
#   ./scripts/run_all.sh
#   IPHONE_NAME="iPhone 17 Pro Max" WATCH_NAME="Apple Watch Series 11 (46mm)" ./scripts/run_all.sh
#
# Defaults below match an already-paired simulator set on this machine
# (see `xcrun simctl list pairs`). If you use a different pair, override
# both env vars together so the two devices are actually paired with
# each other -- an unpaired iPhone + Watch combination will boot and run,
# but WatchConnectivity will never report reachable/paired.
#
# Note: simulator-to-simulator WatchConnectivity file transfer (how a
# watch recording actually reaches the iPhone) is known to be less
# reliable than on real hardware. Use Settings > "Simulate Incoming
# Watch Audio Sync" in the iOS app to exercise the processing pipeline
# without depending on that transfer.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"

IPHONE_NAME="${IPHONE_NAME:-iPhone 17 Pro Max}"
WATCH_NAME="${WATCH_NAME:-Apple Watch Series 11 (46mm)}"

regenerate_project

iphone_udid="$(find_simulator_udid "$IPHONE_NAME")"
if [[ -z "$iphone_udid" ]]; then
  echo "error: no simulator named '$IPHONE_NAME' found." >&2
  exit 1
fi

watch_udid="$(find_simulator_udid "$WATCH_NAME")"
if [[ -z "$watch_udid" ]]; then
  echo "error: no simulator named '$WATCH_NAME' found." >&2
  exit 1
fi

echo "== iPhone: $IPHONE_NAME ($iphone_udid) =="
boot_simulator "$iphone_udid"
build_app "Voxbrief" "$iphone_udid"
iphone_app_path="$(find_app_path "Voxbrief")"
if [[ -z "$iphone_app_path" ]]; then
  echo "error: could not locate built Voxbrief.app under $DERIVED_DATA_PATH" >&2
  exit 1
fi
install_and_launch "$iphone_udid" "$iphone_app_path" "com.jacksonzhou666.voxbrief.app"

echo
echo "== Watch: $WATCH_NAME ($watch_udid) =="
boot_simulator "$watch_udid"
build_app "VoxbriefWatch" "$watch_udid"
watch_app_path="$(find_app_path "VoxbriefWatch")"
if [[ -z "$watch_app_path" ]]; then
  echo "error: could not locate built VoxbriefWatch.app under $DERIVED_DATA_PATH" >&2
  exit 1
fi
install_and_launch "$watch_udid" "$watch_app_path" "com.jacksonzhou666.voxbrief.app.watchkitapp"

echo
echo "✅ Voxbrief is running on both '$IPHONE_NAME' and '$WATCH_NAME'."

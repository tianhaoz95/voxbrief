#!/usr/bin/env bash
# Builds and launches the Voxbrief iOS app on an iPhone simulator.
#
# Usage:
#   ./scripts/run_ios.sh
#   IPHONE_NAME="iPhone 16 Pro" ./scripts/run_ios.sh
#
# List available device names with: xcrun simctl list devices available

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"

IPHONE_NAME="${IPHONE_NAME:-iPhone 17 Pro Max}"

regenerate_project

udid="$(find_simulator_udid "$IPHONE_NAME")"
if [[ -z "$udid" ]]; then
  echo "error: no simulator named '$IPHONE_NAME' found." >&2
  echo "List available devices with: xcrun simctl list devices available" >&2
  exit 1
fi

boot_simulator "$udid"
build_app "Voxbrief" "$udid"

app_path="$(find_app_path "Voxbrief")"
if [[ -z "$app_path" ]]; then
  echo "error: could not locate built Voxbrief.app under $DERIVED_DATA_PATH" >&2
  exit 1
fi

install_and_launch "$udid" "$app_path" "com.jacksonzhou666.voxbrief.app"
echo "✅ Voxbrief is running on '$IPHONE_NAME' ($udid)."

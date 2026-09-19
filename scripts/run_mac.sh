#!/usr/bin/env bash
# Builds and launches the VoxbriefMac menu-bar app locally.
#
# Usage:
#   ./scripts/run_mac.sh
#
# On first launch you'll need to grant Microphone and Accessibility access in
# System Settings > Privacy & Security -- the app prompts for both from its
# menu bar item. Accessibility is required for the global "both Command keys"
# hotkey and for pasting the cleaned-up result into the focused app.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"

regenerate_project

echo "-> Building VoxbriefMac (this can take a minute)..."
xcodebuild build \
  -project "$REPO_ROOT/Voxbrief.xcodeproj" \
  -scheme VoxbriefMac \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO

app_path="$(find_app_path "VoxbriefMac")"
if [[ -z "$app_path" ]]; then
  echo "error: could not locate built VoxbriefMac.app under $DERIVED_DATA_PATH" >&2
  exit 1
fi

echo "-> Relaunching $(basename "$app_path")..."
pkill -f "$app_path" >/dev/null 2>&1 || true
open "$app_path"
echo "✅ VoxbriefMac is running (menu bar icon, no Dock icon -- look for the waveform glyph)."

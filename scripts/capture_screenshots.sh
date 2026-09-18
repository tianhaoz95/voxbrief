#!/usr/bin/env bash
# Automated screenshot capture for App Store Connect releases and marketing.
# Captures pixel-perfect screenshots for both iPhone (6.9"/6.7") and Apple Watch (46mm),
# sets clean 9:41 status bars, exercises the key views, and generates promotional assets.
#
# Usage:
#   ./scripts/capture_screenshots.sh
#   ./scripts/capture_screenshots.sh --skip-build
#   IPHONE_NAME="iPhone 16 Pro Max" ./scripts/capture_screenshots.sh
#
# Output:
#   metadata/screenshots/iphone/
#   metadata/screenshots/watch/
#   fastlane/screenshots/en-US/
#   docs/assets/promo/

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_DIR="$REPO_ROOT/scripts"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"

IPHONE_NAME="${IPHONE_NAME:-iPhone 17 Pro Max}"
WATCH_NAME="${WATCH_NAME:-Apple Watch Series 11 (46mm)}"
SKIP_BUILD=false

for arg in "$@"; do
  case "$arg" in
    --skip-build)
      SKIP_BUILD=true
      ;;
  esac
done

IPHONE_APP_BUNDLE_ID="com.jacksonzhou666.voxbrief.app"
WATCH_APP_BUNDLE_ID="com.jacksonzhou666.voxbrief.app.watchkitapp"

IPHONE_OUTPUT_DIR="$REPO_ROOT/metadata/screenshots/iphone"
WATCH_OUTPUT_DIR="$REPO_ROOT/metadata/screenshots/watch"
FASTLANE_DIR="$REPO_ROOT/fastlane/screenshots/en-US"

mkdir -p "$IPHONE_OUTPUT_DIR" "$WATCH_OUTPUT_DIR" "$FASTLANE_DIR"

echo "================================================================"
echo "  Voxbrief App Store Screenshot Automation Pipeline"
echo "================================================================"

# --- 1. Locate Simulators ---------------------------------------------------

echo "-> Locating iPhone simulator '$IPHONE_NAME'..."
IPHONE_UDID="$(find_simulator_udid "$IPHONE_NAME")"
if [[ -z "$IPHONE_UDID" ]]; then
  echo "warning: '$IPHONE_NAME' not found, looking for any booted iPhone..."
  IPHONE_UDID="$(xcrun simctl list devices available -j | jq -r '.devices[] | .[] | select(.name | test("iPhone") and .state == "Booted") | .udid' | head -n1)"
fi
if [[ -z "$IPHONE_UDID" ]]; then
  echo "error: Could not find an iPhone simulator. Available devices:" >&2
  xcrun simctl list devices available >&2
  exit 1
fi
echo "   Found iPhone simulator: $IPHONE_UDID"

echo "-> Locating Apple Watch simulator '$WATCH_NAME'..."
WATCH_UDID="$(find_simulator_udid "$WATCH_NAME")"
if [[ -z "$WATCH_UDID" ]]; then
  echo "warning: '$WATCH_NAME' not found, looking for any booted Apple Watch..."
  WATCH_UDID="$(xcrun simctl list devices available -j | jq -r '.devices[] | .[] | select(.name | test("Apple Watch") and .state == "Booted") | .udid' | head -n1)"
fi
if [[ -z "$WATCH_UDID" ]]; then
  echo "error: Could not find an Apple Watch simulator. Available devices:" >&2
  xcrun simctl list devices available >&2
  exit 1
fi
echo "   Found Apple Watch simulator: $WATCH_UDID"

# --- 2. Boot Simulators -----------------------------------------------------

boot_simulator "$IPHONE_UDID"
boot_simulator "$WATCH_UDID"

# --- 3. Build Apps if required ----------------------------------------------

if [[ "$SKIP_BUILD" != "true" ]]; then
  echo "-> Building iPhone app (Voxbrief)..."
  build_app "Voxbrief" "$IPHONE_UDID"
  echo "-> Building Apple Watch app (VoxbriefWatch)..."
  build_app "VoxbriefWatch" "$WATCH_UDID"
else
  echo "-> Skipping build phase (--skip-build specified)."
fi

IPHONE_APP_PATH="$(find_app_path "Voxbrief")"
WATCH_APP_PATH="$(find_app_path "VoxbriefWatch")"

if [[ -z "$IPHONE_APP_PATH" || ! -d "$IPHONE_APP_PATH" ]]; then
  echo "error: Voxbrief.app not found under $DERIVED_DATA_PATH. Run without --skip-build." >&2
  exit 1
fi

if [[ -z "$WATCH_APP_PATH" || ! -d "$WATCH_APP_PATH" ]]; then
  echo "error: VoxbriefWatch.app not found under $DERIVED_DATA_PATH. Run without --skip-build." >&2
  exit 1
fi

# --- 4. Install fresh app builds --------------------------------------------

echo "-> Installing apps to simulators..."
xcrun simctl install "$IPHONE_UDID" "$IPHONE_APP_PATH"
xcrun simctl install "$WATCH_UDID" "$WATCH_APP_PATH"

# Ensure clean first-run state on iPhone
xcrun simctl spawn "$IPHONE_UDID" defaults write "$IPHONE_APP_BUNDLE_ID" has_completed_onboarding -bool true

# Configure standard Apple 9:41 AM status bar
echo "-> Applying pristine Apple marketing status bar (9:41 AM, 100% battery, full signal)..."
xcrun simctl status_bar "$IPHONE_UDID" override \
  --time "9:41" \
  --batteryState charged \
  --batteryLevel 100 \
  --cellularBars 4 \
  --wifiBars 3

cleanup() {
  echo "-> Resetting status bar overrides..."
  xcrun simctl status_bar "$IPHONE_UDID" clear 2>/dev/null || true
}
trap cleanup EXIT

# --- 5. Capture iPhone Screenshots ------------------------------------------

capture_iphone_screen() {
  local filename="$1"
  local description="$2"
  shift 2 || true

  echo "  📸 Capturing iPhone screen: $description ($filename)..."
  xcrun simctl terminate "$IPHONE_UDID" "$IPHONE_APP_BUNDLE_ID" 2>/dev/null || true
  sleep 0.5

  if [[ $# -gt 0 ]]; then
    xcrun simctl launch "$IPHONE_UDID" "$IPHONE_APP_BUNDLE_ID" "$@" >/dev/null
  else
    xcrun simctl launch "$IPHONE_UDID" "$IPHONE_APP_BUNDLE_ID" >/dev/null
  fi
  sleep 2.5

  xcrun simctl io "$IPHONE_UDID" screenshot "$IPHONE_OUTPUT_DIR/$filename" >/dev/null
  cp "$IPHONE_OUTPUT_DIR/$filename" "$FASTLANE_DIR/$filename"
}

echo "-> Capturing iPhone screenshots..."
capture_iphone_screen "01_notes_list.png" "Notes List & Dynamic Tags" -voxbriefScreen list
capture_iphone_screen "02_note_detail.png" "Structured Note & Audio Scrubber" -voxbriefScreen detail -voxbriefTab cleaned
capture_iphone_screen "03_two_stage_pipeline.png" "Verbatim Speech-to-Text (ASR)" -voxbriefScreen detail -voxbriefTab raw
capture_iphone_screen "04_pipeline_diagnostics.png" "Two-Stage AI Pipeline Diagnostics" -voxbriefScreen detail -voxbriefTab pipeline
capture_iphone_screen "05_quick_record.png" "Instant Voice Recording" -voxbriefScreen record -voxbriefSimulateRecording
capture_iphone_screen "06_settings_pipeline.png" "On-Device WhisperKit & MLX Models" -voxbriefScreen settings

# --- 6. Capture Apple Watch Screenshots -------------------------------------

capture_watch_screen() {
  local filename="$1"
  local description="$2"
  shift 2 || true

  echo "  ⌚ Capturing Apple Watch screen: $description ($filename)..."
  xcrun simctl terminate "$WATCH_UDID" "$WATCH_APP_BUNDLE_ID" 2>/dev/null || true
  sleep 0.5

  if [[ $# -gt 0 ]]; then
    xcrun simctl launch "$WATCH_UDID" "$WATCH_APP_BUNDLE_ID" "$@" >/dev/null
  else
    xcrun simctl launch "$WATCH_UDID" "$WATCH_APP_BUNDLE_ID" >/dev/null
  fi
  sleep 2.5

  xcrun simctl io "$WATCH_UDID" screenshot "$WATCH_OUTPUT_DIR/$filename" >/dev/null
  cp "$WATCH_OUTPUT_DIR/$filename" "$FASTLANE_DIR/$filename"
}

echo "-> Capturing Apple Watch screenshots..."
capture_watch_screen "watch_01_instant_capture.png" "Instant 1-Tap Capture"
capture_watch_screen "watch_02_recording_active.png" "Active Recording & Waveform" -voxbriefWatchRecording
capture_watch_screen "watch_03_notes_queue.png" "Offline Storage Queue" -voxbriefWatchNotes

# Terminate apps at the end
xcrun simctl terminate "$IPHONE_UDID" "$IPHONE_APP_BUNDLE_ID" 2>/dev/null || true
xcrun simctl terminate "$WATCH_UDID" "$WATCH_APP_BUNDLE_ID" 2>/dev/null || true

# --- 7. Generate Promotional Graphics & Landing Page Assets -----------------

if [[ -f "$SCRIPT_DIR/generate_promo_assets.py" ]]; then
  echo "-> Generating promotional graphics and device mockups..."
  python3 "$SCRIPT_DIR/generate_promo_assets.py"
fi

echo ""
echo "================================================================"
echo "✅ All screenshots captured and promotional graphics generated!"
echo "================================================================"
echo "iPhone Screenshots:"
ls -lh "$IPHONE_OUTPUT_DIR"/*.png | awk '{print "  - " $9 " (" $5 ")"}'
echo "Apple Watch Screenshots:"
ls -lh "$WATCH_OUTPUT_DIR"/*.png | awk '{print "  - " $9 " (" $5 ")"}'
if [[ -d "$REPO_ROOT/docs/assets/promo" ]]; then
  echo "Promotional Assets:"
  ls -lh "$REPO_ROOT/docs/assets/promo"/*.png 2>/dev/null | awk '{print "  - " $9 " (" $5 ")"}' || true
fi

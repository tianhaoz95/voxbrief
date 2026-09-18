#!/usr/bin/env bash
# ==============================================================================
# Voxbrief Automated Screenshot Capture & Marketing Pipeline
# ==============================================================================
# Captures pixel-perfect screenshots for App Store release and marketing:
#   - iPhone: 6.9"/6.7" Super Retina XDR (1320 x 2868)
#   - Apple Watch: 46mm Ultra/Series display (416 x 496)
# Sets pristine 9:41 AM status bars, drives app states via launch arguments,
# and generates framed promotional composites.
#
# Usage:
#   ./scripts/capture_screenshots.sh [options]
#
# Options:
#   -h, --help                Show this help message and exit
#   -s, --skip-build          Skip rebuilding Xcode schemes (use existing DerivedData)
#   --skip-promo              Skip generating composite marketing assets with Pillow
#   --iphone-only             Capture iPhone screenshots only
#   --watch-only              Capture Apple Watch screenshots only
#   --iphone-device <name>    Target iPhone simulator (default: iPhone 17 Pro Max)
#   --watch-device <name>     Target Apple Watch simulator (default: Apple Watch Series 11 (46mm))
#   --output-dir <path>       Base directory for screenshots (default: metadata/screenshots)
#   --fastlane-dir <path>     Fastlane screenshots directory (default: fastlane/screenshots/en-US)
#
# Environment variables:
#   IPHONE_NAME               Alternative way to override target iPhone simulator
#   WATCH_NAME                Alternative way to override target Apple Watch simulator
# ==============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_DIR="$REPO_ROOT/scripts"

# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"

# Default configuration
IPHONE_NAME="${IPHONE_NAME:-iPhone 17 Pro Max}"
WATCH_NAME="${WATCH_NAME:-Apple Watch Series 11 (46mm)}"
SKIP_BUILD=false
SKIP_PROMO=false
CAPTURE_IPHONE=true
CAPTURE_WATCH=true
CUSTOM_OUTPUT_DIR=""
CUSTOM_FASTLANE_DIR=""

show_help() {
  cat << 'EOF'
Voxbrief Automated Screenshot Capture & Marketing Pipeline

Usage:
  ./scripts/capture_screenshots.sh [options]

Options:
  -h, --help                Show this help message and exit
  -s, --skip-build          Skip building Xcode schemes (use existing DerivedData binaries)
  --skip-promo              Skip generating composite marketing graphics with Pillow
  --iphone-only             Capture iPhone screenshots only (skip watchOS)
  --watch-only              Capture Apple Watch screenshots only (skip iOS)
  --iphone-device <name>    Specify iPhone simulator name (default: iPhone 17 Pro Max)
  --watch-device <name>     Specify Watch simulator name (default: Apple Watch Series 11 (46mm))
  --output-dir <path>       Base output directory (default: metadata/screenshots)
  --fastlane-dir <path>     Fastlane output directory (default: fastlane/screenshots/en-US)

Examples:
  ./scripts/capture_screenshots.sh
  ./scripts/capture_screenshots.sh --skip-build
  ./scripts/capture_screenshots.sh --iphone-only --skip-build
  ./scripts/capture_screenshots.sh --iphone-device "iPhone 16 Pro Max"
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      show_help
      exit 0
      ;;
    -s|--skip-build)
      SKIP_BUILD=true
      shift
      ;;
    --skip-promo)
      SKIP_PROMO=true
      shift
      ;;
    --iphone-only)
      CAPTURE_IPHONE=true
      CAPTURE_WATCH=false
      shift
      ;;
    --watch-only)
      CAPTURE_IPHONE=false
      CAPTURE_WATCH=true
      shift
      ;;
    --iphone-device)
      IPHONE_NAME="$2"
      shift 2
      ;;
    --watch-device)
      WATCH_NAME="$2"
      shift 2
      ;;
    --output-dir)
      CUSTOM_OUTPUT_DIR="$2"
      shift 2
      ;;
    --fastlane-dir)
      CUSTOM_FASTLANE_DIR="$2"
      shift 2
      ;;
    *)
      echo "error: Unknown option '$1'. Use --help for usage." >&2
      exit 1
      ;;
  esac
done

IPHONE_APP_BUNDLE_ID="com.jacksonzhou666.voxbrief.app"
WATCH_APP_BUNDLE_ID="com.jacksonzhou666.voxbrief.app.watchkitapp"

BASE_OUTPUT_DIR="${CUSTOM_OUTPUT_DIR:-$REPO_ROOT/metadata/screenshots}"
IPHONE_OUTPUT_DIR="$BASE_OUTPUT_DIR/iphone"
WATCH_OUTPUT_DIR="$BASE_OUTPUT_DIR/watch"
FASTLANE_DIR="${CUSTOM_FASTLANE_DIR:-$REPO_ROOT/fastlane/screenshots/en-US}"

mkdir -p "$IPHONE_OUTPUT_DIR" "$WATCH_OUTPUT_DIR" "$FASTLANE_DIR"

echo "================================================================"
echo "  Voxbrief Screenshot Automation"
echo "================================================================"
echo "  Capture iOS:       $CAPTURE_IPHONE ($IPHONE_NAME)"
echo "  Capture watchOS:   $CAPTURE_WATCH ($WATCH_NAME)"
echo "  Skip Build:        $SKIP_BUILD"
echo "  Output Directory:  $BASE_OUTPUT_DIR"
echo "================================================================"

IPHONE_UDID=""
WATCH_UDID=""

# --- 1. Locate Simulators -----------------------------------------------------

if [[ "$CAPTURE_IPHONE" == "true" ]]; then
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
  echo "   iPhone simulator UDID: $IPHONE_UDID"
  boot_simulator "$IPHONE_UDID"
fi

if [[ "$CAPTURE_WATCH" == "true" ]]; then
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
  echo "   Apple Watch simulator UDID: $WATCH_UDID"
  boot_simulator "$WATCH_UDID"
fi

# --- 2. Build Apps ------------------------------------------------------------

if [[ "$SKIP_BUILD" != "true" ]]; then
  regenerate_project
  if [[ "$CAPTURE_IPHONE" == "true" ]]; then
    echo "-> Building iOS scheme (Voxbrief)..."
    build_app "Voxbrief" "$IPHONE_UDID"
  fi
  if [[ "$CAPTURE_WATCH" == "true" ]]; then
    echo "-> Building watchOS scheme (VoxbriefWatch)..."
    build_app "VoxbriefWatch" "$WATCH_UDID"
  fi
else
  echo "-> Skipping build phase (--skip-build specified)."
fi

# --- 3. Install Apps & Setup Status Bar ---------------------------------------

if [[ "$CAPTURE_IPHONE" == "true" ]]; then
  IPHONE_APP_PATH="$(find_app_path "Voxbrief")"
  if [[ -z "$IPHONE_APP_PATH" || ! -d "$IPHONE_APP_PATH" ]]; then
    echo "error: Voxbrief.app not found under $DERIVED_DATA_PATH. Run without --skip-build." >&2
    exit 1
  fi
  echo "-> Installing Voxbrief on iPhone simulator..."
  xcrun simctl install "$IPHONE_UDID" "$IPHONE_APP_PATH"
  xcrun simctl spawn "$IPHONE_UDID" defaults write "$IPHONE_APP_BUNDLE_ID" has_completed_onboarding -bool true

  echo "-> Applying Apple marketing status bar (9:41 AM, 100% battery, full signal)..."
  xcrun simctl status_bar "$IPHONE_UDID" override \
    --time "9:41" \
    --batteryState charged \
    --batteryLevel 100 \
    --cellularBars 4 \
    --wifiBars 3
fi

if [[ "$CAPTURE_WATCH" == "true" ]]; then
  WATCH_APP_PATH="$(find_app_path "VoxbriefWatch")"
  if [[ -z "$WATCH_APP_PATH" || ! -d "$WATCH_APP_PATH" ]]; then
    echo "error: VoxbriefWatch.app not found under $DERIVED_DATA_PATH. Run without --skip-build." >&2
    exit 1
  fi
  echo "-> Installing VoxbriefWatch on Apple Watch simulator..."
  xcrun simctl install "$WATCH_UDID" "$WATCH_APP_PATH"
fi

cleanup() {
  if [[ -n "$IPHONE_UDID" ]]; then
    echo "-> Resetting iPhone status bar overrides..."
    xcrun simctl status_bar "$IPHONE_UDID" clear 2>/dev/null || true
  fi
}
trap cleanup EXIT

# --- 4. iPhone Capture Routine ------------------------------------------------

capture_iphone_screen() {
  local filename="$1"
  local description="$2"
  shift 2 || true

  echo "  📸 iPhone: $description ($filename)..."
  xcrun simctl terminate "$IPHONE_UDID" "$IPHONE_APP_BUNDLE_ID" 2>/dev/null || true
  sleep 0.4

  if [[ $# -gt 0 ]]; then
    xcrun simctl launch "$IPHONE_UDID" "$IPHONE_APP_BUNDLE_ID" "$@" >/dev/null
  else
    xcrun simctl launch "$IPHONE_UDID" "$IPHONE_APP_BUNDLE_ID" >/dev/null
  fi
  sleep 2.5

  xcrun simctl io "$IPHONE_UDID" screenshot "$IPHONE_OUTPUT_DIR/$filename" >/dev/null
  cp "$IPHONE_OUTPUT_DIR/$filename" "$FASTLANE_DIR/$filename"
}

if [[ "$CAPTURE_IPHONE" == "true" ]]; then
  echo "-> Capturing iPhone screenshots..."
  capture_iphone_screen "01_notes_list.png" "Notes List & Dynamic Tags" -voxbriefScreen list
  capture_iphone_screen "02_note_detail.png" "Structured Note & Audio Scrubber" -voxbriefScreen detail -voxbriefTab cleaned
  capture_iphone_screen "03_two_stage_pipeline.png" "Verbatim Speech-to-Text (ASR)" -voxbriefScreen detail -voxbriefTab raw
  capture_iphone_screen "04_pipeline_diagnostics.png" "Two-Stage AI Pipeline Diagnostics" -voxbriefScreen detail -voxbriefTab pipeline
  capture_iphone_screen "05_quick_record.png" "Instant Voice Recording" -voxbriefScreen record -voxbriefSimulateRecording
  capture_iphone_screen "06_settings_pipeline.png" "On-Device WhisperKit & MLX Models" -voxbriefScreen settings
  xcrun simctl terminate "$IPHONE_UDID" "$IPHONE_APP_BUNDLE_ID" 2>/dev/null || true
fi

# --- 5. Apple Watch Capture Routine -------------------------------------------

capture_watch_screen() {
  local filename="$1"
  local description="$2"
  shift 2 || true

  echo "  ⌚ Watch: $description ($filename)..."
  xcrun simctl terminate "$WATCH_UDID" "$WATCH_APP_BUNDLE_ID" 2>/dev/null || true
  sleep 0.4

  if [[ $# -gt 0 ]]; then
    xcrun simctl launch "$WATCH_UDID" "$WATCH_APP_BUNDLE_ID" "$@" >/dev/null
  else
    xcrun simctl launch "$WATCH_UDID" "$WATCH_APP_BUNDLE_ID" >/dev/null
  fi
  sleep 2.5

  xcrun simctl io "$WATCH_UDID" screenshot "$WATCH_OUTPUT_DIR/$filename" >/dev/null
  cp "$WATCH_OUTPUT_DIR/$filename" "$FASTLANE_DIR/$filename"
}

if [[ "$CAPTURE_WATCH" == "true" ]]; then
  echo "-> Capturing Apple Watch screenshots..."
  capture_watch_screen "watch_01_instant_capture.png" "Instant 1-Tap Capture"
  capture_watch_screen "watch_02_recording_active.png" "Active Recording & Waveform" -voxbriefWatchRecording
  capture_watch_screen "watch_03_notes_queue.png" "Offline Storage Queue" -voxbriefWatchNotes
  xcrun simctl terminate "$WATCH_UDID" "$WATCH_APP_BUNDLE_ID" 2>/dev/null || true
fi

# --- 6. Promotional Asset Generation ------------------------------------------

if [[ "$SKIP_PROMO" != "true" && -f "$SCRIPT_DIR/generate_promo_assets.py" ]]; then
  echo "-> Generating promotional graphics and device mockups..."
  python3 "$SCRIPT_DIR/generate_promo_assets.py" \
    --iphone-dir "$IPHONE_OUTPUT_DIR" \
    --watch-dir "$WATCH_OUTPUT_DIR"
fi

echo ""
echo "================================================================"
echo "✅ Screenshot capture complete!"
echo "================================================================"
if [[ "$CAPTURE_IPHONE" == "true" ]]; then
  echo "iPhone Screenshots ($IPHONE_OUTPUT_DIR):"
  ls -lh "$IPHONE_OUTPUT_DIR"/*.png 2>/dev/null | awk '{print "  - " $9 " (" $5 ")"}' || true
fi
if [[ "$CAPTURE_WATCH" == "true" ]]; then
  echo "Apple Watch Screenshots ($WATCH_OUTPUT_DIR):"
  ls -lh "$WATCH_OUTPUT_DIR"/*.png 2>/dev/null | awk '{print "  - " $9 " (" $5 ")"}' || true
fi
if [[ "$SKIP_PROMO" != "true" && -d "$REPO_ROOT/docs/assets/promo" ]]; then
  echo "Promotional Graphics ($REPO_ROOT/docs/assets/promo):"
  ls -lh "$REPO_ROOT/docs/assets/promo"/*.png 2>/dev/null | awk '{print "  - " $9 " (" $5 ")"}' || true
fi

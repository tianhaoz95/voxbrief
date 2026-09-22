#!/usr/bin/env bash
# Runs the full unit test suite for Voxbrief (macOS and iOS).
#
# Usage:
#   ./scripts/run_unit_tests.sh         # runs both macOS and iOS unit tests
#   ./scripts/run_unit_tests.sh --mac   # runs macOS unit tests only
#   ./scripts/run_unit_tests.sh --ios   # runs iOS unit tests only
#
# Optional environment variables:
#   IPHONE_NAME="iPhone 17 Pro Max"    # override the iOS simulator device name

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

RUN_MAC=true
RUN_IOS=true

for arg in "$@"; do
  case "$arg" in
    --mac|--macos)
      RUN_MAC=true
      RUN_IOS=false
      ;;
    --ios)
      RUN_MAC=false
      RUN_IOS=true
      ;;
    -h|--help)
      echo "Usage: $0 [--mac] [--ios]"
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      exit 1
      ;;
  esac
done

if command -v xcodegen >/dev/null 2>&1; then
  echo "-> Regenerating Xcode project with xcodegen..."
  xcodegen generate >/dev/null
fi

if [ "$RUN_MAC" = true ]; then
  echo "==> Running macOS Unit Tests (VoxbriefMacTests)..."
  xcodebuild test \
    -project Voxbrief.xcodeproj \
    -scheme VoxbriefMac \
    -destination 'platform=macOS' \
    CODE_SIGNING_ALLOWED=NO \
    -only-testing:VoxbriefMacTests
  echo "✅ macOS unit tests passed!"
fi

if [ "$RUN_IOS" = true ]; then
  echo "==> Locating iOS simulator..."
  DEVICE_ID=""
  if [ -n "${IPHONE_NAME:-}" ]; then
    DEVICE_ID=$(xcrun simctl list devices available -j | jq -r --arg name "$IPHONE_NAME" '
      .devices | to_entries[] | .value[] |
      select(.isAvailable == true and .name == $name) |
      .udid
    ' | head -n 1)
  fi

  if [ -z "$DEVICE_ID" ]; then
    DEVICE_ID=$(xcrun simctl list devices available -j | jq -r '
      .devices | to_entries[] | .value[] |
      select(.isAvailable == true and (.name | startswith("iPhone")) and .state == "Booted") |
      .udid
    ' | head -n 1)
  fi

  if [ -z "$DEVICE_ID" ]; then
    DEVICE_ID=$(xcrun simctl list devices available -j | jq -r '
      .devices | to_entries[] | .value[] |
      select(.isAvailable == true and (.name | startswith("iPhone"))) |
      .udid
    ' | head -n 1)
  fi

  if [ -z "$DEVICE_ID" ]; then
    echo "error: No available iPhone simulator found." >&2
    exit 1
  fi

  DEVICE_NAME=$(xcrun simctl list devices available -j | jq -r --arg id "$DEVICE_ID" '
    .devices | to_entries[] | .value[] | select(.udid == $id) | .name
  ' | head -n 1)

  echo "==> Booting simulator '$DEVICE_NAME' ($DEVICE_ID) if needed..."
  xcrun simctl boot "$DEVICE_ID" 2>/dev/null || true

  echo "==> Running iOS Unit Tests (VoxbriefTests on $DEVICE_NAME)..."
  xcodebuild test \
    -project Voxbrief.xcodeproj \
    -scheme Voxbrief \
    -destination "platform=iOS Simulator,id=$DEVICE_ID" \
    CODE_SIGNING_ALLOWED=NO \
    -only-testing:VoxbriefTests
  echo "✅ iOS unit tests passed!"
fi

echo "🎉 All requested unit tests completed successfully!"

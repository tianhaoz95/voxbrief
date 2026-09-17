#!/usr/bin/env bash
# Shared helpers for scripts/run_*.sh. Not meant to be executed directly.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_PATH="$REPO_ROOT/build/DerivedData"

# Regenerates Voxbrief.xcodeproj from project.yml if xcodegen is installed,
# so the simulator always runs what project.yml describes.
regenerate_project() {
  if command -v xcodegen >/dev/null 2>&1; then
    echo "-> Regenerating Xcode project via xcodegen..."
    (cd "$REPO_ROOT" && xcodegen generate >/dev/null)
  else
    echo "-> xcodegen not found on PATH; using the existing Voxbrief.xcodeproj as-is."
  fi
}

# Prints the UDID of a simulator matching an exact device name. Prefers an
# already-booted instance of that device, otherwise the first shutdown match.
find_simulator_udid() {
  local device_name="$1"
  local devices_json
  devices_json="$(xcrun simctl list devices available -j)"

  local booted_udid
  booted_udid="$(echo "$devices_json" | jq -r --arg name "$device_name" \
    '.devices[] | .[] | select(.name == $name and .state == "Booted") | .udid' | head -n1)"
  if [[ -n "$booted_udid" ]]; then
    echo "$booted_udid"
    return
  fi

  echo "$devices_json" | jq -r --arg name "$device_name" \
    '.devices[] | .[] | select(.name == $name) | .udid' | head -n1
}

# Boots the given simulator UDID (no-op if already booted) and brings up Simulator.app.
boot_simulator() {
  local udid="$1"
  local state
  state="$(xcrun simctl list devices -j | jq -r --arg udid "$udid" \
    '.devices[] | .[] | select(.udid == $udid) | .state')"

  if [[ "$state" != "Booted" ]]; then
    echo "-> Booting simulator $udid..."
    xcrun simctl boot "$udid"
  fi
  # Best-effort: bring up the Simulator.app window if a GUI session is available.
  # Harmless (and non-fatal) if there is no display, e.g. a headless/CI shell.
  open -a Simulator >/dev/null 2>&1 || true
}

# Builds a scheme for a given simulator destination.
build_app() {
  local scheme="$1"
  local udid="$2"

  echo "-> Building $scheme for simulator $udid (this can take a minute)..."
  xcodebuild build \
    -project "$REPO_ROOT/Voxbrief.xcodeproj" \
    -scheme "$scheme" \
    -destination "id=$udid" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    CODE_SIGNING_ALLOWED=NO
}

# Finds the built .app bundle path for a product name under DerivedData.
find_app_path() {
  local product_name="$1"
  find "$DERIVED_DATA_PATH/Build/Products" -maxdepth 2 -name "${product_name}.app" 2>/dev/null | head -n1
}

install_and_launch() {
  local udid="$1"
  local app_path="$2"
  local bundle_id="$3"

  echo "-> Installing $(basename "$app_path") on $udid..."
  xcrun simctl install "$udid" "$app_path"

  echo "-> Launching $bundle_id on $udid..."
  xcrun simctl launch "$udid" "$bundle_id" >/dev/null
}

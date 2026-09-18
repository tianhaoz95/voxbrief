#!/usr/bin/env bash
# Builds a Release archive of Voxbrief (with VoxbriefWatch and both widget
# extensions embedded) and uploads it to App Store Connect for TestFlight.
#
# Signing is fully automatic: xcodebuild manages certificates and provisioning
# profiles itself via an App Store Connect API key, so there is no manually
# exported .p12 distribution certificate or keychain wrangling to do here.
# You need:
#
#   1. An App Store Connect API key (App Manager role or higher) as three
#      pieces of credential -- its private key file (.p8), Key ID, and
#      Issuer ID. Create one at https://appstoreconnect.apple.com/access/api.
#   2. Your Apple Developer Team ID (Membership Details at
#      https://developer.apple.com/account).
#   3. An app record already created in App Store Connect with bundle ID
#      com.jacksonzhou666.voxbrief.app -- this script does not create it.
#
# Usage:
#   APPLE_TEAM_ID=ABCDE12345 ./scripts/release_testflight.sh
#
# Credentials are read from these env vars (first match wins per line -- the
# FA_* names are used automatically if already present in your shell, as they
# are in this environment):
#   ASC_KEY_ID     / FA_ASC_KEY_ID      -- App Store Connect API Key ID
#   ASC_ISSUER_ID  / FA_ASC_ISSUER_ID   -- App Store Connect API Issuer ID
#   ASC_KEY_PATH   / FA_KEY_LOCATION    -- path to the AuthKey_<KEY_ID>.p8 file
#   APPLE_TEAM_ID                        -- Apple Developer Team ID (no fallback)
#
# The build number (CFBundleVersion) is set to the current UTC timestamp so
# repeated uploads never collide with a previous build's number.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$REPO_ROOT/build/release"
ARCHIVE_PATH="$BUILD_DIR/Voxbrief.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
EXPORT_OPTIONS_PLIST="$BUILD_DIR/ExportOptions.plist"

ASC_KEY_ID="${ASC_KEY_ID:-${FA_ASC_KEY_ID:-}}"
ASC_ISSUER_ID="${ASC_ISSUER_ID:-${FA_ASC_ISSUER_ID:-}}"
ASC_KEY_PATH="${ASC_KEY_PATH:-${FA_KEY_LOCATION:-}}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:-}"

# --- Validate credentials ---------------------------------------------------

missing=()
[[ -z "$ASC_KEY_ID" ]] && missing+=("ASC_KEY_ID (or FA_ASC_KEY_ID)")
[[ -z "$ASC_ISSUER_ID" ]] && missing+=("ASC_ISSUER_ID (or FA_ASC_ISSUER_ID)")
[[ -z "$ASC_KEY_PATH" ]] && missing+=("ASC_KEY_PATH (or FA_KEY_LOCATION)")
[[ -z "$APPLE_TEAM_ID" ]] && missing+=("APPLE_TEAM_ID")

if [[ ${#missing[@]} -gt 0 ]]; then
  echo "error: missing required credentials:" >&2
  for m in "${missing[@]}"; do echo "  - $m" >&2; done
  exit 1
fi

if [[ ! -f "$ASC_KEY_PATH" ]]; then
  echo "error: App Store Connect API key not found at: $ASC_KEY_PATH" >&2
  exit 1
fi

# --- Validate app icons exist (a missing 1024x1024 icon fails App Store ----
# --- validation late, after a full archive build -- catch it up front) -----

check_app_icon() {
  local iconset="$1"
  local label="$2"
  if ! find "$iconset" -maxdepth 1 -iname "*.png" 2>/dev/null | grep -q .; then
    echo "error: $label has no app icon image yet (only Contents.json is present)." >&2
    echo "  Add a real 1024x1024 icon before releasing: $iconset" >&2
    return 1
  fi
}

icon_ok=true
check_app_icon "$REPO_ROOT/VoxbriefApp/Resources/Assets.xcassets/AppIcon.appiconset" "The iOS app" || icon_ok=false
check_app_icon "$REPO_ROOT/VoxbriefWatch/Resources/Assets.xcassets/AppIcon.appiconset" "The watch app" || icon_ok=false
if [[ "$icon_ok" != "true" ]]; then
  exit 1
fi

# --- Build ------------------------------------------------------------------

echo "-> Regenerating Xcode project via xcodegen..."
(cd "$REPO_ROOT" && xcodegen generate)

BUILD_NUMBER="$(date -u +%Y%m%d%H%M)"
echo "-> Using build number $BUILD_NUMBER (CFBundleVersion)"

mkdir -p "$BUILD_DIR"
rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH"

echo "-> Archiving Voxbrief (Release, embeds VoxbriefWatch + both widget extensions)..."
# CODE_SIGN_IDENTITY is pinned to "Apple Development", not "Apple Distribution": the app's
# linked SPM package targets (MLX, WhisperKit, etc.) are auto-categorized by Xcode as
# "development" signing regardless of build configuration, so forcing a Distribution
# identity project-wide here conflicts with them ("has conflicting provisioning settings").
# The separate -exportArchive step below still re-signs the final app/extensions with a
# proper Distribution identity for the App Store -- that's a distinct signing pass from
# this one. On a machine/CI runner with no existing "Apple Development" certificate+key in
# its keychain, -allowProvisioningUpdates will mint a brand-new one; on an ephemeral CI
# runner that's an orphan every time (the private key never leaves that run's keychain), so
# CI pins and reuses one persisted certificate instead (see .github/workflows/testflight.yml)
# rather than accumulating new ones until Apple's per-team certificate cap is hit.
xcodebuild archive \
  -project "$REPO_ROOT/Voxbrief.xcodeproj" \
  -scheme Voxbrief \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  -destination "generic/platform=iOS" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_KEY_PATH" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGNING_REQUIRED=YES \
  CODE_SIGN_STYLE=Automatic \
  CODE_SIGN_IDENTITY="Apple Development" \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER"

cat > "$EXPORT_OPTIONS_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store</string>
	<key>teamID</key>
	<string>$APPLE_TEAM_ID</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>destination</key>
	<string>upload</string>
</dict>
</plist>
PLIST

echo "-> Exporting and uploading to App Store Connect (TestFlight)..."
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS_PLIST" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_KEY_PATH" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID"

echo "✅ Build $BUILD_NUMBER uploaded to App Store Connect."
echo "   It will appear in TestFlight once Apple finishes processing (usually a few minutes)."

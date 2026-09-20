#!/usr/bin/env bash
# Deep-sign the built VoxbriefMac.app, rebuild a signed DMG, and optionally notarize.
#
#   ./scripts/sign-desktop.sh                 # sign the .app and build a signed .dmg
#   ./scripts/sign-desktop.sh --notarize      # ...then notarize and staple
#   ./scripts/sign-desktop.sh --verify-only   # just report on what's already signed
#
# Operates on an already-built .app (see scripts/release-mac.sh, which builds it first via plain
# `xcodebuild build -configuration Release` -- no archive/export needed for direct Developer ID
# distribution, unlike scripts/release_testflight.sh's App Store Connect upload flow).
#
# No nested-binary deep-signing loop here (unlike e.g. a Tauri app bundling a Node runtime):
# `find VoxbriefMac.app/Contents -type f -exec file {} \; | grep Mach-O` on a Release build shows
# WhisperKit and MLX Swift link statically into the single VoxbriefMac executable -- no embedded
# frameworks, no spawned helper process, nothing else to sign. If that ever changes (a future SPM
# dependency ships as a dynamic .framework), re-add the inside-out signing loop -- see
# ~/GitHub/nana/scripts/sign-desktop.sh for what that looks like when it's actually needed.
#
# Identity:
#   FA_MAC_IDENTITY   full identity string; otherwise a "Developer ID Application"
#                     cert is preferred, falling back to "Apple Development"
#                     (fine for running locally, NOT distributable or notarizable).
#
# Notarization auth, best first:
#   FA_NOTARY_PROFILE                        a `notarytool store-credentials` profile
#   FA_ASC_ISSUER_ID + one of:
#     FA_KEY_LOCATION      explicit path to the .p8 (key id read off the filename)
#     FA_ASC_KEY_ID        looked up in ~/.appstoreconnect/private_keys/
#   FA_APPLE_ID + FA_APP_PASSWORD + FA_TEAM_ID   app-specific password
#
# Same FA_* / ~/.appstoreconnect/private_keys/ conventions as scripts/release_testflight.sh, so
# the one App Store Connect API key already set up for TestFlight uploads can notarize too, as
# long as it was created with at least the Developer role (App Manager, used for TestFlight
# uploads, does not necessarily grant notarization access -- if notarization fails with an auth
# error, create a second key with the Developer role in App Store Connect > Users and Access >
# Integrations > App Store Connect API, and point FA_ASC_KEY_ID/FA_KEY_LOCATION at it instead).
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
APP="$ROOT/build/release-mac/Build/Products/Release/VoxbriefMac.app"
ENTITLEMENTS="$ROOT/VoxbriefMac/Entitlements.plist"
OUT_DMG="$ROOT/build/release-mac/dmg/VoxbriefMac-signed.dmg"
VOLUME_NAME="Voxbrief"

NOTARIZE=0
VERIFY_ONLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --notarize)    NOTARIZE=1; shift ;;
    --verify-only) VERIFY_ONLY=1; shift ;;
    -h|--help)     sed -n '2,10p' "$0"; exit 0 ;;
    *) echo "!! unknown argument: $1" >&2; exit 2 ;;
  esac
done

[ -d "$APP" ] || {
  echo "!! no app bundle at:" >&2
  echo "   $APP" >&2
  echo "   build it first: ./scripts/release-mac.sh --skip-build=false, or see that script's build step" >&2
  exit 1
}

# ---------------------------------------------------------------- identity

pick_identity() {
  if [ -n "${FA_MAC_IDENTITY:-}" ]; then echo "$FA_MAC_IDENTITY"; return; fi
  local devid
  devid="$(security find-identity -v -p codesigning 2>/dev/null \
            | grep "Developer ID Application" | head -1 \
            | sed 's/.*"\(.*\)".*/\1/')"
  if [ -n "$devid" ]; then echo "$devid"; return; fi
  security find-identity -v -p codesigning 2>/dev/null \
    | grep "Apple Development" | head -1 | sed 's/.*"\(.*\)".*/\1/'
}

IDENTITY="$(pick_identity)"
[ -n "$IDENTITY" ] || {
  echo "!! no code signing identity in the keychain." >&2
  echo "   Xcode > Settings > Accounts > Manage Certificates > + " >&2
  exit 1
}

DISTRIBUTABLE=1
case "$IDENTITY" in
  *"Developer ID Application"*) ;;
  *) DISTRIBUTABLE=0 ;;
esac

echo "==> identity: $IDENTITY"
if [ "$DISTRIBUTABLE" -eq 0 ]; then
  cat <<'EOF'

   !! This is a DEVELOPMENT certificate, not "Developer ID Application".
      The signed app will run on this Mac, but it cannot be notarized and
      Gatekeeper will refuse it on anyone else's machine.

      To fix: Xcode > Settings > Accounts > select the team >
      Manage Certificates > + > Developer ID Application.
      Only the Account Holder of the developer program can create one.

      Continuing so the pipeline can be verified end to end.

EOF
fi

# ------------------------------------------------------------------ verify

report() {
  echo "==> verifying"
  codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | sed 's/^/    /' || true
  echo "==> entitlements on the app"
  codesign -d --entitlements - --xml "$APP" 2>/dev/null \
    | plutil -convert xml1 -o - - 2>/dev/null | grep -E "<key>|<true|<false" | sed 's/^/    /' || true
  echo "==> Gatekeeper assessment"
  spctl -a -vvv -t exec "$APP" 2>&1 | sed 's/^/    /' || true
}

if [ "$VERIFY_ONLY" -eq 1 ]; then report; exit 0; fi

# -------------------------------------------------------------------- sign

echo "==> signing the app bundle"
codesign --force --sign "$IDENTITY" --timestamp --options runtime \
  --entitlements "$ENTITLEMENTS" \
  "$APP"

report

# The notary service rejects any binary carrying com.apple.security.get-task-allow (it permits a
# debugger to attach) -- a first-party, statically-linked app like this one won't normally carry
# it, but it costs nothing to confirm rather than find out from a rejection email.
echo "==> checking for get-task-allow (a notarization blocker)"
if codesign -d --entitlements - --xml "$APP" 2>/dev/null \
     | plutil -convert xml1 -o - - 2>/dev/null | grep -q "get-task-allow"; then
  echo "!! get-task-allow is set on the app bundle -- refusing to continue." >&2
  exit 1
fi
echo "    clean"

# --------------------------------------------------------------------- dmg

echo "==> building a DMG from the signed app"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
mkdir -p "$(dirname "$OUT_DMG")"
rm -f "$OUT_DMG"
hdiutil create -volname "$VOLUME_NAME" -srcfolder "$STAGE" \
  -ov -format UDZO "$OUT_DMG" >/dev/null
codesign --force --sign "$IDENTITY" --timestamp "$OUT_DMG"
echo "    $OUT_DMG"

# --------------------------------------------------------------- notarize

if [ "$NOTARIZE" -eq 0 ]; then
  echo
  echo "Signed. To notarize (required before anyone else can open it):"
  echo "  ./scripts/sign-desktop.sh --notarize"
  exit 0
fi

if [ "$DISTRIBUTABLE" -eq 0 ]; then
  echo "!! cannot notarize with a development certificate — see above." >&2
  exit 1
fi

# Three ways in, best first. An App Store Connect API key is preferred over an app-specific
# password: it is not tied to anyone's Apple ID password, it can be revoked on its own, and the
# SAME key uploads the iOS build in scripts/release_testflight.sh.
# Note altool and notarytool disagree on how to find the .p8 — altool looks it up by key id in a
# well-known directory, notarytool wants an explicit path — so keeping it at
# ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8 satisfies both.
# FA_KEY_LOCATION, if set, is the .p8 itself and wins over the conventional locations. The key id
# can be read back off the filename, so setting it separately is optional.
if [ -n "${FA_KEY_LOCATION:-}" ]; then
  ASC_KEY="${FA_KEY_LOCATION/#\~/$HOME}"
  if [ -z "${FA_ASC_KEY_ID:-}" ]; then
    base="$(basename "$ASC_KEY")"; base="${base%.p8}"
    FA_ASC_KEY_ID="${base#AuthKey_}"
  fi
else
  ASC_KEY="$HOME/.appstoreconnect/private_keys/AuthKey_${FA_ASC_KEY_ID:-none}.p8"
  [ -f "$ASC_KEY" ] || ASC_KEY="$HOME/private_keys/AuthKey_${FA_ASC_KEY_ID:-none}.p8"
fi

AUTH=()
if [ -n "${FA_NOTARY_PROFILE:-}" ]; then
  AUTH=(--keychain-profile "$FA_NOTARY_PROFILE")
elif [ -n "${FA_ASC_KEY_ID:-}" ] && [ -n "${FA_ASC_ISSUER_ID:-}" ] && [ -f "$ASC_KEY" ]; then
  AUTH=(--key "$ASC_KEY" --key-id "$FA_ASC_KEY_ID" --issuer "$FA_ASC_ISSUER_ID")
elif [ -n "${FA_APPLE_ID:-}" ] && [ -n "${FA_APP_PASSWORD:-}" ] && [ -n "${FA_TEAM_ID:-}" ]; then
  AUTH=(--apple-id "$FA_APPLE_ID" --password "$FA_APP_PASSWORD" --team-id "$FA_TEAM_ID")
else
  if [ -n "${FA_ASC_KEY_ID:-}" ] && [ ! -f "$ASC_KEY" ]; then
    echo "!! FA_ASC_KEY_ID is set but no key file at:" >&2
    echo "   ~/.appstoreconnect/private_keys/AuthKey_${FA_ASC_KEY_ID}.p8" >&2
    echo >&2
  fi
  cat >&2 <<'EOF'
!! no notarization credentials.

   Recommended — store credentials once as a keychain profile so nothing else has
   to be managed locally:

     xcrun notarytool store-credentials Voxbrief \
       --key ~/.appstoreconnect/private_keys/AuthKey_XXXXXXXXXX.p8 \
       --key-id XXXXXXXXXX --issuer xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
     export FA_NOTARY_PROFILE=Voxbrief

   Or reuse the same App Store Connect API key as scripts/release_testflight.sh:

       export FA_ASC_KEY_ID=... FA_ASC_ISSUER_ID=... FA_KEY_LOCATION=~/.appstoreconnect/private_keys/AuthKey_....p8

   Or, the older way: FA_APPLE_ID + FA_APP_PASSWORD + FA_TEAM_ID, with an
   app-specific password from appleid.apple.com > Sign-In and Security.
EOF
  exit 1
fi

echo "==> submitting to the notary service (this takes a few minutes)"
xcrun notarytool submit "$OUT_DMG" "${AUTH[@]}" --wait

echo "==> stapling"
xcrun stapler staple "$OUT_DMG"
# Staple the app too, so a copy dragged out of the DMG validates offline.
xcrun stapler staple "$APP"

echo "==> final assessment"
spctl -a -vvv -t exec "$APP" 2>&1 | sed 's/^/    /' || true

echo
echo "Done: $OUT_DMG"

#!/usr/bin/env bash
# Build, verify, package, and optionally notarize a production macOS app.
set -euo pipefail

APP_DIR="${1:?app dir e.g. checklist_entry}"
PRODUCT="${2:?product name e.g. InspectionEntry}"
BUNDLE_ID="${3:?bundle id}"
TEAM="${DEVELOPMENT_TEAM:-9DZ78A7F2H}"
SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-Developer ID Application}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_ROOT="$ROOT/apps/$APP_DIR"
DIST_DIR="$ROOT/dist/macos/$APP_DIR"

if [[ ! -d "$APP_ROOT/macos" ]]; then
  echo "macOS Flutter app not found: $APP_ROOT" >&2
  exit 1
fi

if [[ -f "$ROOT/.env.local" ]]; then
  # shellcheck disable=SC1091
  set -a
  source "$ROOT/.env.local"
  set +a
fi
if [[ -z "${SUPABASE_URL:-}" || -z "${SUPABASE_ANON_KEY:-}" ]]; then
  echo "SUPABASE_URL and SUPABASE_ANON_KEY are required in .env.local or the environment." >&2
  exit 1
fi
if [[ "$SUPABASE_URL" == *"iqcxgtpcfhoapnklxdyl"* ]]; then
  echo "Refusing to build: the configured URL belongs to the unrelated smart-meters project." >&2
  exit 1
fi
if ! security find-identity -v -p codesigning | grep -Fq "$SIGN_IDENTITY"; then
  echo "Code-signing identity not found: $SIGN_IDENTITY" >&2
  exit 1
fi

DART_DEFINES=(
  --dart-define=SUPABASE_URL="$SUPABASE_URL"
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"
  --dart-define=APP_ENV="${RELEASE_APP_ENV:-production}"
  --dart-define=DEMO_LOGIN=false
)

cd "$APP_ROOT"
flutter pub get >/dev/null

set +e
flutter build macos --release "${DART_DEFINES[@]}"
BUILD_RC=$?
set -e
if [[ $BUILD_RC -ne 0 ]]; then
  echo "flutter build failed ($BUILD_RC); retrying with explicit Xcode signing settings…"
  flutter build macos --config-only --release "${DART_DEFINES[@]}"
  (
    cd "$APP_ROOT/macos"
    xcodebuild -workspace Runner.xcworkspace -scheme Runner \
      -configuration Release -destination 'platform=macOS' \
      PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
      CODE_SIGN_STYLE=Automatic \
      DEVELOPMENT_TEAM="$TEAM" \
      CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
      -allowProvisioningUpdates build
  )
fi

BUILT="$APP_ROOT/build/macos/Build/Products/Release/${PRODUCT}.app"
if [[ ! -d "$BUILT" ]]; then
  echo "Release app not found: $BUILT" >&2
  exit 1
fi

ACTUAL_BUNDLE_ID="$(defaults read "$BUILT/Contents/Info" CFBundleIdentifier)"
if [[ "$ACTUAL_BUNDLE_ID" != "$BUNDLE_ID" ]]; then
  echo "Bundle identifier mismatch: expected $BUNDLE_ID, found $ACTUAL_BUNDLE_ID" >&2
  exit 1
fi
codesign --verify --deep --strict --verbose=2 "$BUILT"

mkdir -p "$DIST_DIR"
PACKAGE="$DIST_DIR/${PRODUCT}-macOS.zip"
ditto -c -k --sequesterRsrc --keepParent "$BUILT" "$PACKAGE"

if [[ -n "${APPLE_NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$PACKAGE" \
    --keychain-profile "$APPLE_NOTARY_PROFILE" --wait
  xcrun stapler staple "$BUILT"
  codesign --verify --deep --strict --verbose=2 "$BUILT"
  ditto -c -k --sequesterRsrc --keepParent "$BUILT" "$PACKAGE"
fi

codesign -dvv "$BUILT" 2>&1 | grep -E 'Authority|TeamIdentifier|Identifier'
echo "Release package: $PACKAGE"
echo "Supabase: $SUPABASE_URL"

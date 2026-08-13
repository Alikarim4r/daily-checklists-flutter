#!/usr/bin/env bash
# Build a signed Android App Bundle for one checklist application.
set -euo pipefail

APP_DIR="${1:?app dir e.g. checklist_entry}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_ROOT="$ROOT/apps/$APP_DIR"

if [[ ! -d "$APP_ROOT/android" ]]; then
  echo "Android Flutter app not found: $APP_ROOT" >&2
  exit 1
fi
if [[ -f "$ROOT/.env.local" ]]; then
  # shellcheck disable=SC1091
  set -a
  source "$ROOT/.env.local"
  set +a
fi
if [[ -z "${SUPABASE_URL:-}" || -z "${SUPABASE_ANON_KEY:-}" ]]; then
  echo "SUPABASE_URL and SUPABASE_ANON_KEY are required." >&2
  exit 1
fi
if [[ "$SUPABASE_URL" == *"iqcxgtpcfhoapnklxdyl"* ]]; then
  echo "Refusing to build against the unrelated smart-meters project." >&2
  exit 1
fi

if [[ -z "${ANDROID_KEYSTORE_PATH:-}" && "$(uname -s)" == "Darwin" ]]; then
  LOCAL_SIGNING_DIR="$HOME/Library/Application Support/Daily Checklists Signing"
  LOCAL_KEYSTORE="$LOCAL_SIGNING_DIR/android-release.jks"
  if [[ -f "$LOCAL_KEYSTORE" ]] && command -v security >/dev/null 2>&1; then
    export ANDROID_KEYSTORE_PATH="$LOCAL_KEYSTORE"
    export ANDROID_KEY_ALIAS="${ANDROID_KEY_ALIAS:-daily-checklists-release}"
    export ANDROID_KEYSTORE_PASSWORD="$(security find-generic-password \
      -a alimind-daily-checklists \
      -s com.alimind.daily-checklists.android.store-password \
      -w 2>/dev/null || true)"
    export ANDROID_KEY_PASSWORD="$(security find-generic-password \
      -a alimind-daily-checklists \
      -s com.alimind.daily-checklists.android.key-password \
      -w 2>/dev/null || true)"
  fi
fi
if [[ ! -f "$APP_ROOT/android/key.properties" && -z "${ANDROID_KEYSTORE_PATH:-}" ]]; then
  echo "Configure android/key.properties or ANDROID_KEYSTORE_* variables first." >&2
  exit 1
fi

RELEASE_APP_ENV="${RELEASE_APP_ENV:-production}"

cd "$APP_ROOT"
flutter pub get >/dev/null
flutter build appbundle --release \
  --obfuscate \
  --split-debug-info="$ROOT/dist/symbols/android/$APP_DIR" \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY" \
  --dart-define=APP_ENV="$RELEASE_APP_ENV" \
  --dart-define=DEMO_LOGIN=false
flutter build apk --release \
  --obfuscate \
  --split-debug-info="$ROOT/dist/symbols/android/$APP_DIR" \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY" \
  --dart-define=APP_ENV="$RELEASE_APP_ENV" \
  --dart-define=DEMO_LOGIN=false

mkdir -p "$ROOT/dist/android/$APP_DIR"
cp "$APP_ROOT/build/app/outputs/bundle/release/app-release.aab" \
  "$ROOT/dist/android/$APP_DIR/${APP_DIR}.aab"
cp "$APP_ROOT/build/app/outputs/flutter-apk/app-release.apk" \
  "$ROOT/dist/android/$APP_DIR/${APP_DIR}.apk"
echo "Release bundle: $ROOT/dist/android/$APP_DIR/${APP_DIR}.aab"
echo "Release APK: $ROOT/dist/android/$APP_DIR/${APP_DIR}.apk"

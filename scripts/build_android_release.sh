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
if [[ ! -f "$APP_ROOT/android/key.properties" && -z "${ANDROID_KEYSTORE_PATH:-}" ]]; then
  echo "Configure android/key.properties or ANDROID_KEYSTORE_* variables first." >&2
  exit 1
fi

cd "$APP_ROOT"
flutter pub get >/dev/null
flutter build appbundle --release \
  --obfuscate \
  --split-debug-info="$ROOT/dist/symbols/android/$APP_DIR" \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY" \
  --dart-define=APP_ENV="${APP_ENV:-production}" \
  --dart-define=DEMO_LOGIN=false
flutter build apk --release \
  --obfuscate \
  --split-debug-info="$ROOT/dist/symbols/android/$APP_DIR" \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY" \
  --dart-define=APP_ENV="${APP_ENV:-production}" \
  --dart-define=DEMO_LOGIN=false

mkdir -p "$ROOT/dist/android/$APP_DIR"
cp "$APP_ROOT/build/app/outputs/bundle/release/app-release.aab" \
  "$ROOT/dist/android/$APP_DIR/${APP_DIR}.aab"
cp "$APP_ROOT/build/app/outputs/flutter-apk/app-release.apk" \
  "$ROOT/dist/android/$APP_DIR/${APP_DIR}.apk"
echo "Release bundle: $ROOT/dist/android/$APP_DIR/${APP_DIR}.aab"
echo "Release APK: $ROOT/dist/android/$APP_DIR/${APP_DIR}.apk"

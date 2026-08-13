#!/usr/bin/env bash
# Build an obfuscated, signed iOS IPA for one checklist application.
set -euo pipefail

APP_DIR="${1:?app dir e.g. checklist_entry}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_ROOT="$ROOT/apps/$APP_DIR"

if [[ ! -d "$APP_ROOT/ios" ]]; then
  echo "iOS Flutter app not found: $APP_ROOT" >&2
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

EXPORT_ARGS=(--export-method "${IOS_EXPORT_METHOD:-app-store}")
if [[ -n "${IOS_EXPORT_OPTIONS_PLIST:-}" ]]; then
  if [[ ! -f "$IOS_EXPORT_OPTIONS_PLIST" ]]; then
    echo "Export options file not found: $IOS_EXPORT_OPTIONS_PLIST" >&2
    exit 1
  fi
  EXPORT_ARGS=(--export-options-plist "$IOS_EXPORT_OPTIONS_PLIST")
fi

cd "$APP_ROOT"
flutter pub get >/dev/null
flutter build ipa --release \
  "${EXPORT_ARGS[@]}" \
  --obfuscate \
  --split-debug-info="$ROOT/dist/symbols/ios/$APP_DIR" \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY" \
  --dart-define=APP_ENV="${APP_ENV:-production}" \
  --dart-define=DEMO_LOGIN=false

mkdir -p "$ROOT/dist/ios/$APP_DIR"
for ipa in "$APP_ROOT"/build/ios/ipa/*.ipa; do
  cp "$ipa" "$ROOT/dist/ios/$APP_DIR/"
done
echo "Release IPA directory: $ROOT/dist/ios/$APP_DIR"

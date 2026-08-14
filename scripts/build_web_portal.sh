#!/usr/bin/env bash
# Build portal + Flutter web apps into web_deploy/ (GitHub Pages style).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
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

# Base path the apps are served under.
#
# On a custom domain the site is the origin root, so the apps resolve at
# /entry/, /viewer/, /admin/. On the project Pages URL the site lives under
# /<repo>/, which stays the default so an unconfigured build is unchanged.
#
# Set WEB_BASE_HREF="" (or "/") for a root-served custom domain.
if [[ -n "${WEB_BASE_HREF+x}" ]]; then
  BASE_HREF="${WEB_BASE_HREF%/}"        # tolerate a trailing slash
else
  BASE_HREF="/daily-checklists-flutter"
fi

# Written into the published output so the custom domain survives a redeploy:
# this directory replaces the branch wholesale, so a CNAME created from the
# repository settings alone would be lost on the next publish.
PAGES_CNAME="${PAGES_CNAME:-}"

OUT="$ROOT/web_deploy"
rm -rf "$OUT"
mkdir -p "$OUT" "$OUT/downloads/android" "$OUT/downloads/macos"
touch "$OUT/.nojekyll"

if [[ -n "$PAGES_CNAME" ]]; then
  printf '%s\n' "$PAGES_CNAME" >"$OUT/CNAME"
  echo "CNAME: $PAGES_CNAME"
fi

rsync -a --exclude 'downloads' "$ROOT/web_portal/" "$OUT/"

build_web() {
  local dir="$1" dest="$2" href="$3"
  echo "=== web $dest ==="
  cd "$ROOT/$dir"
  flutter pub get >/dev/null || flutter pub get --offline >/dev/null
  flutter build web --release --no-pub \
    --dart-define=SUPABASE_URL="$SUPABASE_URL" \
    --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY" \
    --dart-define=APP_ENV="${RELEASE_APP_ENV:-production}" \
    --dart-define=DEMO_LOGIN=false \
    --base-href "$href"
  mkdir -p "$OUT/$dest"
  rsync -a --delete build/web/ "$OUT/$dest/"
}

build_web apps/checklist_entry entry "$BASE_HREF/entry/"
build_web apps/checklist_viewer viewer "$BASE_HREF/viewer/"
build_web apps/checklist_admin admin "$BASE_HREF/admin/"

# Signed Android APKs if already packaged into dist.
copy_apk() {
  local src="$1" name="$2" app_dir="$3"
  local expected actual_line actual_name actual_code sdk_root aapt_bin
  local apksigner_bin certificate_dn
  expected="$(awk '/^version:/{print $2; exit}' "$ROOT/apps/$app_dir/pubspec.yaml")"
  sdk_root="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
  aapt_bin="$(find "$sdk_root/build-tools" -type f -name aapt 2>/dev/null | sort -V | tail -1)"
  apksigner_bin="$(find "$sdk_root/build-tools" -type f -name apksigner 2>/dev/null | sort -V | tail -1)"
  if [[ ! -f "$src" || -z "$aapt_bin" || -z "$apksigner_bin" ]]; then
    echo "skip apk $name (missing artifact or version inspector)"
    return
  fi
  if [[ -z "${JAVA_HOME:-}" && -d "/Applications/Android Studio.app/Contents/jbr/Contents/Home" ]]; then
    export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
  fi
  actual_line="$("$aapt_bin" dump badging "$src" | head -1)"
  actual_name="$(sed -n "s/.*versionName='\\([^']*\\)'.*/\\1/p" <<<"$actual_line")"
  actual_code="$(sed -n "s/.*versionCode='\\([^']*\\)'.*/\\1/p" <<<"$actual_line")"
  if [[ "$actual_name+$actual_code" != "$expected" ]]; then
    echo "skip apk $name (artifact $actual_name+$actual_code, expected $expected)"
    return
  fi
  certificate_dn="$("$apksigner_bin" verify --print-certs "$src" 2>/dev/null \
    | sed -n 's/^Signer #1 certificate DN: //p; s/^V2 Signer: certificate DN: //p' \
    | head -1)"
  if [[ -z "$certificate_dn" || "$certificate_dn" == *"Android Debug"* ]]; then
    echo "skip apk $name (not production signed)"
    return
  fi
  cp "$src" "$OUT/downloads/android/$name"
  echo "apk $name ($expected)"
}
copy_apk "$ROOT/dist/android/checklist_entry/checklist_entry.apk" inspection-entry.apk checklist_entry
copy_apk "$ROOT/dist/android/checklist_viewer/checklist_viewer.apk" inspection-viewer.apk checklist_viewer
copy_apk "$ROOT/dist/android/checklist_admin/checklist_admin.apk" inspection-admin.apk checklist_admin

# Notarized/signed macOS zips from dist if present.
zip_mac() {
  local src="$1" zipname="$2" app_dir="$3" product="$4"
  local expected expected_name expected_build actual_name actual_build
  local verify_dir app_path
  expected="$(awk '/^version:/{print $2; exit}' "$ROOT/apps/$app_dir/pubspec.yaml")"
  expected_name="${expected%%+*}"
  expected_build="${expected##*+}"
  if [[ ! -f "$src" ]]; then
    echo "skip mac $zipname (missing artifact)"
    return
  fi
  actual_name="$(unzip -p "$src" "$product.app/Contents/Info.plist" \
    | plutil -extract CFBundleShortVersionString raw -o - - 2>/dev/null || true)"
  actual_build="$(unzip -p "$src" "$product.app/Contents/Info.plist" \
    | plutil -extract CFBundleVersion raw -o - - 2>/dev/null || true)"
  if [[ "$actual_name" != "$expected_name" || "$actual_build" != "$expected_build" ]]; then
    echo "skip mac $zipname (artifact $actual_name+$actual_build, expected $expected)"
    return
  fi
  verify_dir="$(mktemp -d)"
  unzip -q "$src" -d "$verify_dir"
  app_path="$verify_dir/$product.app"
  if [[ ! -d "$app_path" ]] \
    || ! codesign --verify --deep --strict "$app_path" >/dev/null 2>&1 \
    || ! codesign -dvv "$app_path" 2>&1 | grep -Fq 'Authority=Developer ID Application' \
    || ! xcrun stapler validate "$app_path" >/dev/null 2>&1; then
    rm -rf "$verify_dir"
    echo "skip mac $zipname (Developer ID/notarization verification failed)"
    return
  fi
  rm -rf "$verify_dir"
  cp "$src" "$OUT/downloads/macos/$zipname"
  echo "mac $zipname ($expected)"
}
zip_mac "$ROOT/dist/macos/checklist_entry/InspectionEntry-macOS.zip" Inspection-Entry-macOS.zip checklist_entry InspectionEntry
zip_mac "$ROOT/dist/macos/checklist_viewer/InspectionViewer-macOS.zip" Inspection-Viewer-macOS.zip checklist_viewer InspectionViewer
zip_mac "$ROOT/dist/macos/checklist_admin/InspectionAdmin-macOS.zip" Inspection-Admin-macOS.zip checklist_admin InspectionAdmin

echo "web_deploy ready: $OUT"

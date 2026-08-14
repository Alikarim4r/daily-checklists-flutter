#!/usr/bin/env bash
# Verify that no client-identifying asset can reach a release build.
#
# Run before signing. With no argument it checks the working tree; pass an APK
# to check what actually got packaged into an artefact.
#
#   scripts/verify_release_assets.sh
#   scripts/verify_release_assets.sh dist/android/checklist_entry/checklist_entry.apk
#
# Exits non-zero on the first thing found, so it is safe to chain before a
# build or an upload.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="${1:-}"
fail=0

# Names and values that must never ship. Kept literal so the check is obvious.
FORBIDDEN_NAMES=(
  moehe_logo
  moehe_logo_drive
  logo_waseef
  logo_footer2
)
FORBIDDEN_STRINGS=(
  MOEHE
  Waseef
  Elegancia
  "Ministry of Education"
  "Evaluation Institute"
  "Shared Services Division"
  "Secretary General"
  66170852
  "معهد التقييم"
  "قطاع الخدمات"
)

report() { printf '  %-46s %s\n' "$1" "$2"; }

check_dir() {
  local dir="$1" label="$2"
  echo "== $label"

  for n in "${FORBIDDEN_NAMES[@]}"; do
    local hits
    hits="$( { find "$dir" -name "*${n}*" 2>/dev/null || true; } | wc -l | tr -d ' ')"
    report "asset name: $n" "$hits"
    if [ "$hits" != "0" ]; then fail=1; fi
  done

  for s in "${FORBIDDEN_STRINGS[@]}"; do
    local hits
    hits="$( { grep -rl "$s" "$dir" 2>/dev/null || true; } | wc -l | tr -d ' ')"
    report "string: $s" "$hits"
    if [ "$hits" != "0" ]; then fail=1; fi
  done

  # Demo replacements must be present, or branding silently disappears.
  local demo
  demo="$( { find "$dir" -name '*_logo_demo*' 2>/dev/null || true; } | wc -l | tr -d ' ')"
  report "demo logos present (expect >0)" "$demo"
  if [ "$demo" = "0" ]; then fail=1; fi

  # Building identifiers must be the synthetic ones.
  local bj
  bj="$( { find "$dir" -name buildings.json 2>/dev/null || true; } | head -1)"
  if [ -n "$bj" ]; then
    local real demo_pins
    real="$(grep -c '66170852' "$bj" 2>/dev/null || true)"
    demo_pins="$(grep -c 'DEMO-' "$bj" 2>/dev/null || true)"
    report "buildings.json real PINs (expect 0)" "$real"
    report "buildings.json demo PINs (expect >0)" "$demo_pins"
    if [ "$real" != "0" ]; then fail=1; fi
    if [ "$demo_pins" = "0" ]; then fail=1; fi
  fi
}

if [ -z "$TARGET" ]; then
  check_dir "$ROOT/packages/checklist_shared/assets" "source assets (working tree)"
else
  [ -f "$TARGET" ] || { echo "No such APK: $TARGET" >&2; exit 2; }
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  unzip -q "$TARGET" 'assets/flutter_assets/*' -d "$tmp"
  check_dir "$tmp" "packaged APK: $(basename "$TARGET")"

  # Package identity must not drift: a changed applicationId is a different app.
  if command -v aapt >/dev/null 2>&1 || [ -n "${ANDROID_HOME:-}" ]; then
    aapt_bin="$(command -v aapt || find "${ANDROID_HOME:-$HOME/Library/Android/sdk}/build-tools" \
      -type f -name aapt 2>/dev/null | sort -V | tail -1)"
    if [ -n "$aapt_bin" ]; then
      pkg="$("$aapt_bin" dump badging "$TARGET" 2>/dev/null \
        | sed -n "s/.*package: name='\([^']*\)'.*/\1/p")"
      report "applicationId" "$pkg"
      case "$pkg" in
        com.moehe.checklists.*) ;;
        *) echo "  applicationId changed — refusing" >&2; fail=1 ;;
      esac
    fi
  fi
fi

echo
if [ "$fail" -eq 0 ]; then
  echo "PASS — nothing client-identifying found."
else
  echo "FAIL — see the non-zero rows above." >&2
fi
exit "$fail"

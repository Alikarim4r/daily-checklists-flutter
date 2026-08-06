#!/usr/bin/env bash
# Build macOS app with Apple Development signing + keychain access.
# Loads SUPABASE_* from .env.local (Daily Checklists project only).
set -euo pipefail

APP_DIR="${1:?app dir e.g. checklist_entry}"
PRODUCT="${2:?product name e.g. InspectionEntry}"
BUNDLE_ID="${3:?bundle id}"
TEAM="${DEVELOPMENT_TEAM:-9DZ78A7F2H}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_ROOT="$ROOT/apps/$APP_DIR"

if [[ -f "$ROOT/.env.local" ]]; then
  # shellcheck disable=SC1091
  set -a; source "$ROOT/.env.local"; set +a
fi
if [[ -z "${SUPABASE_URL:-}" || -z "${SUPABASE_ANON_KEY:-}" ]]; then
  echo "SUPABASE_URL and SUPABASE_ANON_KEY required in .env.local" >&2
  exit 1
fi
if [[ "${SUPABASE_URL}" == *"iqcxgtpcfhoapnklxdyl"* ]]; then
  echo "Refusing: .env.local points at smart-meters." >&2
  exit 1
fi
DART_DEFINES=(
  --dart-define=SUPABASE_URL="$SUPABASE_URL"
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"
  --dart-define=APP_ENV="${APP_ENV:-staging}"
)

write_entitlements() {
  local path="$1"
  local debug_extra="$2"
  cat > "$path" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.app-sandbox</key>
	<true/>
${debug_extra}	<key>com.apple.security.network.client</key>
	<true/>
	<key>com.apple.security.network.server</key>
	<true/>
	<key>com.apple.security.files.user-selected.read-write</key>
	<true/>
	<key>com.apple.security.files.downloads.read-write</key>
	<true/>
	<key>com.apple.security.personal-information.photos-library</key>
	<true/>
	<key>com.apple.security.print</key>
	<true/>
	<key>keychain-access-groups</key>
	<array>
		<string>\$(AppIdentifierPrefix)${BUNDLE_ID}</string>
	</array>
</dict>
</plist>
EOF
}

write_entitlements "$APP_ROOT/macos/Runner/DebugProfile.entitlements" $'\t<key>com.apple.security.cs.allow-jit</key>\n\t<true/>\n'
write_entitlements "$APP_ROOT/macos/Runner/Release.entitlements" ''

CFG="$APP_ROOT/macos/Runner/Configs/AppInfo.xcconfig"
grep -q 'DEVELOPMENT_TEAM' "$CFG" || echo "DEVELOPMENT_TEAM = $TEAM" >> "$CFG"
perl -i -pe "s/^DEVELOPMENT_TEAM = .*/DEVELOPMENT_TEAM = $TEAM/" "$CFG"

python3 - <<PY
from pathlib import Path
import re
pbx = Path("$APP_ROOT/macos/Runner.xcodeproj/project.pbxproj")
t = pbx.read_text()
t = t.replace('CODE_SIGN_IDENTITY = "-";', 'CODE_SIGN_IDENTITY = "Apple Development";')
if 'DEVELOPMENT_TEAM = $TEAM;' not in t:
    t = t.replace('CODE_SIGN_STYLE = Automatic;', 'CODE_SIGN_STYLE = Automatic;\n\t\t\t\tDEVELOPMENT_TEAM = $TEAM;')
else:
    t = re.sub(r'DEVELOPMENT_TEAM = [^;]+;', 'DEVELOPMENT_TEAM = $TEAM;', t)
pbx.write_text(t)
PY

cd "$APP_ROOT"
flutter pub get >/dev/null

# Prefer flutter build; if provisioning blocks it, fall back to xcodebuild
# with -allowProvisioningUpdates (needed after macOS/Xcode profile refresh).
set +e
flutter build macos --debug "${DART_DEFINES[@]}"
BUILD_RC=$?
set -e
if [[ $BUILD_RC -ne 0 ]]; then
  echo "flutter build failed ($BUILD_RC); retrying with xcodebuild -allowProvisioningUpdates…"
  flutter build macos --config-only --debug "${DART_DEFINES[@]}"
  (
    cd "$APP_ROOT/macos"
    xcodebuild -workspace Runner.xcworkspace -scheme Runner -configuration Debug \
      -destination 'platform=macOS' \
      CODE_SIGN_STYLE=Automatic \
      DEVELOPMENT_TEAM="$TEAM" \
      CODE_SIGN_IDENTITY='Apple Development' \
      -allowProvisioningUpdates \
      build
  )
fi

BUILT="$APP_ROOT/build/macos/Build/Products/Debug/${PRODUCT}.app"
if [[ ! -d "$BUILT" ]]; then
  # xcodebuild may only refresh DerivedData — copy from there
  DERIVED=$(ls -td "$HOME"/Library/Developer/Xcode/DerivedData/Runner-*/Build/Products/Debug/"${PRODUCT}.app" 2>/dev/null | head -1 || true)
  if [[ -n "${DERIVED:-}" && -d "$DERIVED" ]]; then
    mkdir -p "$(dirname "$BUILT")"
    rm -rf "$BUILT"
    cp -R "$DERIVED" "$BUILT"
  fi
fi
if [[ ! -d "$BUILT" ]]; then
  echo "Built app not found: $BUILT" >&2
  exit 1
fi

codesign -dvv "$BUILT" 2>&1 | grep -E 'Authority|TeamIdentifier|Identifier' || true

pkill -f "/${PRODUCT}.app/" 2>/dev/null || true
rm -rf "$HOME/Applications/${PRODUCT}.app"
cp -R "$BUILT" "$HOME/Applications/${PRODUCT}.app"
# Keep original signature — do not ad-hoc re-sign (breaks launch).
xattr -cr "$HOME/Applications/${PRODUCT}.app" 2>/dev/null || true
echo "Installed: $HOME/Applications/${PRODUCT}.app"
echo "FROM: $BUILT"
echo "SUPABASE: $SUPABASE_URL"

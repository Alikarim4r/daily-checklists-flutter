#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-entry}"
DEVICE="${2:-}"

case "$APP" in
  entry) DIR="$ROOT/apps/checklist_entry" ;;
  viewer) DIR="$ROOT/apps/checklist_viewer" ;;
  admin) DIR="$ROOT/apps/checklist_admin" ;;
  *) echo "Usage: $0 {entry|viewer|admin} [device_id]"; exit 1 ;;
esac

cd "$DIR"
flutter pub get
if [[ -n "$DEVICE" ]]; then
  flutter run -d "$DEVICE"
else
  flutter run
fi

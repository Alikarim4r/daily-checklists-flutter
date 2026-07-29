#!/usr/bin/env bash
# Run Daily Checklists apps against THIS project's Supabase (independent).
#
# Usage:
#   cp .env.example .env.local   # fill Daily Checklists project URL + anon key
#   ./scripts/run_staging_app.sh entry|viewer|admin [extra flutter run args]

set -euo pipefail

APP="${1:-}"
shift || true

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [[ ! -f "$ROOT/.env.local" ]]; then
  echo "Missing $ROOT/.env.local" >&2
  echo "Copy .env.example and set SUPABASE_URL / SUPABASE_ANON_KEY for the Daily Checklists project." >&2
  exit 1
fi

# shellcheck disable=SC1091
set -a; source "$ROOT/.env.local"; set +a

if [[ -z "${SUPABASE_URL:-}" || -z "${SUPABASE_ANON_KEY:-}" ]]; then
  echo "SUPABASE_URL and SUPABASE_ANON_KEY are required in .env.local" >&2
  exit 1
fi

# Guard against accidentally pointing at smart-meters Staging
if [[ -z "${SUPABASE_URL:-}" ]]; then
  echo "SUPABASE_URL is empty. Configure a dedicated Daily Checklists Supabase project." >&2
  exit 1
fi
if [[ "${SUPABASE_URL}" == *"iqcxgtpcfhoapnklxdyl"* ]] \
  || [[ "${SUPABASE_URL}" == *"smart-meters"* ]] \
  || [[ "${APP_ENV:-}" == "smart-meters" ]]; then
  echo "Refusing to run: SUPABASE_URL/APP_ENV points at smart-meters." >&2
  echo "Daily Checklists must use its own Supabase project." >&2
  exit 1
fi

export APP_ENV="${APP_ENV:-staging}"

case "$APP" in
  entry)  DIR="apps/checklist_entry" ;;
  viewer) DIR="apps/checklist_viewer" ;;
  admin)  DIR="apps/checklist_admin" ;;
  *)
    echo "Usage: $0 entry|viewer|admin [flutter run args...]" >&2
    exit 1
    ;;
esac

cd "$ROOT/$DIR"
flutter pub get
flutter run \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY" \
  --dart-define=APP_ENV="$APP_ENV" \
  "$@"

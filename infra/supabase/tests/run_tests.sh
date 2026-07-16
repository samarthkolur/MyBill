#!/usr/bin/env bash
#
# Verify the Supabase migrations against a throwaway Postgres container.
#
# Applies, in order:
#   1. harness.sql        — stubs Supabase's auth/storage schemas + roles for plain PG
#   2. migrations/*.sql   — the real production migrations (lexicographic order)
#   3. test_rls.sql       — RLS + auth-sync assertions (aborts on first failure)
#
# Usage:  ./run_tests.sh        (from anywhere)
# Requires: docker, psql
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MIGRATIONS_DIR="$HERE/../migrations"

CONTAINER="mybill-migration-test"
PG_IMAGE="postgres:16-alpine"
PG_PASSWORD="postgres"
PG_PORT="55432"   # unlikely to collide with a local Postgres on 5432
export PGPASSWORD="$PG_PASSWORD"
PSQL=(psql -h localhost -p "$PG_PORT" -U postgres -d postgres -v ON_ERROR_STOP=1 --quiet)

cleanup() { docker rm -f "$CONTAINER" >/dev/null 2>&1 || true; }
trap cleanup EXIT

echo "==> Starting throwaway Postgres ($PG_IMAGE) on port $PG_PORT"
cleanup
docker run -d --name "$CONTAINER" \
  -e POSTGRES_PASSWORD="$PG_PASSWORD" \
  -p "$PG_PORT:5432" \
  "$PG_IMAGE" >/dev/null

echo "==> Waiting for Postgres to accept connections"
for _ in $(seq 1 30); do
  if "${PSQL[@]}" -c 'select 1' >/dev/null 2>&1; then break; fi
  sleep 1
done
"${PSQL[@]}" -c 'select 1' >/dev/null

echo "==> Applying test harness (Supabase auth/storage stubs)"
"${PSQL[@]}" -f "$HERE/harness.sql"

echo "==> Applying migrations"
for migration in "$MIGRATIONS_DIR"/*.sql; do
  echo "    - $(basename "$migration")"
  "${PSQL[@]}" -f "$migration"
done

echo "==> Running RLS / auth-sync assertions"
"${PSQL[@]}" -f "$HERE/test_rls.sql"

echo "==> SUCCESS: migrations apply cleanly and all assertions passed."

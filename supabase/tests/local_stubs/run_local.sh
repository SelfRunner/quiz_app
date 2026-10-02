#!/usr/bin/env bash
# LOCAL VALIDATION ONLY: applies the Supabase stubs + migrations to a fresh
# database on a plain PostgreSQL server (with pgTAP installed) and runs the
# pgTAP tests. Never point this at a Supabase project.
#
#   PGHOST=/path/to/socket PGPORT=5432 PGUSER=postgres ./supabase/tests/local_stubs/run_local.sh
#
# Requires: psql, a superuser connection, pgTAP (e.g. apt install postgresql-16-pgtap),
# and optionally pg_prove (falls back to psql + grep for "not ok").
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
db="${QUIZ_TEST_DB:-quiz_app_rls_test}"

psql -v ON_ERROR_STOP=1 -q -d postgres -c "drop database if exists \"$db\"" -c "create database \"$db\""

psql -v ON_ERROR_STOP=1 -q -d "$db" -f "$here/supabase_stubs.psql"
for f in "$root"/migrations/*.sql; do
  echo "applying $(basename "$f")"
  psql -v ON_ERROR_STOP=1 -q -d "$db" -f "$f"
done

status=0
for t in "$root"/tests/*.sql; do
  echo "== $(basename "$t")"
  if command -v pg_prove >/dev/null 2>&1; then
    pg_prove -d "$db" "$t" || status=1
  else
    out="$(psql -X -q -t -A -v ON_ERROR_STOP=1 -d "$db" -f "$t" 2>&1)" || status=1
    echo "$out"
    if grep -qE '^not ok|Looks like|ERROR' <<<"$out"; then status=1; fi
  fi
done
exit $status

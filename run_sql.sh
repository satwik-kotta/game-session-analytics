#!/usr/bin/env bash
# Usage: ./run_sql.sh [database]   (needs PostgreSQL and psql on PATH; run from the repository root)
# Connection settings come from the usual libpq variables (PGHOST, PGPORT, PGUSER, PGPASSWORD).
set -euo pipefail
DB=${1:-${PGDATABASE:-game}}
for f in sql/0*.sql; do echo "== $f"; psql -v ON_ERROR_STOP=1 -q -d "$DB" -f "$f"; done

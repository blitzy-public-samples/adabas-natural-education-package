#!/usr/bin/env bash
# Empty the CRUISE, CRUISE2 and YACHT Adabas files so the demo can be re-seeded
# from a clean state.
#
# "adadbm REFRESH=<fnr>" deletes every record in a file but keeps the file and
# its FDT, so there is no need to re-run create-adabas-files.sh afterwards -
# just re-run gen-seed.sh.
#
# Useful because seeding is additive: STORE always inserts, so seeding twice
# without a reset duplicates every record.
set -euo pipefail

command -v docker >/dev/null 2>&1 || export PATH="$HOME/.docker/bin:$PATH"

ADA="${ADA:-adabas-db}"
DBID="${DBID:-12}"

for fnr in 40 41 42; do
  docker exec "$ADA" sh -c \
    "cd /opt/softwareag/Adabas && ./adadbm DBID=$DBID REFRESH=$fnr" </dev/null 2>&1 \
    | grep -E 'REFRESH|-E-|-F-' || true
done

echo
docker exec "$ADA" sh -c \
  "cd /opt/softwareag/Adabas && ./adarep DBID=$DBID CONTENTS" </dev/null \
  | sed -n '/loaded on/,/^$/p' | grep -E 'File|CRUISE|YACHT'

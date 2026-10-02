#!/usr/bin/env bash
# Stage CSV_Files/ into the natural-ce container so the WORK* programs can read
# and write them.
#
# WORKFPGM, WORKFPGM1 and WORKOPGM use DEFINE WORK FILE with paths that were
# originally hardcoded to Windows locations (C:\FileSystem\Workfiles\...). They
# now point at $WORKDIR below. If you change one, change the other.
#
# Two container details matter here:
#   * natural-ce runs as sagadmin (uid 1724), so the target must be a directory
#     that user can write - /opt/softwareag/Natural/tmp is.
#   * docker cp lands files owned by root, which makes WRITE WORK fail with a
#     permission error. They have to be chowned afterwards, as root.
set -euo pipefail

command -v docker >/dev/null 2>&1 || export PATH="$HOME/.docker/bin:$PATH"

REPO="${REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
NAT="${NAT:-natural-ce}"
WORKDIR="${WORKDIR:-/opt/softwareag/Natural/tmp}"

for c in CRUISE.CSV CRUISENEW1.CSV CRUISENEW2.CSV; do
  src="$REPO/CSV_Files/$c"
  [ -f "$src" ] || { echo "missing $src" >&2; exit 1; }
  docker cp "$src" "$NAT:$WORKDIR/$c" >/dev/null
done

docker exec -u root "$NAT" sh -c "chown sagadmin:sagadmin $WORKDIR/*.CSV && chmod 664 $WORKDIR/*.CSV"

echo "staged work files in $NAT:$WORKDIR"
docker exec "$NAT" sh -c "ls -l $WORKDIR/*.CSV"

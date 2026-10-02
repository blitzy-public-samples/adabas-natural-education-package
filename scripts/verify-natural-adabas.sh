#!/usr/bin/env bash
# Verify the NaturalONE CE stack end-to-end WITHOUT the NaturalONE IDE.
# Proves: Natural runtime works, and Natural can read the Adabas demo DB.
set -uo pipefail

command -v docker >/dev/null 2>&1 || command -v docker >/dev/null 2>&1 || export PATH="$HOME/.docker/bin:$PATH"

NAT=natural-ce
ADA=adabas-db
DBID=12          # ADABAS_DBID in the adabas-db container
FNR=11           # EMPLOYEES-NAT, the file the SAMP4ONE DDM targets

# Strip the curses escape codes Natural emits so output is readable.
strip_ansi() { sed -e 's/\x1b\[[0-9;?]*[a-zA-Z]//g' -e 's/\x1b[()][0-9A-B]//g'; }

step() { printf '\n=== %s ===\n' "$1"; }

step "1. containers up"
docker ps --filter "name=$NAT" --filter "name=$ADA" \
  --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

step "2. name resolution: $NAT -> $ADA"
# dbmapping.txt uses uppercase ADABAS-DB; /etc/hosts lookup is case-insensitive.
docker exec "$NAT" getent hosts ADABAS-DB || echo "FAIL: ADABAS-DB does not resolve"

step "3. TCP reachability to Adabas port 60001"
docker exec "$NAT" sh -c \
  'timeout 5 bash -c "</dev/tcp/ADABAS-DB/60001" && echo OPEN || echo FAILED'

step "4. DBID -> host:port mapping the Adabas client will use"
docker exec "$NAT" grep -vE '^\s*#|^\s*$' /opt/softwareag/AdabasClient/config/dbmapping.txt

step "5. Adabas DB $DBID contents (expect file $FNR EMPLOYEES-NAT)"
docker exec "$ADA" sh -c "cd /opt/softwareag/Adabas && ./adarep DBID=$DBID CONTENTS" \
  | sed -n '/^ File Filename/,/^$/p'

step "6. Natural runtime only: HELLO-W (no database access)"
docker exec "$NAT" sh -c \
  'cd /opt/softwareag/Natural/bin && printf "\n\n\n" | ./natural BATCH STACK="(LOGON SAMP4ONE;HELLO-W;FIN)"' \
  2>&1 | strip_ansi

step "7. Natural -> Adabas: TEST-EMP (FIND on PERSONNEL-ID 50005000)"
out=$(docker exec "$NAT" sh -c \
  'cd /opt/softwareag/Natural/bin && printf "\n\n\n" | ./natural BATCH STACK="(LOGON SAMP4ONE;TEST-EMP;FIN)"' \
  2>&1 | strip_ansi)
printf '%s\n' "$out"

printf '\n--- verdict ---\n'
if printf '%s' "$out" | grep -q 'GIDDE'; then
  echo "PASS: Natural read a real record from Adabas (no NAT3148)."
elif printf '%s' "$out" | grep -qE '3148|NAT3[0-9]{3}'; then
  echo "FAIL: Adabas error. Fix: put both containers on one docker network:"
  echo "  docker network create adabas_natural"
  echo "  # then rerun both 'docker run' commands with --network adabas_natural"
  echo "  # and --network-alias adabas-db on the DB, dropping --add-host."
else
  echo "UNCLEAR: no record and no Adabas error code; inspect output above."
fi

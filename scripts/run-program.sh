#!/usr/bin/env bash
# Run one cataloged Natural program in the natural-ce container.
#
#   scripts/run-program.sh HISTOPGM Lefkas
#   scripts/run-program.sh HELLOWLD
#
# Anything after the program name is fed to the program on stdin, one argument
# per input prompt. Trailing newlines are appended automatically so Natural's
# "MORE >" pager does not stall the session.
set -uo pipefail

command -v docker >/dev/null 2>&1 || export PATH="$HOME/.docker/bin:$PATH"

NAT="${NAT:-natural-ce}"
LIB="${LIB:-EDUPKG}"
NH=/opt/softwareag/Natural

PROG="${1:-}"
if [ -z "$PROG" ]; then
  echo "usage: ${0##*/} <PROGRAM> [input ...]" >&2
  exit 1
fi
shift

# Build stdin: supplied inputs first, then enough newlines to page through output.
stdin=""
for a in "$@"; do stdin="$stdin$a\n"; done
for _ in $(seq 1 30); do stdin="$stdin\n"; done

# A distinct ETID per run matters: reusing one leaves an open Adabas user
# session behind, and the next run fails with "NAT3048 ... DB/Subcode 12/8",
# which reads like a missing file but is a session collision.
etid="R$(printf '%04d' $((RANDOM % 10000)))"

docker exec "$NAT" sh -c \
  "cd $NH/bin && printf '$stdin' | timeout 30 ./natural BATCH SM=ON ETID=$etid STACK=\"(LOGON $LIB;$PROG;FIN)\"" 2>&1 \
  | sed -e 's/\x1b\[[0-9;?]*[a-zA-Z]//g' -e 's/\x1b[()][0-9A-B]//g' \
  | tr -d '\033\016\017\r' \
  | sed -e 's/.*Software AG 2025//' -e 's/MORE *>//g'

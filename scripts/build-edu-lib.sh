#!/usr/bin/env bash
# Rebuild the EDUPKG Natural library from the education-package repo and
# catalog every member, then run the ones that need no Adabas file.
#
# Notes earned the hard way:
#  * Natural member names are max 8 chars and uppercase -> three get renamed.
#  * Copying files into fuser/<LIB>/SRC is not enough; each member must be
#    registered in FILEDIR.SAG with the ftouch utility.
#  * ftouch stamps each source as reporting or structured mode ("sm"). Most of
#    these samples are structured (DEFINE DATA / END-IF), so they are registered
#    with sm and cataloged with SM=ON; anything that fails is retried as
#    reporting mode.
#  * "STOW <name>" acts on the editor work area, so cataloging is
#    "READ <name>" then a bare "STOW".
set -uo pipefail

command -v docker >/dev/null 2>&1 || export PATH="$HOME/.docker/bin:$PATH"

REPO="${REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
NAT=natural-ce
LIB=${LIB:-EDUPKG}
NH=/opt/softwareag/Natural

# Natural library names are limited to 8 characters; a longer one fails every
# catalog with a confusing "NAT0400 Invalid library ID".
case "$LIB" in
  *[!A-Z0-9]*) echo "LIB must be uppercase alphanumeric: $LIB" >&2; exit 1 ;;
esac
if [ ${#LIB} -gt 8 ]; then
  echo "LIB must be 8 characters or fewer (got ${#LIB}: $LIB)" >&2; exit 1
fi
FUSER="$NH/fuser/$LIB"
FTOUCH="$NH/bin/ftouch"

NO_DB=(HELLOWLD COND CONDPGM LOCALVAR LOOPPGM LOOP2PGM ARRAYPGM ARRA2PGM)
DB=(HISTOPGM RETRIPGM RETRIPG1 RETOPPGM STOREPGM UPDATPGM DELETPGM
    WORKFPGM WORKFPG1 WORKOPGM)
DDMS=(CRUISE CRUISE2 YACHT)

strip_ansi() { sed -e 's/\x1b\[[0-9;?]*[a-zA-Z]//g' -e 's/\x1b[()][0-9A-B]//g'; }

nat() {  # nat <SM=ON|SM=OFF> <stack>
  docker exec "$NAT" sh -c \
    "cd $NH/bin && printf '\n\n\n\n\n\n' | ./natural BATCH $1 STACK=\"($2)\"" 2>&1 | strip_ansi
}
err() { tr -s ' ' | sed 's/lqq*k/\n/g; s/xx/\n/g' | grep -oE 'NAT[0-9]{4} [^|]{0,55}' | head -1; }
has_gp() { docker exec "$NAT" test -f "$FUSER/GP/$1.NGP"; }

# ---------------------------------------------------------------- stage -----
STAGE=$(mktemp -d); trap 'rm -rf "$STAGE"' EXIT
for f in "$REPO"/CodeSamples/*.NSP; do
  n=$(basename "$f" .NSP | tr '[:lower:]' '[:upper:]')
  case "$n" in HELLOWORLD) n=HELLOWLD;; RETRIPGM1) n=RETRIPG1;; WORKFPGM1) n=WORKFPG1;; esac
  cp "$f" "$STAGE/$n.NSP"
done
for f in "$REPO"/CodeSamples/DDM/*.NSD; do
  cp "$f" "$STAGE/$(basename "$f" .NSD | tr '[:lower:]' '[:upper:]').NSD"
done

docker exec "$NAT" rm -rf "$FUSER"
docker exec "$NAT" mkdir -p "$FUSER/SRC" "$FUSER/GP"
docker cp "$STAGE/." "$NAT:$FUSER/SRC/"

# ------------------------------------------------------- register (ftouch) --
# -d builds a fresh FILEDIR.SAG and must be paired with its own member, so the
# directory is created first against the DDM list and every member added after.
echo "=== registering members in FILEDIR.SAG (structured mode) ==="
first=1
docker exec "$NAT" sh -c "
cd $FUSER
for f in SRC/*.NSP SRC/*.NSD; do
  b=\$(basename \"\$f\")
  if [ $first = 1 ]; then :; fi
  flags='-s -a -f sm'
  [ ! -f FILEDIR.SAG ] && flags='-s -d -a sm'
  $FTOUCH lib=$LIB \$flags \"\$b\" >/dev/null 2>&1 || echo \"  ftouch failed: \$b\"
  # -d consumes its member silently on some builds; re-add to be certain.
  $FTOUCH lib=$LIB -s -a -f sm \"\$b\" >/dev/null 2>&1
done"
docker exec "$NAT" sh -c "ls $FUSER/FILEDIR.SAG" >/dev/null && echo "  FILEDIR.SAG built"

# ------------------------------------------------------------- catalog ------
echo
echo "=== cataloging DDMs ==="
for d in "${DDMS[@]}"; do
  out=$(nat "SM=ON" "LOGON $LIB;READ $d;STOW;FIN")
  if docker exec "$NAT" test -f "$FUSER/GP/$d.NGD"; then
    printf '  %-10s CATALOGED\n' "$d"
  else
    printf '  %-10s FAILED  %s\n' "$d" "$(printf '%s' "$out" | err)"
  fi
done

echo
echo "=== cataloging programs ==="
# The first structured STOW of a freshly registered member sometimes fails on a
# transient editor work-file error (NAT6805). Retry structured - re-stamping the
# source with sm each time - before considering reporting mode, otherwise one
# flake permanently demotes a structured program and it then fails for real with
# NAT0610/NAT0612. Report the STRUCTURED error when both modes fail, since that
# is the mode these samples are actually written in.
restamp() { # restamp <program> [sm]
  docker exec "$NAT" sh -c \
    "cd $FUSER && $FTOUCH lib=$LIB -s -a -f ${2:-} \"$1.NSP\"" >/dev/null 2>&1
}

for p in "${NO_DB[@]}" "${DB[@]}"; do
  struct_err=""
  cataloged=0
  for attempt in 1 2 3; do
    restamp "$p" sm
    out=$(nat "SM=ON" "LOGON $LIB;READ $p;STOW;FIN")
    if has_gp "$p"; then
      printf '  %-10s CATALOGED (structured)\n' "$p"; cataloged=1; break
    fi
    [ -z "$struct_err" ] && struct_err=$(printf '%s' "$out" | err)
  done
  [ "$cataloged" = 1 ] && continue

  # Only now try reporting mode, which needs the source re-stamped without sm.
  restamp "$p"
  out=$(nat "SM=OFF" "LOGON $LIB;READ $p;STOW;FIN")
  if has_gp "$p"; then printf '  %-10s CATALOGED (reporting)\n' "$p"; continue; fi

  # Leave the source stamped structured so a later manual retry behaves sanely.
  restamp "$p" sm
  printf '  %-10s FAILED  %s\n' "$p" "$struct_err"
done

# ----------------------------------------------------------------- run ------
echo
echo "=== running programs that need no database ==="
for p in "${NO_DB[@]}"; do
  has_gp "$p" || { printf '\n--- %s --- (not cataloged, skipped)\n' "$p"; continue; }
  printf '\n--- %s ---\n' "$p"
  nat "SM=ON" "LOGON $LIB;$p;FIN" | sed -e '1,2d' -e 's/MORE >.*//'
done

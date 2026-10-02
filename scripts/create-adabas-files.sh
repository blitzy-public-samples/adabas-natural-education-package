#!/usr/bin/env bash
# Create Adabas files 40/41/42 in DB 12 from the education package's DDM layouts.
# adafdu reads the FDT from the file named by $FDUFDT - not stdin - and that
# file must contain only field lines (no FIELDS header).
#   Natural N8.0 -> 8,U | P10.3 (13 digits) -> 7,P | P3.2 -> 3,P | P3.0 -> 2,P
#   DDM "D" column -> DE (descriptor) | DDM "N" column -> NU (null suppression)
set -euo pipefail
command -v docker >/dev/null 2>&1 || export PATH="$HOME/.docker/bin:$PATH"
ADA=adabas-db

cruise_fdt='01,CI,8,U,DE,NU
01,CK,1,A,NU
01,CL
02,CM,8,U,DE
02,CN,6,U,NU
01,CO
02,CP,8,U,DE,NU
02,CQ,6,U,NU
01,CR,20,A,DE
01,CS,20,A,DE
01,CT,8,U,DE,NU
01,CW
02,CX,7,P,NU
02,CY,7,P,NU
02,CZ,7,P,NU'

yacht_fdt='01,DB,8,U,DE,NU
01,DC,30,A,DE,NU
01,DD,30,A,DE,NU
01,DF,3,P,NU
01,DG,3,P,NU
01,DH,3,P,NU
01,DI,2,P,NU
01,DJ,2,P,NU
01,DK,3,P,NU
01,DL,2,P,NU'

load() { # load <fnr> <name> <fdt>
  printf '%s\n' "$3" | docker exec -i "$ADA" sh -c "cat > /tmp/$2.fdt"
  docker exec "$ADA" sh -c "cd /opt/softwareag/Adabas && FDUFDT=/tmp/$2.fdt ./adafdu \
    DBID=12 FILE=$1 NAME=$2 MAXISN=1000 DSSIZE=20B NISIZE=20B UISIZE=20B" </dev/null \
    2>&1 | grep -E 'LOADED|-E-|-F-'
}

load 41 CRUISE  "$cruise_fdt"
load 40 CRUISE2 "$cruise_fdt"
load 42 YACHT   "$yacht_fdt"
docker exec "$ADA" sh -c 'cd /opt/softwareag/Adabas && ./adarep DBID=12 CONTENTS' </dev/null \
  | sed -n '/loaded on/,/^$/p'

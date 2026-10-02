# Adabas & Natural Education Package

A fork of [SoftwareAG/adabas-natural-education-package](https://github.com/SoftwareAG/adabas-natural-education-package),
with the sample programs fixed so they compile and run against the Adabas and
Natural **Community Edition Docker containers** on Linux.

Upstream is archived and assumed a Windows virtual machine from Software AG's
University Relations department. This fork drops that requirement: everything
runs in two containers, driven from the shell.

> **What changed from upstream:** 7 programs were edited to compile and run, and
> `scripts/`, `docker-compose.yml` were added. See
> [Changes from upstream](#changes-from-upstream). No sample's logic was altered.

---

## Requirements

* Docker Engine 24+ with the Compose v2 plugin
* An **x86_64** host. Both Software AG images are `linux/amd64` only; on arm64
  (Apple Silicon) they run under emulation and are very slow.
* Nothing else. There is no language runtime or SDK to install — all compiling
  and running happens inside the containers.

## Quick start

```bash
docker compose up -d             # 1. start Adabas + Natural, wait for healthy
scripts/create-adabas-files.sh   # 2. create Adabas files 40, 41, 42
scripts/build-edu-lib.sh         # 3. catalog 3 DDMs + 18 programs
scripts/gen-seed.sh              # 4. seed CRUISE and YACHT with data
scripts/setup-workfiles.sh       # 5. stage CSV_Files/ for the WORK* programs
```

**Order matters between steps 3 and 4.** The seed program does `VIEW OF CRUISE`,
so it cannot compile until `build-edu-lib.sh` has cataloged the DDMs. Running
`gen-seed.sh` first fails with a clear message telling you to do step 3.

Then run anything:

```bash
scripts/run-program.sh HELLOWLD
scripts/run-program.sh HISTOPGM Lefkas
```

To confirm Natural can actually reach Adabas before anything else:

```bash
scripts/verify-natural-adabas.sh
```

That prints a pass/fail verdict after checking name resolution, TCP 60001, the
DBID-to-host mapping, the Adabas file list, and a real database read.

---

## Step by step

### 1. Start the containers

```bash
docker compose up -d
docker compose ps        # wait until both report healthy (up to ~2 minutes)
```

Both images ship healthchecks and Natural is gated on Adabas being healthy, so
`up -d` orders startup correctly.

> **Do not** connect these with `--add-host` and a host IP. The Natural
> container's `AdabasClient/config/dbmapping.txt` maps DBID 11 and 12 to
> `adatcp://ADABAS-DB:60001`, so Adabas must be reachable as the hostname
> `adabas-db` on a shared Docker network — which is what `docker-compose.yml`
> provides. Hostname lookups are case-insensitive, so the lowercase service name
> matches the uppercase entry in `dbmapping.txt`.

### 2. Create the Adabas files

The `adabas-ce` image creates a demo database (DBID 12) on first start, but it
does **not** contain the files these programs use. The DDMs in
`CodeSamples/DDM/` target DBID 12 files **40 (CRUISE2)**, **41 (CRUISE)** and
**42 (YACHT)**; upstream assumed the University Relations VM where they are
pre-loaded.

```bash
scripts/create-adabas-files.sh
```

This derives each FDT from the DDM field layouts. Two things to know if you edit
it: `adafdu` reads the FDT from the file named by the **`FDUFDT` environment
variable**, not stdin, and that file must contain **only field lines** — a
`FIELDS` header makes it fail. The type mapping used is:

| Natural (DDM) | Adabas FDT |
|---|---|
| `N8.0` | `8,U` |
| `P10.3` (13 digits) | `7,P` |
| `P3.2` | `3,P` |
| `P3.0` | `2,P` |
| DDM `D` column | `DE` (descriptor) |
| DDM `N` column | `NU` (null suppression) |

A "file already loaded" message on re-run means the file exists — treat it as
success.

### 3. Build the library

```bash
scripts/build-edu-lib.sh
```

Stages every source into Natural library `EDUPKG`, registers it, catalogs the
3 DDMs and 18 programs, then runs the programs that need no database. Override
the library with `LIB=` (8 characters max, uppercase) or the source tree with
`REPO=`.

Expected: **3 DDMs and 18 programs cataloged.**

This has to happen before seeding, because the seed program does
`VIEW OF CRUISE` and needs the DDM cataloged to compile.

### 4. Seed the data

```bash
scripts/gen-seed.sh
```

Generates a Natural program, catalogs it, runs it, and prints the resulting
record counts — **20 CRUISE and 16 YACHT**.

Seeding is additive (`STORE` always inserts), so the script refuses to run if
`CRUISE` already holds data. To start over:

```bash
scripts/reset-data.sh     # empties files 40, 41, 42 (adadbm REFRESH)
scripts/gen-seed.sh
```

`reset-data.sh` keeps the files and their FDTs, so there is no need to re-run
`create-adabas-files.sh`.

> **The CSVs in `CSV_Files/` are not Adabas load data.** They are Natural *work
> file* input for the `WORK*` programs, and they do not match the DDM layouts —
> they carry a yacht **name** where `CRUISE` has a numeric `ID-YACHT`, a combined
> `YYYYMMDD-HH` string where `CRUISE` has separate date and time fields, and one
> price where `CRUISE` has three.
>
> So the seed data is **derived**, not shipped: prices 2W/3W are 2x and 3x the
> CSV price, status is `'1'`, yacht type is `'Sailing Yacht'`. The full mapping
> is documented in the header of `scripts/gen-seed.sh`. Change it there if the
> exact values matter to you.

### 5. Stage the work files

```bash
scripts/setup-workfiles.sh
```

Needed only for `WORKFPGM`, `WORKFPG1` and `WORKOPGM`, which read and write the
CSVs through `DEFINE WORK FILE`. Without this they catalog fine and then fail at
runtime with `NAT1599 Attempt to execute READ/WRITE WORK to non-existent file`.

### 6. Run the programs

```bash
scripts/run-program.sh <PROGRAM> [input ...]
```

Arguments after the program name are fed to its input prompts in order.

```
scripts/run-program.sh HELLOWLD            ->  Hello world!
scripts/run-program.sh HISTOPGM Lefkas     ->  Values found for: Lefkas  Number: 4
scripts/run-program.sh LOCALVAR            ->  VAR2A: 1111.0  VAR2B: 222222.00
```

**Run the CRUD programs in order: `STOREPGM` → `UPDATPGM` → `DELETPGM`.** They
form a pipeline — `STOREPGM` copies `CRUISE` into `CRUISE2`, `UPDATPGM` modifies
it, `DELETPGM` empties it. Out of order, the later two have no data and look
broken.

---

## The programs

| Program | What it shows | Needs |
|---|---|---|
| `HELLOWLD` | `DISPLAY` — the classic first program | — |
| `COND` | Conditional logic on a salary value | — |
| `CONDPGM` | `DECIDE ON` with `FIRST` | — |
| `LOCALVAR` | Local variable formats and `REDEFINE` | — |
| `LOOPPGM` | `FOR` loop with `DECIDE ON` ranges | — |
| `LOOP2PGM` | Descending loop with range tests | — |
| `ARRAYPGM` | 2-dimensional array init and `WRITE (*,n)` | — |
| `ARRA2PGM` | Array copy, nested vs non-nested printing | — |
| `HISTOPGM` | `HISTOGRAM` — descriptor-only read, counts by harbor | CRUISE |
| `RETRIPGM` | `READ` loop over CRUISE with `PRINT` | CRUISE |
| `RETRIPG1` | Same, substituting `Skiatos` → `Naxos` | CRUISE |
| `RETOPPGM` | `FIND` + `READ` across CRUISE and YACHT | CRUISE, YACHT |
| `STOREPGM` | `STORE` + `END TRANSACTION` — CRUISE → CRUISE2 | CRUISE, CRUISE2 |
| `UPDATPGM` | `UPDATE` + `END TRANSACTION` | CRUISE2 |
| `DELETPGM` | `DELETE` + `END TRANSACTION` | CRUISE2 |
| `WORKFPGM` | `READ WORK FILE` of a CSV | work files |
| `WORKFPG1` | Read one CSV, `WRITE WORK` another | work files |
| `WORKOPGM` | Work file read/write with a different record layout | work files |

Three programs are renamed from upstream because **Natural member names are
limited to 8 characters**: `HelloWorld` → `HELLOWLD`, `RETRIPGM1` → `RETRIPG1`,
`WORKFPGM1` → `WORKFPG1`. The files on disk keep their original names; the
rename happens when they are staged into the library.

### `UPDATPGM` fails on purpose

`UPDATPGM` ends with `NAT1302 Division by zero not permitted`. **That is
correct behaviour, not a setup problem.** The upstream source divides
`PRICE-1W` by zero on the tenth record, behind a comment reading
`/* provoke error`. It is a debugging exercise. Do not "fix" it.

---

## Changes from upstream

Seven programs were edited. All three problems were environmental or
mechanical — no sample's logic was changed.

**1. Comment marker in the wrong column** — `ARRAYPGM`, `ARRA2PGM`, `RETRIPGM`,
`WORKFPGM`, `WORKFPGM1`, `WORKOPGM`

Natural treats `*` as a comment **only in column 1**. These files had lines of
whitespace-then-`*`, so inside `DEFINE DATA` the parser read them as field
definitions and failed with `NAT0243 Syntax error in DEFINE DATA
statement/structure` — pointing at the comment line, which sends you looking at
the data structure instead.

**2. Truncated sources** — `RETRIPGM`, `RETRIPGM1`

Both ended mid-`READ` loop with no `END-READ` and no `END`. `NAT0261 END
statement missing` was literally correct. Both closers were appended.

**3. Hardcoded Windows paths** — `WORKFPGM`, `WORKFPGM1`, `WORKOPGM`

```
DEFINE WORK FILE 1 'C:\FileSystem\Workfiles\CRUISE.CSV'          TYPE 'CSV'
DEFINE WORK FILE 1 'C:\Training\307-66E\Student\Workfiles\...'   TYPE 'CSV'
```

These compiled fine and failed only at runtime. Repointed to
`/opt/softwareag/Natural/tmp/`, which is where `scripts/setup-workfiles.sh`
stages the CSVs. If you change one, change the other.

---

## Working with Natural: things worth knowing

Collected while getting this running — none of it is obvious from the sources.

* **Member names are capped at 8 characters and must be uppercase.** Library
  names too: a 9-character library fails every catalog with the unhelpful
  `NAT0400 Invalid library ID`.
* **Copying sources into `fuser/<LIB>/SRC` is not enough.** Each member must be
  registered in `FILEDIR.SAG` with the `ftouch` utility, **one file per call** —
  it rejects globs and multiple filenames.
* **`ftouch` stamps each source as reporting or structured mode.** These samples
  are structured (`DEFINE DATA`, `END-IF`): register with the `sm` flag and
  catalog with `SM=ON`. Getting it wrong yields `NAT0610`, `NAT0612` or
  `NAT1155`, which look like syntax errors but are mode errors.
* **`STOW <name>` operates on the editor work area, not a library member.**
  Cataloging is `READ <name>` then a bare `STOW`; `STOW <name>` alone gives
  `NAT0083 SAVE or CATALOG command issued when work area empty`.
* **Pass a distinct `ETID=` to every run that updates data.** Reusing it leaves
  an open Adabas user session and the next run fails with
  `NAT3048 Error during Open processing. DB/Subcode 12/8` — which reads like a
  missing file but is a session collision.
* **`fuser` is a Docker volume.** The library lives outside the container
  filesystem; recreating the containers without preserving the volume discards
  it. Rerun `scripts/build-edu-lib.sh` rather than trying to persist it.
* **Natural pages output with a `MORE >` prompt.** In batch, feed it newlines or
  the session stalls until it is killed.

---

## License and attribution

Apache-2.0, inherited from upstream — see [LICENSE](LICENSE). The sample
programs are the work of Software AG and the Natural developer community.

> These tools are provided as-is and without warranty or support. They do not
> constitute part of the Software AG product suite.

For background on Adabas and Natural, see the
[Software AG TECHcommunity](https://tech.forums.softwareag.com/tag/Adabas-Natural).

# MOD-001 verification on real GEONET 30 s data

Production-data verification of MOD-001 using GEONET station
**0627** observations from **2026-04-01** (DOY 091). This data
is the load-bearing input for PNT Moni's monthly evaluation
pipeline, so reproducing the modification's intended behavior on
it is the strongest evidence available short of a full pipeline
re-run.

## Data

- **OBS** (RINEX, 30 s sampled, integer-second timing):
  `pntmoni-pipeline/data/raw/rinex/2026/091/06270910.26o.gz`
- **NAV** (BRDC mixed):
  `pntmoni-pipeline/data/raw/brdc/2026/BRDC00IGS_R_20260910000_01D_MN.rnx.gz`
- **L6** (24-hour concatenated):
  `pntmoni-pipeline/data/raw/l6/2026/091/2026091AX.l6`

These files come from PNT Moni's own pipeline working tree on
the operator's local host. They are **not** committed to this
fork; only the reset-event extracts (`resets_*.txt`) and this
README are. Outputs in `*.nmea`, `*.stat`, and `*.trace` are
gitignored to avoid republishing operational outputs that may be
considered sensitive.

## Configurations

Same `kinematic_regularly300.conf` as in the parent
verification (1Hz CLASLIB sample), placed in the parent
directory.

Two start times are exercised to expose alignment behavior:

- **Aligned**: `-ts 2026/04/01 00:00:00` (TOW 259200; **is** a
  multiple of 300)
- **Misaligned**: `-ts 2026/04/01 00:01:00` (TOW 259260; **not**
  a multiple of 300)

Both end at `-te 2026/04/01 00:59:30`.

## Results

### Aligned start

`resets_fork_geonet0627_aligned.txt` and
`resets_upstream_geonet0627_aligned.txt` are **identical**:

```
259500, 259800, 260100, 260400, 260700, 261000, 261300,
261600, 261900, 262200, 262500
```

11 resets, all multiples of 300. Both fork and upstream produce
the same schedule because the session start (TOW 259200) is
itself a multiple of 300, so upstream's first-obs-relative
schedule happens to coincide with the absolute-aligned
schedule.

### Misaligned start

| Branch | # resets | First reset TOW | All multiples of 300? |
|---|---|---|---|
| upstream | 11 | 259560 (= 259260 + 300) | **No** — none of the 11 reset TOWs are multiples of 300 |
| fork | 10 | 259800 (= first multiple of 300 ≥ T0+300−0.5) | **Yes** — all 10 reset TOWs are multiples of 300 |

Upstream resets at 259560, 259860, 260160, 260460, 260760,
261060, 261360, 261660, 261960, 262260, 262560 — anchored to
session start, none aligned to absolute GPS seconds.

Fork resets at 259800, 260100, 260400, 260700, 261000, 261300,
261600, 261900, 262200, 262500 — all aligned to multiples of
300 regardless of session start.

## Interpretation

This run satisfies the production-data dimension of MOD-001
verification:

1. **No regression** on a session whose start happens to align
   with the reset boundary (aligned case → identical outputs).
2. **Correct alignment** on a session whose start does not align
   (misaligned case → fork stays on absolute GPS seconds while
   upstream drifts with first-obs).

The original "受信機時計がずれていた" failure mode in MOD-001's
issue description — `timediff` falling below the configured
interval due to receiver clock offset — is **not** reproducible
from this data, because GEONET RINEX exports clean
integer-second observation timestamps regardless of the
receiver-side clock state. The MOD-001 fix is still the right
fix for that scenario (the rounding tolerance absorbs ±0.5 s of
offset), but the available evidence on the symptom that does
manifest in production is the **alignment drift** demonstrated
above. PNT Moni's TTFF aggregation requires reset epochs to be
consistent across files and sessions, which is exactly the
property the fork now provides and upstream does not.

## Reproducing

```bash
# Place the three input files anywhere; record their absolute paths.
OBS=/path/to/06270910.26o.gz
NAV=/path/to/BRDC00IGS_R_20260910000_01D_MN.rnx.gz
L6=/path/to/2026091AX.l6

# Decompress OBS and NAV into a temp dir.
TMP=$(mktemp -d)
gunzip -kc "$OBS" > "$TMP/0627.obs"
gunzip -kc "$NAV" > "$TMP/brdc.nav"

# Run from util/rnx2rtkp/ on the desired branch.
cd util/rnx2rtkp
LABEL=fork  # or `upstream` after `git checkout main`

# Aligned start (00:00:00):
./rnx2rtkp -ts 2026/04/01 00:00:00 -te 2026/04/01 00:59:30 \
    -x 2 -k ../../verification/MOD-001/kinematic_regularly300.conf \
    "$TMP/0627.obs" "$TMP/brdc.nav" "$L6" \
    -o ../../verification/MOD-001/geonet/0627_${LABEL}_reg300.nmea

# Misaligned start (00:01:00):
./rnx2rtkp -ts 2026/04/01 00:01:00 -te 2026/04/01 00:59:30 \
    -x 2 -k ../../verification/MOD-001/kinematic_regularly300.conf \
    "$TMP/0627.obs" "$TMP/brdc.nav" "$L6" \
    -o ../../verification/MOD-001/geonet/0627_${LABEL}_reg300_offset60.nmea

# Extract reset events:
for tag in reg300 reg300_offset60; do
    grep "regularly reset filter" \
        ../../verification/MOD-001/geonet/0627_${LABEL}_${tag}.nmea.trace \
        > ../../verification/MOD-001/geonet/resets_${LABEL}_geonet0627_${tag/reg300/aligned}.txt
done
```

(The script renames `reg300` to `aligned` and `reg300_offset60`
to `offset60` for the committed extract filenames.)

# MOD-001 verification — diff analysis

**Test target**: `make test_L6_bnx` (1Hz BINEX data, 1-hour window
starting 2019-08-27 16:00:00 UTC).

**Test data**:
- `data/0627239Q.bnx` (rover BINEX, 1Hz)
- `data/sept_2019239.nav` (broadcast nav)
- `data/2019239Q.l6` (CLAS L6 messages)

**Configurations exercised**:
- `kinematic_unix.conf` — upstream `kinematic.conf` with paths
  converted to forward slashes; `misc-regularly` not set
  (i.e., default 0 = disabled). Used for the regression test.
- `kinematic_regularly300.conf` — same as above plus
  `misc-regularly=300` to exercise the modified reset path.

**Branches compared**:
- `main` at `59b5dc5` (= upstream CLASLIB v0.8.3 + fork-init
  docs only, no code changes) — the *upstream* baseline.
- `mod-001-ttff-reset-interval` at `d3d54c4` — the *fork* with
  MOD-001 applied.

**Build profile**: macOS clang, no LAPACK
(`-D_POSIX_C_SOURCE=200809L -D_DARWIN_C_SOURCE`,
`LDLIBS=-lm`). The same profile is used for both branches, so
build-time differences are excluded.

---

## Result 1 — Regression test (`misc-regularly` disabled)

With `misc-regularly` unset, the modified condition in
`ppp_rtk_pos` and `relposvrs` short-circuits to false on the
first clause (`opt->regularly != 0`), exactly as upstream's
condition does. The new modulo and tolerance terms are never
evaluated, so the reset block is never entered.

Empirically:

```
$ diff -q 0627239Q_fork_regularly0.nmea 0627239Q_upstream_regularly0.nmea
(no output — files are bit-identical)

$ wc -l 0627239Q_*regularly0.nmea
    7160 0627239Q_fork_regularly0.nmea
    7160 0627239Q_upstream_regularly0.nmea
```

**Verdict**: PASS. MOD-001 introduces zero observable change
on workloads that don't enable `misc-regularly`.

---

## Result 2 — Behavioral test, 1Hz processing (`-ti 1`,
`misc-regularly=300`)

Reset events extracted from the trace log
(`grep "regularly reset filter"`):

| Run | # resets | TOWs (s) |
|---|---|---|
| upstream | 11 | 230720, 231020, 231320, 231620, 231920, 232220, 232520, 232820, 233120, 233420, 233720 |
| fork (MOD-001) | 10 | 231000, 231300, 231600, 231900, 232200, 232500, 232800, 233100, 233400, 233700 |

Upstream resets are spaced exactly 300 s apart but anchored at
**230720** — i.e. first-obs-time plus 300 s — and remain
anchored to that arbitrary epoch for the rest of the run. None
of the 11 upstream reset TOWs are integer multiples of 300.

Fork resets are also spaced exactly 300 s apart but every TOW
is an exact multiple of 300. The first reset is at 231000 (the
first multiple of 300 reached after the start of the
processing window), the last at 233700.

The count differs (10 vs. 11) because the absolute-aligned
schedule fits one fewer 300-s slot inside the same 1-hour
window than the first-obs-relative schedule does. This is the
intended difference, not a regression.

**Verdict**: PASS. Reset alignment to absolute GPS TOW is
demonstrated.

---

## Result 3 — Behavioral test, 30 s subsampling (`-ti 30`,
`misc-regularly=300`)

`-ti 30` forces the post-processor to consider only obs at
30 s nominal spacing, simulating sub-minute sampled data
(the actual operational scenario for PNT Moni's GEONET
evaluation).

| Run | # resets | TOWs (s) |
|---|---|---|
| upstream | 11 | 230730, 231030, 231330, 231630, 231930, 232230, 232530, 232830, 233130, 233430, 233730 |
| fork (MOD-001) | 10 | 231000, 231300, 231600, 231900, 232200, 232500, 232800, 233100, 233400, 233700 |

The fork's reset TOWs are identical between `-ti 1` and
`-ti 30`, demonstrating that the alignment is determined by
absolute GPS time (the modulo of TOW by `opt->regularly`)
rather than by the obs cadence or by the start of the run.

Upstream's reset TOWs **shift** between the two runs (230720 →
230730) because the first obs accepted under `-ti 30`
subsampling is 10 seconds later than under `-ti 1`, and
upstream anchors all subsequent resets to that moving
first-obs time. This is exactly the failure mode that PNT
Moni's TTFF measurement workflow needs to avoid: reset epochs
drift unpredictably with the data cadence and any clock
offset.

**Verdict**: PASS. Sub-minute sampled processing produces
absolute-aligned resets on the fork; upstream's reset schedule
is sensitive to the effective sampling cadence.

---

## What this verification does *not* cover

The available CLASLIB sample data is at 1 Hz with effectively
clean integer-second receiver timing, so the failure mode
described in MOD-001's "Issue" section — `timediff` falling
just below the configured interval (e.g., 29.999 vs. 30.0)
because of a non-trivial receiver clock offset on 30-second
sampled data — cannot be reproduced from the public test
suite alone.

The 1Hz tests above demonstrate three of the four properties
required for MOD-001 to be considered correct:

1. ✓ No regression on `misc-regularly`-disabled workloads
2. ✓ Resets fire at integer multiples of `opt->regularly`
3. ✓ Reset alignment is invariant to obs cadence
4. **Pending** — robustness to receiver clock offset on
   GEONET 30 s data

Property 4 should be re-confirmed once on a representative
PNT Moni production GEONET file (any 30-second RINEX whose
timestamps exhibit non-zero sub-second offset). The expected
fork behavior: reset still fires at multiples of
`opt->regularly` because `round()` absorbs the offset within
±0.5 s. The expected upstream behavior: reset cadence skips
or doubles, depending on the offset direction.

---

## Reproducing these results

```bash
# On mod-001-ttff-reset-interval:
OUTPUT_LABEL=fork bash verification/MOD-001/run.sh

# Then on main (or upstream tag):
git checkout main
OUTPUT_LABEL=upstream bash verification/MOD-001/run.sh

# Diff:
diff -q verification/MOD-001/0627239Q_fork_regularly0.nmea \
       verification/MOD-001/0627239Q_upstream_regularly0.nmea
diff verification/MOD-001/resets_fork_regularly300.txt \
     verification/MOD-001/resets_upstream_regularly300.txt
```

Run output, configurations, and extracted reset-event lists
are committed alongside this document for audit. Full `.trace`
and `.stat` files are gitignored as they are large and
regenerable from the script.

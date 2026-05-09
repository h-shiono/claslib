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

## Result 4 — Production GEONET 30 s data (station 0627,
2026-04-01)

Verified separately on station 0627's RINEX (30 s sampled,
clean integer-second timing) for DOY 091 of 2026. Two start
times are exercised to expose the alignment behavior:

| Start time | TOW at start | Multiple of 300? | Fork resets | Upstream resets | Identical? |
|---|---|---|---|---|---|
| 00:00:00 (aligned) | 259200 | yes | 11 at 259500…262500 (all multiples of 300) | 11 at 259500…262500 (all multiples of 300) | **yes** |
| 00:01:00 (misaligned) | 259260 | no | 10 at 259800…262500 (all multiples of 300) | 11 at 259560…262560 (**none** multiples of 300) | **no** |

**Aligned-start case** demonstrates no regression on real
GEONET 30 s data: when the session start happens to fall on a
reset boundary, fork and upstream produce the exact same reset
schedule.

**Misaligned-start case** demonstrates the fork's intended
behavior on real production timing: fork's reset epochs remain
on absolute multiples of `opt->regularly`, while upstream's
shift by 60 s to follow the session start.

Full extracts are in
[`geonet/`](./geonet/) (see
[`geonet/README.md`](./geonet/README.md) for reproduction
instructions and the rationale for not committing the
underlying NMEA / trace files).

**Verdict**: PASS. Production data confirms (a) no regression
on aligned sessions and (b) absolute-GPS-aligned reset epochs
on misaligned sessions, which is the property PNT Moni's TTFF
aggregation requires.

### Note on the original "receiver clock offset" failure mode

GEONET RINEX exports clean integer-second observation
timestamps regardless of the receiver-side clock state, so the
specific failure mode described in MOD-001's "Issue" section —
`timediff` falling just below the configured interval (e.g.,
29.999 vs. 30.0) — is not directly reproducible from this
data. The MOD-001 fix is still the correct fix for that
scenario (the `round()` tolerance absorbs ±0.5 s of obs-time
offset), but the symptom that does manifest in production is
the **alignment drift** demonstrated in the misaligned-start
case above. PNT Moni's TTFF aggregation needs reset epochs to
be consistent across files and sessions, which the fork now
provides and upstream does not.

---

## All four required properties

| # | Property | Result |
|---|---|---|
| 1 | No regression with `misc-regularly` disabled | ✓ PASS (Result 1) |
| 2 | Resets fire at integer multiples of `opt->regularly` | ✓ PASS (Results 2, 3, 4) |
| 3 | Reset alignment invariant to obs cadence | ✓ PASS (Results 2 vs. 3) |
| 4 | Robustness on real GEONET 30 s data | ✓ PASS (Result 4) |

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

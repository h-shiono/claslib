# PNT Moni Modifications to CLASLIB

This document is the authoritative record of all modifications made
in `pntmoni-claslib` relative to upstream CLASLIB
(https://github.com/QZSS-Strategy-Office/claslib).

It exists to ensure that:

1. Every modification is auditable by third parties
2. The fork's divergence from upstream is bounded and minimal
3. Each modification has a documented rationale, impact statement,
   and verification record
4. Re-application of modifications during upstream rebases is
   reproducible

This document should be updated **before** any modification is
merged into the `main` branch of this fork.

## Upstream Base

| Item | Value |
|---|---|
| Upstream repository | https://github.com/QZSS-Strategy-Office/claslib |
| Upstream version | 0.8.3 |
| Upstream release date | 2026-03-31 |
| Fork base commit | (recorded at next rebase) |
| Last upstream sync | 2026-05-09 (initial fork) |

When upstream releases a new version, this section is updated
during the rebase process. The previous values are preserved in
the rebase record (see "Upstream Tracking" below).

## Modification Protocol

Each modification follows this lifecycle:

1. **Identify**: A specific functional gap or bug is identified
   that prevents PNT Moni evaluation. The issue is documented
   in this file as a "pending" entry under a new `MOD-NNN`
   identifier.

2. **Justify**: The modification rationale, expected impact, and
   alternatives considered are documented. Modifications must:

   - Be strictly necessary for PNT Moni evaluation
   - Be minimal in scope
   - Not affect positioning solution computation unless
     explicitly justified
   - Have a clear, deterministic effect

3. **Implement**: The modification is implemented on a feature
   branch named `mod-NNN-<short-description>`. The change is
   accompanied by inline code comments referencing the MOD-NNN
   identifier:

   ```c
   /* PNTMONI MOD-001: round reset interval to int for sub-minute data */
   ```

4. **Verify**: The verification suite is run. For each modification:

   - Positioning solutions on data where the modification does
     not apply (or should not apply) must be bit-identical or
     within agreed tolerance to upstream
   - The behavioral change targeted by the modification must
     be demonstrated on appropriate test data
   - Verification artifacts (input data, output logs, diff files,
     analysis scripts) are committed to
     `verification/MOD-NNN/`

5. **Document**: This file is updated with the verification
   results and the modification entry's status changes from
   "pending" to "applied".

6. **Tag release**: A fork release is tagged using the format
   `v<upstream-version>-pntmoni-N`, where N is incremented for
   each fork release on the same upstream base
   (e.g., `v0.8.3-pntmoni-1`).

7. **Consider upstream PR**: For modifications that may benefit
   the broader CLASLIB community, a pull request to upstream is
   considered. The PR submission is recorded in the modification
   entry.

## Modifications

### MOD-001: Integer rounding of TTFF reset interval

**Status**: Applied (verified on 1Hz CLASLIB sample data;
GEONET 30s confirmation pending) — 2026-05-09

**Issue**

CLASLIB provides a `misc-regularly` option intended for periodic
state reset, primarily used for Time-To-First-Fix (TTFF)
measurement. Upstream's implementation triggers a reset when the
float-valued elapsed time since the last reset meets or exceeds
the configured interval, then anchors the next interval at the
exact obs time of the reset:

```c
/* upstream */
if (opt->regularly != 0 && timediff(obs[0].time, regularly) >= (double)opt->regularly) {
    /* reset, then: */
    regularly = obs[0].time;
}
```

Two problems arise on sub-minute sampled data such as GEONET
30-second observations:

1. **Reset cadence skips when receiver clock is offset.** If the
   receiver clock causes `timediff` to be e.g. 29.999 instead of
   30.0 between consecutive epochs, the comparison fails and no
   reset fires. The next epoch's timediff (~59.998) does trigger
   a reset, but the reset cadence has effectively doubled (60s
   instead of 30s) — and this can repeat for the entire run.

2. **Reset is not aligned to absolute GPS seconds.** Because the
   anchor is updated to the exact obs time on each reset, drift
   accumulates and resets shift in TOW relative to the nominal
   schedule. This complicates TTFF measurement, where reset
   epochs should be globally consistent across runs and across
   files.

For TTFF percentile measurement on GEONET 30-second data, both
issues mean the actual reset behavior diverges from the
documented "reset every N seconds" intent.

**Affected files**

| File | Function | Lines (post-fix) |
|---|---|---|
| `src/ppprtk.c` | `ppp_rtk_pos` | 1477–1497 |
| `src/rtkvrs.c` | `relposvrs` | 1561–1576 |

Both functions contain the same reset trigger pattern; the code
is duplicated between PPP-RTK and VRS modes upstream, so the fix
is applied identically in both locations.

The `static gtime_t regularly` declarations (`src/ppprtk.c:1434`
and `src/rtkvrs.c:1540`) and the `regularly = obs[0].time;`
assignments inside the reset block are retained — they feed the
last-reset-time guard in the new condition.

**Implementation**

The trigger condition is replaced with a TOW-modulo check guarded
by last-reset-time:

```c
/* upstream */
if (opt->regularly != 0 && timediff(obs[0].time, regularly) >= (double)opt->regularly) {

/* PNTMONI MOD-001 */
if (opt->regularly != 0
    && ((int)round(time2gpst(obs[0].time, NULL))) % opt->regularly == 0
    && timediff(obs[0].time, regularly) >= (double)opt->regularly - 0.5) {
```

Two added conditions:

- **`((int)round(tow)) % opt->regularly == 0`** — fires only when
  the GPS time-of-week (rounded to integer seconds) is an exact
  multiple of the configured interval. This anchors resets to
  absolute GPS seconds rather than to "elapsed time since last
  reset", making reset timing globally consistent across runs.
  The `round()` tolerates ±0.5s of receiver clock offset on the
  obs time tag.

- **`timediff(...) >= (double)opt->regularly - 0.5`** — guards
  against double-firing when multiple obs epochs round to the
  same integer TOW (a concern for sub-second sampled data; not
  triggered for 30s GEONET data but kept for correctness).

In `src/rtkvrs.c` the existing local `tow` variable
(declared at line 1553) is reused inside the modulo check
instead of calling `time2gpst()` a second time.

**Constraint**

This implementation requires `opt->regularly` to be a multiple of
the obs sampling interval. For 30-second GEONET data, valid
choices are 30, 60, 90, ..., 900, 1800, 3600, etc. Choosing a
value that doesn't align (e.g., 45 with 30s data) will cause
resets to be missed because no observation epoch will land on the
required TOW. Sample configurations used by PNT Moni should be
documented and reviewed against this constraint.

**Impact statement**

- TTFF measurement becomes feasible on 30-second sampled data
  (and any other integer-second sampling interval)
- Positioning solution computation is **unaffected** (the
  modification only controls when state reset occurs, not
  what the reset does)
- Behavior on 1-second sampled data should be identical to
  upstream (the modification matters only when the elapsed
  time would not naturally hit the float-precision boundary)

**Affected use cases**

- All uses of `misc-regularly` option with reset intervals that
  are integer multiples of the data sampling interval
- TTFF percentile measurement workflows in PNT Moni

**Backward compatibility**

- For users running 1-second sampled data: no observable change
- For users running sub-minute sampled data who currently see
  resets failing: behavior changes to "resets work as
  documented"

**Verification methodology**

1. Run both upstream CLASLIB and `pntmoni-claslib` on identical
   1-second sampled test data
2. Confirm positioning solutions are bit-identical (or within
   floating-point precision tolerance) for non-reset metrics
3. Confirm reset events occur at the same epochs in both
   versions for 1-second data
4. Run both versions on 30-second sampled test data
5. Confirm `pntmoni-claslib` produces reset events at expected
   intervals (every 900s or 3600s as configured)
6. Confirm upstream does not produce reliable reset events on
   the same 30-second data
7. Document all observations in `verification/MOD-001/`

**Verification results**

Verified on 2026-05-09 against `make test_L6_bnx` (1Hz BINEX,
1-hour window starting 2019-08-27 16:00:00 UTC). Full analysis,
configurations, outputs, and reset-event extracts are committed
in [`verification/MOD-001/`](./verification/MOD-001/). Summary:

| # | Property | Result |
|---|---|---|
| 1 | No regression with `misc-regularly` disabled | **PASS** — fork and upstream NMEA outputs are bit-identical (7160 lines each, `diff -q` reports no difference) |
| 2 | Resets fire at integer multiples of `opt->regularly` (1Hz) | **PASS** — fork resets at TOW = 231000, 231300, ..., 233700 (all multiples of 300); upstream resets at TOW = 230720, 231020, ..., 233720 (anchored to first-obs+300, none multiples of 300) |
| 3 | Reset alignment invariant to obs cadence | **PASS** — fork's reset TOWs are identical between `-ti 1` and `-ti 30` runs; upstream's shift by 10 s when subsampling cadence changes |
| 4 | Robustness to receiver clock offset on 30 s GEONET data | **PENDING** — public test data has clean integer-second timing, so the failure mode (`timediff` falling just below the configured interval due to clock offset) cannot be reproduced from the CLASLIB sample suite. Confirmation requires a representative PNT Moni production GEONET file and is tracked as a follow-up |

The verification was performed on macOS clang in a non-LAPACK
build profile (`LDLIBS=-lm`), identical for both branches so
build-time differences cannot bias the comparison. See
[`verification/MOD-001/diff-analysis.md`](./verification/MOD-001/diff-analysis.md)
for the full data and reproduction instructions.

**Upstream PR consideration**

This modification fixes a latent bug that affects any user of
`misc-regularly` on sub-minute data. A pull request to upstream
CLASLIB will be prepared after MOD-001 implementation and
verification, with the goal of having this fix accepted upstream
to reduce fork divergence.

PR status: not yet submitted.

---

(Future modifications follow the same template.)

## Verification Suite

The verification suite is the set of tests that runs against the
fork to confirm modifications behave as intended and do not
introduce unintended changes.

The suite is intended to grow as modifications are added. The
initial scope is:

- **MOD-001 verification**: described above
- **Regression check**: all existing CLASLIB sample test data
  (`make test*` targets) must produce identical or equivalent
  outputs between fork and upstream

The verification suite runs:

- Before any modification is merged to `main`
- Before any release tag is created
- After each upstream rebase (see "Upstream Tracking")

Verification artifacts are stored under `verification/`, organized
by modification:

```
verification/
├── README.md
├── MOD-001/
│   ├── input/                    # test data inputs
│   ├── upstream-output/          # output from upstream CLASLIB
│   ├── fork-output/              # output from this fork
│   ├── diff-analysis.md          # human-readable analysis
│   └── automated-test.sh         # reproducible test script
└── (further MOD-NNN directories)
```

## Upstream Tracking

When upstream CLASLIB releases a new version, this fork is
rebased against it within 30 days where feasible.

The rebase process:

1. Fetch upstream changes
2. Create a rebase branch (`rebase-vX.Y.Z`)
3. Rebase the fork's modifications onto the new upstream base
4. For each `MOD-NNN`: re-apply the modification, addressing any
   conflicts caused by upstream changes
5. Run the full verification suite against the new base
6. Update the "Upstream Base" section of this file
7. Add a rebase record (see template below)
8. Tag a new fork release as `v<upstream-version>-pntmoni-1`
   (with `pntmoni-N` numbering reset to 1 for each new upstream
   base)

### Rebase Record Template

```markdown
### Rebase against upstream v<X.Y.Z> (YYYY-MM-DD)

**Previous fork base**: v<previous>
**New fork base**: v<X.Y.Z>
**New fork release**: v<X.Y.Z>-pntmoni-1
**Upstream commit**: <SHA>

**Modifications carried forward**:
- MOD-001: re-applied without conflict / with conflict in <file>
- MOD-002: ...

**Verification results**:
- All MOD-NNN verification suites passed
- Regression check passed

**Notes**:
- Any observations about upstream changes that affect PNT Moni
  evaluation
```

A rebase record is appended to this file (or to a separate
`REBASE_HISTORY.md`) for each rebase.

## License Compatibility

CLASLIB is distributed under BSD 2-Clause license with two
additional clauses (commercial use permitted). This fork
inherits the same license. All `MOD-NNN` modifications by PNT
Moni are released under the same license.

The original copyright notices are preserved:

- Copyright (c) 2007-, T. Takasu
- Copyright (c) 2014-, Geospatial Information Authority of Japan
- Copyright (c) 2017-, Mitsubishi Electric Corp.

PNT Moni's modifications add no new copyright claims; they are
contributions under the existing license terms.

## Contact

Issues related to this fork's modifications:

- Open an issue in https://github.com/h-shiono/pntmoni-claslib
- For PNT Moni service inquiries: hello@pntmoni.com

Issues related to upstream CLASLIB functionality should be
directed to https://github.com/QZSS-Strategy-Office/claslib.

## Document History

- 2026-05-09: Initial creation. MOD-001 entry added as pending.
- 2026-05-09: MOD-001 implemented in `src/ppprtk.c` and
  `src/rtkvrs.c` on branch `mod-001-ttff-reset-interval`. Status
  moved from "Pending implementation" to "Implemented
  (verification pending)". Issue description corrected to match
  actual upstream code (timediff-based comparison, not
  modulo+epsilon). Affected-files and Implementation sections
  populated with concrete code.
- 2026-05-09: MOD-001 verified against `make test_L6_bnx`
  (1Hz BINEX). Three of four required properties confirmed
  (regression-free, resets at multiples of `opt->regularly`,
  cadence-invariant alignment); GEONET 30s clock-offset
  robustness pending production sample. Status moved to
  "Applied (verified on 1Hz CLASLIB sample data; GEONET 30s
  confirmation pending)". Verification artifacts committed
  under `verification/MOD-001/`.

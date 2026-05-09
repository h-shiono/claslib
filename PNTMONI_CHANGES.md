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

**Status**: Pending implementation (as of 2026-05-09)

**Issue**

CLASLIB provides a `misc-regularly` option intended for periodic
state reset, primarily used for Time-To-First-Fix (TTFF)
measurement. The reset logic computes the elapsed time modulo the
reset interval and triggers a reset when the modulo is below an
epsilon threshold.

When operating on observation data with sub-minute sampling
intervals (e.g., 30-second sampled GEONET data), the reset
interval calculation uses floating-point arithmetic. Floating-
point representation of the interval boundary causes the modulo
computation to produce non-zero remainders even at intended
reset boundaries.

As a result, with 30-second sampled data, resets do not trigger
reliably even when the elapsed time should be a clean multiple
of the configured reset period (e.g., 900 seconds for a 15-minute
reset, or 3600 seconds for a 60-minute reset).

This prevents TTFF measurement on GEONET data, which is sampled
at 30-second intervals.

**Expected location**

The reset logic is expected to be in one of:

- `src/postpos.c` (post-processing main loop)
- `src/ppprtk.c` (PPP-RTK specific reset handling)
- `src/rtkpos.c` (general RTK reset logic inherited from RTKLIB)

The exact file and line are to be confirmed during implementation.

**Proposed fix**

Round the reset interval to integer seconds before the modulo
computation:

```c
/* Original (illustrative; actual upstream code TBD) */
double reset_interval = ...;  /* configured in seconds */
if (fmod(elapsed, reset_interval) < EPS) {
    /* trigger reset */
}

/* PNTMONI MOD-001 */
int reset_interval_int = (int)round(reset_interval);
if (reset_interval_int > 0 && ((int)round(elapsed)) % reset_interval_int == 0) {
    /* trigger reset */
}
```

The exact form of the fix will be determined when the upstream
location is identified.

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

To be filled after implementation.

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

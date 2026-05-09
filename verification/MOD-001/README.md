# MOD-001 verification

Verification artifacts for [MOD-001 — Integer rounding of TTFF
reset interval](../../PNTMONI_CHANGES.md#mod-001-integer-rounding-of-ttff-reset-interval).

## Files

- [`diff-analysis.md`](./diff-analysis.md) — full analysis of
  fork vs. upstream behavior on `make test_L6_bnx`, with reset
  event TOWs and verdicts for each of the three properties
  exercisable from the public test data.
- [`run.sh`](./run.sh) — reproducible test driver. Builds
  rnx2rtkp on the currently-checked-out branch and runs three
  configurations (regression, behavioral 1 Hz, behavioral 30 s).
- [`kinematic_unix.conf`](./kinematic_unix.conf) — upstream
  `util/rnx2rtkp/kinematic.conf` with paths converted to forward
  slashes (the upstream conf uses `\` separators that work only
  on Windows). Used as the regression-test config.
- [`kinematic_regularly300.conf`](./kinematic_regularly300.conf)
  — same as above plus `misc-regularly=300` to exercise the
  modified reset path. Used as the behavioral-test config.
- `0627239Q_*_regularly0.nmea` — NMEA outputs from the
  regression run. `diff` is bit-identical between fork and
  upstream.
- `0627239Q_*_regularly300.nmea` and
  `0627239Q_*_ti30_reg300.nmea` — NMEA outputs from the
  behavioral runs. Differ between fork and upstream as
  expected; the trace logs (gitignored, regenerable) carry the
  reset-event evidence.
- `resets_*.txt` — extracted `regularly reset filter` lines
  from the corresponding `.trace` files. Small, committed for
  audit so the reset-event evidence remains available even
  when `.trace` is gitignored.
- `.gitignore` — excludes `.stat` and `.trace` files (large
  and regenerable from `run.sh`).

## Status

See the [`Verification results`](../../PNTMONI_CHANGES.md#mod-001-integer-rounding-of-ttff-reset-interval)
section in PNTMONI_CHANGES.md for the formal status entry.

Three of four required properties are confirmed by the public
test suite. The fourth — robustness to non-trivial receiver
clock offset on GEONET 30 s sampled data — requires a
production sample file from PNT Moni's evaluation pipeline and
is tracked as a pending follow-up in the analysis document.

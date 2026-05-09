#!/usr/bin/env bash
# MOD-001 verification: TTFF reset-interval behavior on test_L6_bnx.
#
# Reproduces four runs (fork × upstream × ti=1 × ti=30) under the
# same configuration used by `make test_L6_bnx`, with one config
# variant that enables `misc-regularly=300` to exercise the
# modified reset path.
#
# Usage:
#   bash verification/MOD-001/run.sh
#
# Prerequisites:
#   - Run from anywhere; this script cd's into util/rnx2rtkp.
#   - The rnx2rtkp binary must be built. The script builds it
#     fresh on whichever git branch is currently checked out, so
#     to compare fork vs. upstream, run the script twice — once
#     on `mod-001-ttff-reset-interval`, once on the upstream-tip
#     branch (e.g., `main` before merge, or upstream tag) — using
#     a different OUTPUT_LABEL each time.
#
# macOS note:
#   The build uses POSIX feature flags and skips LAPACK
#   (-D_POSIX_C_SOURCE=200809L -D_DARWIN_C_SOURCE; -lm only),
#   matching the makefile's commented-out "without lapack"
#   profile. Linear-algebra results are slightly different from
#   a LAPACK-linked build but are deterministic and reproducible
#   per branch.

set -euo pipefail

LABEL="${OUTPUT_LABEL:-$(git rev-parse --abbrev-ref HEAD)}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
VRF_DIR="$REPO_ROOT/verification/MOD-001"
BUILD_DIR="$REPO_ROOT/util/rnx2rtkp"

CFLAGS_OVERRIDE="-Wall -O3 -I../../src -D_POSIX_C_SOURCE=200809L -D_DARWIN_C_SOURCE -DTRACE -DENAGAL -DENAQZS -DNFREQ=3 -DENA_PPP_RTK -DENA_REL_VRS"
LDLIBS_OVERRIDE="-lm"

OBS="$REPO_ROOT/data/0627239Q.bnx"
NAV="$REPO_ROOT/data/sept_2019239.nav"
L6="$REPO_ROOT/data/2019239Q.l6"
TIME_RANGE=(-ts 2019/08/27 16:00:00 -te 2019/08/27 16:59:59)

cd "$BUILD_DIR"

echo "==> Building rnx2rtkp on branch: $LABEL"
make clean >/dev/null
make rnx2rtkp CFLAGS="$CFLAGS_OVERRIDE" LDLIBS="$LDLIBS_OVERRIDE" >/dev/null

run() {
    local ti="$1" conf="$2" out="$3"
    echo "==> Run: ti=$ti conf=$(basename "$conf") -> $out"
    ./rnx2rtkp -ti "$ti" "${TIME_RANGE[@]}" -x 2 -k "$conf" "$OBS" "$NAV" "$L6" -o "$out" >/dev/null 2>&1
}

# Regression run (regularly=0): fork should be bit-identical to upstream.
run 1 "$VRF_DIR/kinematic_unix.conf"      "$VRF_DIR/0627239Q_${LABEL}_regularly0.nmea"

# Behavioral runs (regularly=300): expected to differ between fork and upstream
# in reset-event TOW alignment.
run 1  "$VRF_DIR/kinematic_regularly300.conf" "$VRF_DIR/0627239Q_${LABEL}_regularly300.nmea"
run 30 "$VRF_DIR/kinematic_regularly300.conf" "$VRF_DIR/0627239Q_${LABEL}_ti30_reg300.nmea"

# Extract reset events from trace logs into compact text files so
# they remain available even when *.trace is gitignored.
for tag in regularly300 ti30_reg300; do
    trace="$VRF_DIR/0627239Q_${LABEL}_${tag}.nmea.trace"
    out="$VRF_DIR/resets_${LABEL}_${tag}.txt"
    if [[ -f "$trace" ]]; then
        grep "regularly reset filter" "$trace" > "$out" || true
        echo "==> $(wc -l < "$out") reset events -> $(basename "$out")"
    fi
done

echo "==> Done. See $VRF_DIR for outputs."

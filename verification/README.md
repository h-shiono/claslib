# Verification suite

Per-MOD verification artifacts for the modifications listed in
[PNTMONI_CHANGES.md](../PNTMONI_CHANGES.md).

Each `MOD-NNN/` subdirectory holds the test driver, configs,
outputs, and analysis for one modification. See the relevant
`MOD-NNN/README.md` for details.

## Layout

```
verification/
├── README.md            (this file)
└── MOD-NNN/
    ├── README.md        — what this MOD verifies
    ├── diff-analysis.md — fork vs. upstream comparison + verdict
    ├── run.sh           — reproducible test driver
    ├── *.conf           — test configurations used
    ├── *.nmea           — committed outputs (small)
    ├── resets_*.txt     — extracted trace evidence (small)
    └── .gitignore       — excludes large regenerable files
```

## Running

Each `MOD-NNN/run.sh` is self-contained and rebuilds rnx2rtkp
on the currently-checked-out branch. To compare fork vs.
upstream:

```bash
git checkout mod-NNN-<name>
OUTPUT_LABEL=fork bash verification/MOD-NNN/run.sh

git checkout main      # or the upstream tag
OUTPUT_LABEL=upstream bash verification/MOD-NNN/run.sh
```

Outputs are differentiated by `OUTPUT_LABEL`, so both runs
coexist in the same directory for direct diffing.

## When to run

Per PNTMONI_CHANGES.md § Verification Suite, the suite runs:

- Before any modification is merged to `main`
- Before any release tag is created
- After each upstream rebase

Each run should leave its outputs and an updated
`diff-analysis.md` entry in the appropriate `MOD-NNN/`
directory.

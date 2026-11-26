#!/bin/zsh
# Measures swift-section refs against the 2026-11-18 ground truth and puts it
# next to that run's IDA numbers. See README.md.
#   SWIFT_SECTION=<binary> ./run_all.sh
set -euo pipefail
SCRIPTS=${0:A:h}
export CROSS_REFERENCE_RECALL_WORK=${CROSS_REFERENCE_RECALL_WORK:-/tmp/cross-reference-recall}

zsh $SCRIPTS/prepare.sh
python3 -I $SCRIPTS/ground_truth.py
python3 -I $SCRIPTS/verify_reproduction.py
python3 -I $SCRIPTS/query_swift_section.py
python3 -I $SCRIPTS/score.py

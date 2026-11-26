#!/bin/zsh
# Thins the two samples to the arm64e slice both IDA databases hold, and
# writes the disassembly, load-command and fixup listings ground_truth.py
# reads. The samples are the ones the 2026-11-18 benchmark used.
set -euo pipefail
WORK=${CROSS_REFERENCE_RECALL_WORK:-/tmp/cross-reference-recall}
FINDER=${CROSS_REFERENCE_RECALL_FINDER:-/Volumes/RE/Finder/26.5.2/Finder}
CONTROL_CENTER=${CROSS_REFERENCE_RECALL_CONTROL_CENTER:-/Volumes/RE/ControlCenter/26.7/ControlCenter}
mkdir -p $WORK
cd $WORK

# A sample already thinned to arm64e is taken as it is.
thin() {
  if lipo -info $1 | grep -q '^Non-fat'; then cp $1 $2; else lipo -thin arm64e $1 -output $2; fi
}
thin $FINDER Finder
thin $CONTROL_CENTER ControlCenter
# 1E2E81F7-9B9D-317A-A102-F55ADAF6A0A0 and 5782ED6B-471B-3CAC-9258-93734B6009C3.
dwarfdump --uuid Finder ControlCenter

for binary in Finder ControlCenter; do
  otool -arch arm64e -tV $WORK/$binary > $binary.otool
  otool -arch arm64e -l $WORK/$binary | awk '/sectname/{s=$2} /segname/{g=$2} /^ *addr /{a=$2} /^ *size /{if(s!=""){print g, s, a, $2; s=""}}' > $binary.sections
  dyld_info -fixups $WORK/$binary > $binary.fixups
  wc -l $binary.otool $binary.sections $binary.fixups
done

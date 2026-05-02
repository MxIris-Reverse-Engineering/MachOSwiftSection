#!/bin/bash
# Regenerates all (or one) MachOSwiftSection fixture-test baseline files.
# Usage:
#   Scripts/regen-baselines.sh                  # all suites
#   Scripts/regen-baselines.sh --suite Foo      # one suite
#
# Sets DYLD_FRAMEWORK_PATH/DYLD_LIBRARY_PATH so swift-testing's runtime
# libraries are findable when running outside `swift test`.
set -euo pipefail

XCODE_FRAMEWORKS="/Applications/Xcode.app/Contents/SharedFrameworks"

DYLD_FRAMEWORK_PATH="$XCODE_FRAMEWORKS" \
DYLD_LIBRARY_PATH="$XCODE_FRAMEWORKS" \
    swift run baseline-generator "$@"

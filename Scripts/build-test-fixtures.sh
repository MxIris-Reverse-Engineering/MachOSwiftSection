#!/usr/bin/env bash
#
# Builds the SymbolTestsCore fixture framework consumed by MachOSwiftSection's
# snapshot tests. Run once after cloning, and again whenever
# Tests/Projects/SymbolTests/SymbolTestsCore/**/*.swift (or the Xcode project
# itself) changes. Output lands in Tests/Projects/SymbolTests/DerivedData/,
# which is gitignored.
#
# If you skip this step, MachOFileTests.init() throws a "file not found" error
# at the configured path under Tests/Projects/SymbolTests/DerivedData/…, and
# every snapshot test aborts before asserting.

set -euo pipefail

# Resolve the script's own directory so the command works from any CWD.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$REPO_ROOT"

xcodebuild \
    -project Tests/Projects/SymbolTests/SymbolTests.xcodeproj \
    -scheme SymbolTestsCore \
    -configuration Release \
    -derivedDataPath Tests/Projects/SymbolTests/DerivedData \
    -destination 'generic/platform=macOS' \
    -quiet \
    build

echo "SymbolTestsCore fixture built. Next: swift package update && swift test"

# CI Test Filter and Environment Upgrade

**Date:** 2026-04-18
**Status:** Approved, pending implementation

## Problem

The GitHub Actions `macOS` workflow runs `swift test` against the entire test
suite. Most test classes rely on resources that only exist on a developer
machine — installed Xcode frameworks (`/Applications/Xcode.app/...`), iOS
Simulator runtimes, the on-device dyld shared cache, runtime-loaded images, and
user applications. On a CI runner these paths do not exist, so those tests
either fail or are meaningless. Running them wastes time and masks real
signal.

There are also tests that can run on CI but require a build artifact that is
not in git: `SymbolTestsCore.framework`. It is produced by the Xcode project
at `Tests/Projects/SymbolTests/SymbolTests.xcodeproj`, and its `DerivedData`
directory is listed in `.gitignore`. The current workflow does not build this
artifact, so even the self-contained fixture tests can't run.

Separately, the workflow pins `macos-15` + Xcode `16.3`. Project requirements
have moved to macOS 26.2 + Xcode 26.2.

## Goals

- CI runs only the test classes that work without a developer-machine
  environment.
- CI builds the `SymbolTestsCore.framework` fixture before running tests.
- CI and the release workflow both run on `macos-26` + Xcode `26.2`.
- No changes to test source files — the filter lives in CI configuration only.

## Non-Goals

- Introducing runtime flags, tags, or `.disabled(if:)` traits in test code.
- Changing which tests exist or how they're organised.
- Making the blocked tests runnable in CI (e.g. vendoring dyld caches, shipping
  Xcode frameworks). They remain developer-only.
- Checking `SymbolTestsCore.framework` into git.

## Scope: Tests that run in CI (whitelist)

Exactly four test classes run in CI. All of them read from
`SymbolTestsCore.framework`:

| Test class | File | Category |
|---|---|---|
| `MachOFileDumpSnapshotTests` | `Tests/SwiftDumpTests/Snapshots/MachOFileDumpSnapshotTests.swift` | Dump snapshot |
| `MachOFileInterfaceSnapshotTests` | `Tests/SwiftInterfaceTests/Snapshots/MachOFileInterfaceSnapshotTests.swift` | Interface snapshot |
| `STCoreE2ETests` | `Tests/SwiftInterfaceTests/SymbolTestsCoreE2ETests.swift` | Fixture E2E |
| `STCoreTests` | `Tests/SwiftInterfaceTests/SymbolTestsCoreIntegrationTests.swift` | Fixture integration |

Every other test class — whether it is a "dump" test, a `DyldCache*` /
`Xcode*` snapshot, a `MachOSwiftSectionTests` unit test, or anything in
`MachOSymbolsTests` / `TypeIndexingTests` / `SwiftInspectionTests` — is
excluded from CI runs. Those tests remain fully functional locally.

## Design

### 1. Build the fixture

The `Build SymbolTestsCore fixture` step is already present on `main` (along
with `Resolve SPM dependencies`, `Cache SymbolTests DerivedData`, and
`Upload xcodebuild logs on failure`). It uses `-derivedDataPath
Tests/Projects/SymbolTests/DerivedData`, which matches the path
`MachOFileName.SymbolTestsCore` (in
`Sources/MachOTestingSupport/MachOFileName.swift`) resolves:

```
../../Tests/Projects/SymbolTests/DerivedData/SymbolTests/Build/Products/Release/SymbolTestsCore.framework/Versions/A/SymbolTestsCore
```

No change is needed for fixture construction.

### 2. Filter test runs

Pass a single combined regex to `swift test --filter`:

```
\.(MachOFileDumpSnapshotTests|MachOFileInterfaceSnapshotTests|STCoreE2ETests|STCoreTests)(/|$)
```

- Leading `\.` anchors against the module prefix (`SwiftDumpTests.`,
  `SwiftInterfaceTests.`) so the names can't match module-less substrings.
- Trailing `(/|$)` uses a word-boundary-style anchor so `STCoreTests` does
  **not** also match `STCoreE2ETests`.

Both Debug and Release `swift test` invocations receive this filter.

### 3. Environment upgrade

Both workflows move to macOS 26.2 + Xcode 26.2.

`.github/workflows/macOS.yml`:

- `matrix.os`: `macos-15` → `macos-26`
- `matrix.xcode-version`: `"16.3"` → `"26.2"`

`.github/workflows/release.yml`:

- `runs-on`: `macos-15` → `macos-26`
- `Setup Xcode` with xcode-version `"16.3"` → `"26.2"`

## Final workflow shape

The `macOS.yml` workflow keeps its existing structure (Resolve SPM,
Cache DerivedData, Build SymbolTestsCore fixture, Upload logs on failure,
Build and run tests). Only three lines change:

- `matrix.os: macos-15` → `matrix.os: macos-26`
- `matrix.xcode-version: "16.3"` → `matrix.xcode-version: "26.2"`
- Both `swift test` invocations gain a single `--filter` argument:
  `'\.(MachOFileDumpSnapshotTests|MachOFileInterfaceSnapshotTests|STCoreE2ETests|STCoreTests)(/|$)'`

`release.yml` keeps its existing shape, with only the runner and Xcode
version bumped:

- `runs-on: macos-15` → `runs-on: macos-26`
- `xcode-version: "16.3"` → `xcode-version: "26.2"`

## Trade-offs

- **Whitelist maintenance.** New test classes that belong in CI must be added
  to the regex. The alternative (a blacklist of environment-dependent tests)
  would drift the opposite way — new tests get included by accident. The
  whitelist matches the intent ("CI only runs reproducible fixture-based
  tests") more directly.
- **`xcodebuild` adds wall-clock time.** Expected ~20-40 seconds for a single
  Release build of the small fixture framework. Acceptable given it's a
  one-time per-run cost and the alternative (checking in the binary) adds
  other problems.
- **Debug and Release both run.** Preserved from the existing workflow. If
  compile time on `macos-26` becomes a concern later, dropping to Debug-only
  is a one-line change.
- **Regex vs. multiple `--filter` flags.** A single regex with an anchored
  word boundary is more compact and avoids the `STCoreTests` ⊂ `STCoreE2ETests`
  substring pitfall that four separate `--filter` flags would have.

## Verification

After the workflow change lands, a CI run on the next PR should:

1. Successfully complete the `Build SymbolTestsCore fixture` step and leave a
   framework at
   `Tests/Projects/SymbolTests/DerivedData/SymbolTests/Build/Products/Release/SymbolTestsCore.framework`.
2. Run exactly the four whitelisted test classes (visible in the test log),
   one invocation per config (Debug + Release).
3. Not attempt `DyldCache*`, `Xcode*`, `MachOImage*`, or `*DumpTests` (non-
   Snapshot) classes.

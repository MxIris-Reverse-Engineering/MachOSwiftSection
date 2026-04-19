# Known Issues

This document tracks known limitations and deferred improvements in MachOSwiftSection. Each entry describes the problem, why it is not addressed yet, and what a future fix would look like.

## Concurrency

### SharedCache builds under the global cache lock

- **Location:** `Sources/MachOCaches/SharedCache.swift` — `storage(in:buildUsing:)` and `storage()`
- **Symptom:** The caller-supplied `build` closure executes inside the same `withLockUnchecked` critical section that guards the identifier-keyed storage dictionary. When the build is expensive (for example, `SymbolIndexStore.prepareWithProgress` performs parallel demangling of every symbol in a Mach-O), all other threads attempting to access the cache for any Mach-O are blocked for the full duration of the build.
- **Why deferred:** In the current use sites, concurrent cache construction across different Mach-O identifiers is rare — tools typically prepare one Mach-O at a time, so the lock contention is not observed in practice. The current implementation was chosen for its simple atomicity guarantee (a single critical section around check–build–insert, independent of whatever `_modify` accessor the `@Mutex` macro generates).
- **Potential fix:** Replace the single mutex with a per-key promise / in-flight map:
  1. Enter the lock, look up the key.
  2. If the entry is already completed, return it.
  3. If an in-flight promise exists, release the lock and await it.
  4. Otherwise, install an in-flight marker, release the lock, run `build` outside the lock, re-enter the lock to store the result, and wake any waiters.
- **Tracking:** Raised in PR #61 review by both `gemini-code-assist` (high priority) and `copilot-pull-request-reviewer`.

### `SymbolIndexStore.demangledNode(for:in:)` data race under parallel tests

- **Location:** `Sources/MachOSymbols/SymbolIndexStore.swift` — `demangledNode(for:in:)` and `setDemangledNode(_:for:)`
- **Symptom:** When swift-testing runs multiple `SwiftInterfaceBuilderTestSuite` sub-suites in parallel (for example `MachOImageTests`, `XcodeMachOFileTests`, `DyldCacheTests`, `MachOFileTests`), the harness sporadically crashes with `NSInvalidArgumentException: -[NSTaggedPointerString objectForKey:]: unrecognized selector sent to instance 0x8000000000000000`. The crash originates in `SymbolIndexStore.demangledNode(for:in:) + 256`, inside the `cacheStorage.demangledNodeBySymbol[symbol]` lookup.
- **Root cause:** On a cache miss, `demangledNode(for:in:)` mutates `Storage.demangledNodeBySymbol` via `setDemangledNode(_:for:)` without synchronization. Swift `Dictionary` is not thread-safe under concurrent read+write; when the swift-testing harness runs sibling suites in parallel, multiple builders hit the same `SymbolIndexStore.Storage` simultaneously, corrupting the dictionary's internal layout and producing the NSException seen above.
- **Why deferred:** Running individual sub-suites (for example `--filter SwiftInterfaceBuilderTestSuite.MachOFileTests`) passes reliably, and end-to-end tests (`SymbolTestsCoreE2ETests`, `MachOSymbolsTests`, `DemanglingTests`) also pass. Only the parallel-suite harness configuration exposes the race, so ordinary CLI workflows are unaffected.
- **Potential fix:** Either (a) guard `demangledNodeBySymbol` with the same `SharedCache` mutex that already wraps `Storage` access, (b) make `setDemangledNode`/`demangledNodeBySymbol` itself thread-safe with an internal lock, or (c) pre-populate `demangledNodeBySymbol` completely during `buildStorageImpl` so `demangledNode(for:in:)` becomes read-only at query time.
- **Tracking:** Observed during PR #61 review-follow-up testing.
- **Recent CI hits:** reproduced on `main` push runs under `.github/workflows/macOS.yml` — after merging `docs/readme-0.9.1` the debug-mode `swift test` step crashed with signal 11 (run 24628302034), and after merging `release/0.10.0` the release-mode step crashed the same way (run 24633097766). Both commits passed on their matching PR-branch runs (e.g. run 24633093885 for `release/0.10.0`), reinforcing the parallel-harness-only nature of the race.

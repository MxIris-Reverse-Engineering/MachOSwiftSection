# PR #103 Code Review Findings

Review date: 2026-08-09
PR: `feature/node-store-migration` → `main` (103 files, +6880/−874, merge base `a8968fa5`)
Review depth: automated multi-agent review at `max` effort, followed by a manual pass that answered the four mandatory questions (reproduce / baseline / worth fixing / fixed before) for every surviving finding against the branch, `main`, CI logs, and `git log`.

Status: **Recorded and verified, not yet fixed.**

All file/line references are against `feature/node-store-migration` at `8faff275`. "Baseline" means `main` at `a8968fa5`. "Upstream" means the `swift-demangling` package.

---

## How to read this document

Every finding answers the four questions AGENTS.md requires of a review finding, in this order:

- **Q1 — Reproducible, or a false positive?** The concrete trigger, with the evidence that it is real.
- **Q2 — Does the baseline have it?** Whether this is newly introduced by the PR or pre-existing on `main`. Several findings are pre-existing *defects* whose *cost* is new — those are called out explicitly, because the fix priority follows the cost, not the defect's age.
- **Q3 — Worth fixing, and how wide is the blast radius?**
- **Q4 — Has this been fixed before?** Traced through `git log` / `git blame` / commit messages. Three findings are repeat offences on code that has already been fixed once or twice for the same class of problem.

Severity buckets are **Blocker / High / Medium / Low**. Nothing here is adjudicated as "won't fix" — findings that were skipped as already-adjudicated or refuted are listed at the end, with pointers, so the next review round does not re-derive them.

---

## Verification status

Everything below was verified directly; nothing is reported on the review agent's word alone.

- **B1** — both pins read from `Package.swift:212-222` on each branch; `git ls-remote --tags` against upstream confirms `0.5.1` is the newest published tag; CI run `31309763070` read with `gh run view --log-failed` (debug and release both fail with the same three errors).
- **H1** — the four clearing assignments read at `SwiftDeclarationIndexer.swift:~306`, the six accessors at `:1027-1042`; `main`'s only `currentStorage.types = []` confirmed to sit in an extraction-failure `catch` (`main:195`). Repo-wide grep confirms zero in-repo consumers.
- **H2** — the two early returns read at `ExtensionDefinition.swift:118-119` against `isIndexed = true` at `:171`; `main`'s equivalent early return confirmed at `main:95`; the four print-path probes read at `SwiftDeclarationPrinter.swift:208`, `:250`, `:305` and `SwiftDiffableInterfaceBuilder.swift:58`.
- **H3 / M4** — `BindOperation` payload types read from the local `../MachOKit` sibling (`Model/Bind/BindOperation.swift:27,37`): `segment`, `count` and `skip` are all `UInt` passed straight through from the opcode stream, with no validation in the decoding layer.
- **H4** — `compare_all_pairs` and `main()` read in full; the verdict path confirmed to depend solely on `difference_count`, which is only incremented inside the `baseline/*.txt` glob loop.
- **M1** — `dd1822c6` located via `git log -S "conflated the two"`; its analysis comment is still present verbatim at `SwiftDeclarationPrinter.swift:251-257`. **Reachability re-verified 2026-08-09** after the implementing session pushed back: `printExtensionHeader` has one in-repo caller (`:213`), preceded by a propagating `index(in:)` at `:209` that performs the same materialization at `ExtensionDefinition.swift:119` — so the `try?` is unreachable in-repo, and the finding was rewritten and downgraded. The original write-up asserted a rendering-path failure that does not exist; see the revision note on M1.
- **M5 / L2** — `a7caf944`'s commit message read in full; it documents the single-layer detach design that `6b0dad20`'s NodeStore arena later outgrew.
- **L1** — `main`'s block-level `printCatchedThrowing` and the PR's per-definition replacement read side by side from the `SwiftInterfaceBuilder.swift` diff.
- **L3** — the two prior rounds on the same function read at `17ad4358` and `6647359e`; rank arithmetic (`bestMatchRank = 0`, `rankStepsPerPathShape = 2`) read from `DyldCache+.swift:21,33,45`.

Two claims are **reasoned, not executed**: the exact heap/时间 cost of H2's repeated materialization was not profiled (the mechanism is certain, the magnitude is not), and M2's use-after-unload was not reproduced with a live `dlclose` (the ownership chain is confirmed by code reading; whether any shipping consumer actually unloads an image was not established).

---

## Shared root causes

Most findings are not independent mistakes. Four causes account for eleven of the fifteen:

| Root cause | Findings |
|---|---|
| **Descriptor slimming (evolution 0002) turned free stored-property reads into throwing, re-parsing calls** — every call site that treated the old read as free needs re-examining, not just the ones that stopped compiling | H1, H2, M1, L1 |
| **Symbol-table compaction (evolution 0001) introduced raw pointers and bit budgets over binary-supplied values** — the safety properties the old `String`-per-row representation gave for free now have to be enforced deliberately | M2, M3, M5 |
| **New binary-format decoding trusts the input** — the LC_DYLD_INFO opcode stream is attacker-controlled in the same way every other input to this library is | H3, M4 |
| **New verification harnesses have no self-check** — a harness that cannot fail is worse than no harness, because its green light was cited as acceptance evidence | H4, L2, L4 |

The first row is the one worth generalizing: **evolution 0002's mechanical migration was driven by the compiler, and the compiler cannot see semantic changes.** A property that became a function still compiles at every call site that only needed its value; what changed is cost (H2), failure mode (M1, L1), and lifetime (H1). Any future descriptor-slimming step should audit call sites by hand rather than by build error.

---

## Blocker

### B1. The `swift-demangling` remote pin names a range with no tag containing the required API — the PR does not compile from a clean clone

- **File:** `Package.swift:222`
- **Q1 — Reproducible.** The remote requirement is `"0.5.1" ..< "0.6.0"`. `git ls-remote --tags` against upstream ends at `0.5.1`; `SharedNodeStore` and `NodeStoreBuilder.reserveCapacity(expectedSymbolCount:)` exist only on the unpublished `feature/node-store` branch. Any resolution that goes through the remote picks `0.5.1` and fails. CI run `31309763070` (2026-08-09) fails in **both** debug and release with `cannot find 'SharedNodeStore' in scope` (`InternedNodeReferenceCache.swift:52`, `SymbolIndexStore.swift:212`) and `value of type 'NodeStoreBuilder' has no member 'reserveCapacity'` (`SymbolIndexStore.swift:560`). The 2026-08-04 run was green because its head predated `6b0dad20`, which introduced the arena usage.
- **Q2 — Not on the baseline.** `main` pins `"0.4.5" ..< "0.5.0"` with a comment stating the adoption lives on this branch and main keeps a closed upper bound until it lands.
- **Q3 — Merge blocker.** This is not "a scenario that misbehaves"; it is the whole PR failing to build anywhere that does not have both a `../swift-demangling` sibling *and* `USING_LOCAL_DEPENDENCIES=1` (`Package.swift:67,74-82` require both conditions). Every other finding in this document is unverifiable on CI until it is resolved. Two possible resolutions: publish an upstream `0.5.2` containing the arena API and re-pin, or revert to branch tracking — but branch tracking is precisely what `38b53c68` removed for cause.
- **Q4 — Fixed before, twice; this is the third round.** `3f7428ec` tracked upstream's `feature/node-store` branch → `38b53c68` replaced it with the `0.5.0` tag, whose message states the reason in full: *"Pinning to a branch made the package unresolvable for any version-based consumer and left builds non-reproducible"* → `6113d518` moved the floor to `0.5.1`. The lesson was recorded; it recurred in a new shape — a legally-resolvable tag that does not contain the symbols the code needs. `38b53c68` also documented its verification step (*"`swift package resolve` in a sibling-free checkout picks 0.5.0, and `swift build` succeeds"*), and that step was not repeated for this bump.
- **Suggested fix:** Publish the upstream tag, re-pin, and re-run resolution in a sibling-free checkout before pushing. Consider making the sibling-free resolution check part of CI so a pin that cannot build alone fails fast and loudly.

---

## High

### H1. `prepare()` clears the section-wrapper arrays, so six public statistics accessors silently return 0

- **File:** `Sources/SwiftIndexing/SwiftDeclarationIndexer.swift:1027-1042` (accessors), `:~306` (clearing)
- **Q1 — Reproducible.** `prepare()` now ends with `currentStorage.types = []` / `.protocols = []` / `.protocolConformances = []` / `.associatedTypes = []`. `numberOfTypes`, `numberOfEnums`, `numberOfStructs`, `numberOfClasses`, `numberOfProtocols` and `numberOfProtocolConformances` all read those arrays, and the only useful time to read them is after preparation. A panel that showed 5416 types for SwiftUI now shows 0.
- **Q2 — New.** On `main` the only `currentStorage.types = []` is the extraction-failure `catch` at `main:195`; the success path keeps the arrays for the indexer's lifetime.
- **Q3 — Worth fixing, cheap.** Zero in-repo consumers (grep hits only the definitions), so the entire blast radius is downstream (RuntimeViewer and similar). That is exactly what makes it worth fixing: a public API that silently returns a wrong answer is harder to notice than one that fails to compile — and evolution 0002's source-compatibility section lists only the three property renames, so a downstream reader has no warning. Fix by capturing the six counts into stored properties before clearing.
- **Q4 — No prior fix.** The statistics block has not been touched independently since the module split (`47b5961f`).
- **Also update:** evolution 0002's source-compatibility section, to list these six accessors alongside the three renames.

### H2. `index(in:)`'s early returns leave `isIndexed` false, so the new materialization runs 3–4× per extension per print

- **File:** `Sources/SwiftDeclaration/Components/Definitions/ExtensionDefinition.swift:118-119`
- **Q1 — Reproducible.** Both `guard protocolConformanceDescriptor != nil else { return }` (`:118`) and `guard let protocolConformance = try materializedProtocolConformance(in: machO), !protocolConformance.resilientWitnesses.isEmpty else { return }` (`:119`) return before `isIndexed = true` at `:171`. One interface run touches the same extension at four points: `SwiftDeclarationPrinter.swift:208` (`index()` → materialize → guard fails), `:250` (`try? materializedProtocolConformance`, a second parse), `:305` (`printDefinition` sees `!isIndexed` and calls `index()` again, a third), and `SwiftDiffableInterfaceBuilder.swift:58` (a fourth).
- **Q2 — The defect is pre-existing; the cost is new.** `main:95` has the same unset-flag early return. It was harmless there because the guard read the stored `protocolConformance` property. Evolution 0002 replaced that read with `materializedProtocolConformance(in:)`, which re-parses the conformance and its trailing objects every time. **Fix priority follows the new cost, not the old defect.**
- **Q3 — Worth fixing, one-line.** Typealias-only extensions are the majority case, and this sits on the full-interface export path. Add `isIndexed = true` before both early returns. `SwiftDiffableInterfaceBuilder.swift:58`'s comment (*"idempotent, so this is safe and cheap to re-enter"*) must either become true again or be deleted.
- **Q4 — No prior fix.** The file has three structural commits (`47b5961f`, `aa233bc0`, `d1078902`), none touching this flag.
- **Sweep result:** `TypeDefinition.index(in:)` and `ProtocolDefinition.index(in:)` have no mid-function early returns, so this is the only instance of the pattern.

### H3. The LC_DYLD_INFO bind decoder trusts two binary-supplied uleb128 values with no bounds

- **File:** `Sources/MachOExtensions/MachOFile+.swift:170` (segment index), `:185` (repeat count)
- **Q1 — Reproducible.** MachOKit decodes opcodes without validating them: `set_segment_and_offset_uleb(segment: UInt, offset: UInt)` and `do_bind_uleb_times_skipping_uleb(count: UInt, skip: UInt)` (`../MachOKit/Sources/MachOKit/Model/Bind/BindOperation.swift:27,37`) hand the raw values through. (a) `segmentIndex = Int(segment)` traps on any value above `Int.max`; the `segmentFileOffsets.indices.contains` guard inside `recordCurrentSlot` runs too late to help. (b) `for _ in 0 ..< count` is unbounded — a count of 2^40 either spins inserting dictionary entries until OOM (valid segment index) or simply hangs (invalid one). `segmentOffset` also advances with wrapping `&+` and is never range-checked, so a wrapped offset attributes a symbol name to an unrelated file offset.
- **Q2 — New.** The whole decoder arrived with `5c74ad67`.
- **Q3 — Worth fixing.** `swift-section` analyses arbitrary third-party binaries; the input is untrusted by construction, and dyld itself bounds both values. Every other malformed-input path in this library throws — this is the only one that traps or hangs. Validate `segment` against `segmentFileOffsets.count` before the `Int` conversion, and clamp `count` against the segment size.
- **Q4 — No prior fix.** New code.

### H4. The A/B rendering-parity gate reports success when it compared zero pairs

- **File:** `Scripts/run-rendering-ab-verification.py:269` (verdict), `:225` (swallowed exit code)
- **Q1 — Reproducible.** `compare_all_pairs` derives its verdict solely from `difference_count`, which is only incremented while iterating `output_root.glob('**/baseline/*.txt')`. With no `/Volumes/DyldSharedCaches` archive, no installed iOS simruntime, or a mistyped `--frameworks`, every CLI invocation exits non-zero, `run_pair` unlinks each `.txt` and writes matching `.skip` markers on both sides, and the glob yields nothing — so the loop never runs, `difference_count` stays 0, and `main()` prints `RESULT: all pairs byte-identical.` and exits 0. `run_macho_image_part` compounds it: `:225` only prints `completed.returncode` and never propagates it, so a `swift test` failure in the MachOImage third of the matrix cannot fail the run either. Nothing asserts that at least one pair was produced.
- **Q2 — New.** The script arrived with `df44c465`.
- **Q3 — Worth fixing, above its own size.** AGENTS.md makes this check mandatory for exactly this class of refactor, and its green light was cited as the acceptance evidence for the `MetadataReaderCache` retirement (*"96 对输出全部逐字节一致、零跳过"*). A harness that reads failure as success does not merely fail to catch regressions — it retroactively weakens every conclusion that cited it. Make `compare_all_pairs` fail when the comparison count is zero, and propagate `run_macho_image_part`'s return code.
- **Q4 — No prior fix.** New script.

---

## Medium

### M1. `try?` gives the public `printExtensionHeader` a different error contract from `index(in:)` — *(revised, downgraded to Low)*

> **Revised 2026-08-09**, after the implementing session challenged the original analysis. Two claims in the first version were wrong and are corrected here rather than silently rewritten:
>
> 1. *"the same function now holds two contradictory policies"* — **false**. A thrown materialization and a thrown protocol-node resolution produce the *identical* observable output (no clause). `:246-248`'s comment states this is deliberate. There is no behavioural difference between the two, so the originally suggested fix ("route a thrown materialization into the same branch as a thrown resolution") would have been a no-op with no possible failing test.
> 2. *"the printer emits `extension Foo { … }` with the clause silently gone"* — **not reachable from any in-repo path**, for the reason in Q1 below. The original severity (Medium) was set on the assumption that the main interface path could hit it.

- **File:** `Sources/SwiftPrinting/SwiftDeclarationPrinter.swift:250`
- **Q1 — Not reachable in-repo; reachable only through the public API.** `printExtensionHeader` has exactly one in-repo caller, `printExtensionDefinition:213`, and `:209` immediately above it runs `try await extensionDefinition.index(in: machO)`. `index(in:)` calls the *same* `materializedProtocolConformance(in:)` at `ExtensionDefinition.swift:119` with a bare `try` — propagating. So every in-repo path that reaches `:250` has already proven the materialization succeeds; the `try?` cannot fire. `SwiftDiffableInterfaceBuilder.swift:58` propagates through the same `index(in:)`, and the diff renderer never calls `printExtensionHeader` at all (it handles only types and protocols). The one live exposure is that **`printExtensionHeader` is `public`**: an out-of-repo caller (RuntimeViewer) may call it directly on a definition that was never indexed, and there the `try?` silently yields a header with no conformance clause.
- **Q2 — New, but the reachable half is narrower than the diff suggests.** `main` reads the stored `extensionDefinition.protocolConformance`, where `nil` can only mean "genuinely no conformance". The PR introduces a second meaning for `nil` — but only observable to a direct public caller.
- **Q3 — Worth fixing as an API-contract fix, not a rendering fix.** The cost of fixing is zero on in-repo paths (they cannot reach it), and the benefit is that the public entry point stops having a weaker error contract than the `index(in:)` it is meant to follow. **Fix: make it a bare `try` and let it propagate.** A direct caller then sees the same error `index(in:)` would have raised, instead of a confidently-wrong header; in-repo behaviour is unchanged because the throw cannot occur there. The "propagate → per-definition catch drops the whole extension" worry does not apply in-repo for the same reason.
- **Q4 — Related prior fix, but *not* a recurrence.** `dd1822c6` ("restore pre-leaf-migration contracts across dump/interface paths") fixed a real instance of conflating `nil` and `throw`, and its analysis comment survives at `:251-257`. That comment describes the *closure below*, which still implements the contract correctly. The new `try?` sits above it and does not undo it. Calling this "the same defect recurring" overstated the case.
- **Regression test:** call the public `printExtensionHeader` directly with an un-indexed `ExtensionDefinition` whose materialization throws; assert it throws. Before the fix it returns a header with no clause. This tests the public contract, which is the only thing that changed.
- **Sweep result:** `try? …materialized…` appears at only one other site (`SymbolIndexStore.swift:570`), which wraps a demangle, not a wrapper materialization, and is a different contract.
- **Interaction with H2:** H2's fix sets `isIndexed = true` before the two early returns. Neither creates a new path to this `try?` — `:118`'s early return means the descriptor is `nil`, so the later materialization returns `nil` without throwing, and `:119`'s early return is only reached *after* a materialization that succeeded. The two fixes are independent.

### M2. `MachOImage` symbol names are raw pointers into a live image, owned by a cache entry that is never invalidated on unload

- **File:** `Sources/MachOSymbols/SymbolTable.swift:141`
- **Q1 — Mechanism confirmed by reading; end-to-end trigger not reproduced.** `withNameBytes(atRow:)` does `mappedStringTableBase.unsafelyUnwrapped.advanced(by:).assumingMemoryBound(to: UInt8.self)` for mapped rows. `prepare()` stores `mappedStringTableBase = symbols64.stringBase` (`SymbolIndexStore.swift:441`), and `SharedCache` keys on `MachOTargetIdentifier.image(ptr)` (`MachORepresentableWithCache.swift:95-96`). `dlopen` → prepare → `dlclose` → a later `dlopen` mapping a different dylib at the same address therefore returns the *old* `Storage`, and the next name materialization reads re-mapped memory: garbage names or SIGSEGV. What was **not** established is whether any shipping consumer actually unloads an indexed image.
- **Q2 — New.** On `main` every row owns a copied `String`; image unload is irrelevant.
- **Q3 — Worth fixing, priority depends on Q1's open half.** This is an inherent cost of the memory optimization, not an oversight. A cheap partial mitigation is available regardless: `detachedFromSharedTable()` covers only six internal storing sites, while the public query API still vends the raw pointer — making the public surface return copies closes the externally-reachable half without giving up the internal saving. The full fix is invalidating the cache entry on unload (or keying on something that changes when the image does).
- **Q4 — Related prior work, different layer.** `a7caf944` introduced `detachedFromSharedTable()` to stop a stored value pinning the whole table; that layer is correct. The raw-pointer layer arrived later with evolution 0001, and the guard did not follow it up.

### M3. `PackedNameReference` enforces its bit budgets with `precondition` on binary-supplied values

- **File:** `Sources/MachOSymbols/SymbolTable.swift:31-32`
- **Q1 — Reproducible.** `nameByteLength: strlen(symbol.nameC)` (`SymbolIndexStore.swift:502`) comes from the symbol table. A Mach-O whose `stroff`/`n_strx` point into a region with no NUL before 4,194,303 bytes — truncated, hostile, or a mis-sized LINKEDIT in a dyld subcache — traps the process. Also reachable through the public `DemangledSymbol(symbol:demangledNode:)` initializer, which packs an unclamped length.
- **Q2 — New.** The bit-packed representation, and therefore the budget, arrived with evolution 0001.
- **Q3 — Worth fixing.** Same class as H3: a value that came from the binary decides whether the process lives. `precondition` is fatal in release. Throw, or fall back to the private name buffer.
- **Q4 — No prior fix.** New code.

### M4. `resolveBind(fileOffset:)` gained an LC_DYLD_INFO fallback; `isBind` did not

- **File:** `Sources/MachOExtensions/MachOFile+.swift:225`
- **Q1 — Reproducible.** `resolveBind(fileOffset:)` branches on `dyldChainedFixups` and falls back to the new opcode index; `isBind(fileOffset:)` → `isBind(_:)` → `resolveBind(at:)` still routes through the chained-fixups-only path. On a pre-chained-fixups binary the two public APIs return contradictory answers for the same offset. `isBind`'s doc comment still asserts the file *"must contain dyldChainedFixups data"*.
- **Q2 — New.** `main` fails consistently on both.
- **Q3 — Worth fixing.** A consumer gating a bind read on `isBind` gets nothing on precisely the binaries this fix targets (every iOS 15.5 simulator framework). Route `isBind` through the same fallback and update its doc comment.
- **Q4 — No prior fix.** A missed site in a new feature.

### M5. `detachedFromSharedTable()` detaches the symbol table but not the node store

- **File:** `Sources/MachOSymbols/DemangledSymbol.swift:83`
- **Q1 — Reproducible.** The body is `DemangledSymbol(symbol: symbol, demangledNode: demangledNode)` — `demangledNode` passes through unchanged and still references the per-image `NodeStore` (nodes + edges + text arena for every demangled symbol in the image).
- **Q2 — New.** On `main`, `DemangledSymbol` holds no `NodeReference`; there is no second layer to detach.
- **Q3 — Worth fixing.** `FunctionDefinition.symbol`, `Accessor.symbol`, `TypeDefinition.deallocatorSymbol` / `destructorSymbol` are stored through this call so `removeSubIndexer(_:)` can reclaim per-image memory. The 185,988-row table is released as documented; the arena is not, so the reclamation is partial while the doc comment reads as a full detach. `SymbolTableRetentionTests` only asserts `retainedSymbolTableRowCount == 1` and never inspects the node store — **the guard written for this property is blind to exactly this gap**, so any fix should extend the test too.
- **Q4 — Related prior work.** `a7caf944` designed the single-layer detach; `6b0dad20` added the arena layer without revisiting it.

### M6. `deinit` evicts three caches under a flag that proves ownership of one

- **File:** `Sources/SwiftIndexing/SwiftDeclarationIndexer.swift:170`
- **Q1 — Reproducible.** `didTriggerSymbolIndexStoreCache` is set only by `if !symbolIndexStore.contains(in: machO)` (`:282`), which says nothing about who populated `InternedNodeReferenceCache` or `MetadataReaderCache` — both are filled by any `MetadataReader.demangleContext` / `InternedNodeReferenceCache.reference(interning:)` caller, including the SwiftDump path, SwiftSpecialization, and any second live indexer. With indexer A owning image X and indexer B built later for the same image, A's `deinit` wipes the interned-name store and demangle memo out from under B: B's already-built `TypeName` / `ProtocolName` / `FieldDefinition.typeNode` keep the orphaned store alive while later names land in a fresh one, so B's model is split across two stores — `structurallyEquals`' `store ===` index-compare fast path stops firing for the pre-eviction population (full tree walks on every name dictionary operation) and `MetadataReaderCache` re-pays every context demangle.
- **Q2 — New.** `main`'s `deinit` does only `symbolIndexStore.remove(for: machO)` — one flag, one cache.
- **Q3 — Worth fixing.** Not a crash; a performance cliff in RuntimeViewer's normal multi-indexer shape. The surrounding comment's tolerance (*"worst case is a redundant rebuild"*) was reasoned for the symbol store alone and no longer holds. Give the other two caches their own ownership flags, or refcount them.
- **Q4 — No prior fix.** The two eviction lines are new in this PR.

---

## Low

### L1. Nested children print without a per-child catch, so one bad nested descriptor drops the enclosing type

- **File:** `Sources/SwiftPrinting/SwiftDeclarationPrinter.swift:162` (throwing materialization), `:137-147` (uncaught nested loop)
- **Q1 — Reproducible.** `printTypeDefinition` iterates `typeChildren` / `protocolChildren` with `try await` and no catch. A throw from `:162`'s `try protocolDefinition.materializedProtocol(in: machO)` (or `:132`'s `materializedTypeContext`) escapes the outer `printTypeDefinition`, and the new per-definition `printCatchedThrowing` discards the whole outer type.
- **Q2 — The baseline is worse; the PR is a net improvement.** `main` catches per *block*, so one throwing type blanks every type in the interface — the defect this PR's own `LegacyDyldInfoBindTests` documents as "defect 2". The PR narrowed that to one top-level definition. What is new is an additional *source* of throws (the materializations), on a path whose innermost level still has no protection.
- **Q3 — Defer.** The remaining gap is one more step in the direction the PR already moved, not a regression. When taken, push the catch down into the nested loops.
- **Q4 — This PR is that fix.** `5c74ad67` moved per-block → per-definition and shipped the regression test.

### L2. The fixture compile can deadlock the whole test run, and leaks a temp directory per run

- **File:** `Tests/SwiftInterfaceTests/LegacyDyldInfoBindTests.swift:45`
- **Q1 — Reproducible.** The order is `standardError = pipe` → `run()` → `waitUntilExit()` → `readDataToEndOfFile()`. On a toolchain/SDK mismatch, `xcrun swiftc -target arm64-apple-macosx11.0` emits well over the ~64 KB Darwin pipe buffer; swiftc blocks writing, the parent is parked in `waitUntilExit()`, neither proceeds. Because `fixtureCompilationResult` is a `static let` and the suite is `@Suite(.serialized)`, the first test touching it hangs `swift test` permanently instead of reporting a failure. Separately, the `LegacyDyldInfoBindFixture-<UUID>` directory created at `:27` holds a `.swift` plus a `.dylib` and is never removed.
- **Q2 — New.** New test file.
- **Q3 — Defer, but cheap.** Only triggers on compilation failure; the cost is that failure presents as a hang rather than an error. Drain the pipe concurrently (or call `readDataToEndOfFile()` before `waitUntilExit()`), and clean up the directory.
- **Q4 — No prior fix.** New code.

### L3. `machOFile(by:)`'s early exit is unreachable for anything but a native `<name>.framework` binary

- **File:** `Sources/MachOExtensions/DyldCache+.swift:117`
- **Q1 — Reproducible.** `bestMatchRank = 0` and rank = `pathShapeRank × 2 + Catalyst penalty` (`:21,33,45,99-100`). `libswiftCore.dylib` scores `pathShapeRank` 1 → rank 2, so `accumulateBestMatch` never returns `true`, and `scanReachedBestMatch` enumerates `self`, then `mainCache`, then every sub-cache — thousands of `MachOFile` constructions on a macOS 26 / iOS 27 cache. Same for any name that matches nothing. `FullDyldCache.machOFile(by:)` (`:186`) likewise lost first-match-wins.
- **Q2 — A deliberate correctness-for-speed trade, not a regression.** `main` used `machOFiles().first(where: { $0.match(by: mode) })` — fast, but resolved `SwiftUI` to the accessibility bundle, which is the bug the ranking exists to fix.
- **Q3 — Defer.** The ranking is right; what is missing is an early exit once no better rank is achievable (track the best rank still reachable and stop when the current match ties it).
- **Q4 — Fixed twice already; this is the third round on the same function.** `17ad4358` introduced the ranking (SwiftUI resolving to `SwiftUI.axbundle` → empty dump, exit 0) → `6647359e` fixed it not applying across cache files → now the early exit is unreachable. Three rounds without landing it cleanly: **the fix should ship with a case covering a plain-`.dylib` lookup**, which is the shape all three rounds missed.

### L4. An order-dependent test caps at 500 entries while iterating a deliberately unordered dictionary

- **File:** `Tests/MachOSymbolsTests/SymbolIndexStoreFixtureTests.swift:178`
- **Q1 — Reproducible.** `storage.symbolRowsByOffset` is `[Int: SymbolRowBucket]` (`SymbolIndexStore.swift:199`, with the PR's own comment: *"Plain Dictionary: … nothing iterates it in order"*). Swift dictionary iteration order is seeded per process, so `for (offset, rows) in storage.symbolRowsByOffset` with `guard checkedOffsetCount < 500 else { break }` samples a different 500 offsets every run.
- **Q2 — New.** New test file.
- **Q3 — Defer, but cheap.** It will not report a false failure; it gives unstable coverage. A regression in the raw-vs-canonical offset rebuild that touches only cache-adjusted keys could pass one run and fail the next — in the very test written to pin that rebuild. Sort the keys, or drop the cap.
- **Q4 — No prior fix.** New code.

---

## Cross-cutting sweeps

Per AGENTS.md, each confirmed finding was swept for other instances of the same pattern:

- **H2 (early return without setting `isIndexed`)** — `ExtensionDefinition` only. `TypeDefinition.index(in:)` (`:155-379`) and `ProtocolDefinition.index(in:)` (`:148-202`) have no mid-function early returns.
- **M1 (`try?` over a materialization)** — one other site, `SymbolIndexStore.swift:570`, which wraps `demangleAsNodeTransient`; different contract, not an instance.
- **H3 / M3 (trusting binary-supplied values)** — the two documented sites. Both should be fixed in the same batch since they share a root cause.
- **M2 / M5 (`detachedFromSharedTable`'s coverage)** — the six internal storing sites are covered; the public query API is not (M2), and the node-store layer is not (M5).

---

## Findings recorded but below the cut

Real, verified, but not worth their own entry:

- `Documentations/Internal/ProjectEvolutionLog.md` has no section for evolutions 0002/0003 despite AGENTS.md's "append a section at the end of every non-trivial batch" rule, and its added line 348 links a TaskReports filename that does not exist (`2026-07-25-dyld-cache-…` vs the actual `2026-07-25-cache-…`).
- The new `_dyldInfoBindSymbolNamesByFileOffset` memo uses an unsynchronized `@AssociatedObject(.retain(.nonatomic))` slot read and written from concurrent rendering tasks — the same pattern as the pre-existing `_resolveBindCache`, so it is consistent with its surroundings rather than newly wrong.
- The `MachOImage` leg dedups on `String(cString:)`-repaired UTF-8 while `row(forName:)` memcmps raw bytes, so the `row(forName: symbol(atRow: r).name) == r` round-trip is no longer guaranteed by construction.

## Skipped — already adjudicated or refuted

Listed so the next round does not re-derive them:

- **`memberSymbols(of:excluding:in:)` / `allOpaqueTypeDescriptorSymbols` dictionary keys flipped from `Node` to `NodeReference`** — adjudicated "不修" in [`NodeStoreMigrationOpenIssues.md`](../Documentations/Internal/NodeStoreMigrationOpenIssues.md) item 3 (2026-08-03): `SymbolIndexStore` is SPI at the type level, the one in-package call site never subscripts, and RuntimeViewer has no call sites on either branch.
- **`MetadataReaderCache` materializing per hit** — measured flat (96 byte-identical pairs, 1150 s vs 1148 s).
- **Loss of `concurrentMap`** — measured *faster* (28.6 s → 24.5 s).
- **Per-block → per-definition `printCatchedThrowing`** — intentional, pinned by the new tests (see L1).
- **`[Node: …]` collections supposedly broken by materialization** — `Node`'s `Hashable` is structural.
- **`Symbol.isExternal` always false** — [`NodeStoreMigrationOpenIssues.md`](../Documentations/Internal/NodeStoreMigrationOpenIssues.md) item 8; equally true on `main`.
- The four entries already in [`ReviewAdjudications.md`](../Documentations/Internal/ReviewAdjudications.md) (A1–A3 and the SPI-key entry).

---

## Suggested landing order

1. **B1** alone, to get CI green — nothing else can be verified until then.
2. **H1, H2, M4** — the small, self-contained correctness fixes, each with a regression test that fails before the fix.
3. **H3, M3** — the untrusted-input pair, in one batch.
4. **H4, L2, L4** — the harness and test-hygiene fixes; H4 first, since the other two are verified by it.
5. **M5, M6, M2** — the retention/ownership work, which needs the extended `SymbolTableRetentionTests` from M5 before M2 can be judged.
6. **L1, L3, M1** — deferrable. L3 should ship with the plain-`.dylib` lookup case all three prior rounds missed; M1 (downgraded) is a one-token public-contract fix whose test exercises the public API directly.

Per AGENTS.md, every fix taken from this list ships with a test that fails before it and passes after, retained permanently as a regression test. Any finding later judged "won't fix" moves to [`ReviewAdjudications.md`](../Documentations/Internal/ReviewAdjudications.md) with its reasoning, not silently dropped.

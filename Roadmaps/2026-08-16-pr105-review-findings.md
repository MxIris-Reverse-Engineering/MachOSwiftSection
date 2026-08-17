# PR #105 Code Review Findings

Review date: 2026-08-16
PR: `next` → `main`, head `ab51750b`, merge base `32bf83c1` (137 files, +11,335 / −972)
Review depth: automated multi-agent review at `max` effort, **run five times independently**. Each run used 10 finder angles plus a verification sweep, built against the local sibling checkouts (`USING_LOCAL_DEPENDENCIES=1`). Dependency-version/tag findings were excluded by instruction; the 12 entries already adjudicated in `Documentations/Internal/ReviewAdjudications.md` (A1–A12) were skipped.

Cross-review: **complete (2026-08-16)**, by an independent session on the same project — the same practice used for proposals 0002/0003 and PR #103's rounds two through four. Its verdicts are recorded inline under each finding. It also ran the thing five review passes did not: the full suite (`--skip IntegrationTests`) is **green, exit code 0, 1433 tests / 270 suites**.

Status: **Open — nothing implemented.** The four mandatory questions (reproduce / baseline / worth fixing / fixed before) have been answered only where the cross-review answered them; the rest is still raw. Nothing has been written into `ReviewAdjudications.md` yet.

Earlier rounds on the predecessor branch: [2026-08-09](2026-08-09-pr103-review-findings.md), [2026-08-14](2026-08-14-pr103-review-round-three-findings.md), and round four in `Documentations/Internal/TaskReports/2026-08-16-pr103-review-round-four-event-reporting.md`.

## How to read this file

Findings keep their original numbering and original wording; the cross-review's verdict is appended to each, per this repository's rule that a review record keeps its historical shape and corrections are added rather than edited in. **Two findings were rejected outright and five were downgraded** — those corrections are the most instructive part of the round, exactly as they were in PR #103's third round.

The confidence column records how many of the five independent runs reported each finding. A 5/5 finding is a strong signal (agents converged from different angles); a 1/5 finding still turned out to be worth reading, but note that both 1/5 entries were the ones the cross-review rejected or reclassified.

| # | Location | Confidence | Original claim | Cross-review verdict |
|---|---|---|---|---|
| F1 | `SwiftIndexing/SwiftDeclarationIndexer.swift:366` | 5/5 | diff-introduced | **upheld**, plus a second consequence |
| F2 | `SwiftInterface/SwiftDiffableInterfaceRenderer.swift:538` | 5/5 | diff-introduced | **downgraded** — rendering-layer only, one claim wrong |
| F3 | `MachOSymbols/SymbolIndexStore.swift:510` | 5/5 | diff-introduced | **merged into F3+F13**, threat model undecided |
| F4 | `swift-section/Commands/InterfaceCommand.swift:91` | 5/5 | pre-existing, in scope | **upheld**, one sibling claim corrected |
| F5 | `SwiftDeclaration/Events/SwiftIndexEvents.swift:404` | 5/5 | new machinery | **upheld**, frequency low |
| F6 | `SwiftInterface/SwiftInterfaceBuilder.swift:64` | 5/5 | diff-introduced | **downgraded** to a one-line nit |
| F7 | `SwiftInterface/SwiftDiffableInterfaceRenderer.swift:503` | 5/5 | diff-introduced | **half rejected** — no start event exists on that path |
| F8 | `SwiftIndexing/SwiftDeclarationIndexer.swift:1113` | 5/5 | diff-introduced | **upheld**, confirmed a real regression |
| F9 | `SwiftDeclarationRendering/MultiPayloadEnumDescriptorCache.swift:29` | 5/5 | incomplete new eviction | **downgraded** — magnitude overstated |
| F10 | `SwiftIndexing/SwiftDeclarationIndexer.swift:250` | 5/5 | diff-introduced | **REJECTED** — wrong location, proposed fix is a no-op |
| F11 | `SwiftDeclaration/Components/Definitions/ProtocolDefinition.swift:188` | 5/5 | pre-existing shape, widened | **upheld and promoted** — exclusivity confirmed |
| F12 | `swift-section/Commands/SnapshotCommand.swift:44` | 5/5 | diff-introduced | **upheld**, proposed fix insufficient |
| F13 | `MachOSymbols/SymbolTable.swift:180` | 1/5 | diff-introduced | **reclassified** — not diff-introduced, merged with F3 |
| F14 | `Tests/SwiftInterfaceTests/PrintFailureEventTests.swift:299` | 5/5 | new guard, holed | **upheld**, premise verified against git history |
| F15 | `Tests/SwiftInterfaceTests/SymbolTableRetentionTests.swift:34` | 3/5 | new storing sites | **downgraded** — coverage improvement, not a live hole |
| F16 | `SwiftInterface/SwiftInterfaceBuilder.swift:157` (+ ~13 siblings) | 5/5 | diff-introduced | **upheld and promoted** — mechanism is worse than claimed |
| F17 | `SwiftSpecialization/GenericSpecializer.swift:631` | 1/5 | diff-introduced | **REJECTED** — the PR improves this line |
| F18 | `SwiftIndexing/SwiftDeclarationIndexer.swift:213` | cross-review | pre-existing | **new** — found by the cross-review |

---

## Implementation order

Revised after the cross-review; the original grouping (below) was organized by defect class, this is organized by what to do.

**Before merging**

1. **F16** — the only finding that costs on *every* run, the fix is cheap, and it undercuts the PR's own performance claim. Highest return.
2. **F1** — low probability (needs a host to prepare concurrently; no in-repo caller, so SPI consumers only) but diff-introduced, and the consequence is total data loss. Cheap fix.
3. **F11** — conditional (re-render after a caught failure) but on trigger two consumers read corrupted data at once. One-line fix. The cross-review considers this the closest thing in the list to "silently wrong on real input".
4. **F8** — folds in with F1: move the statistics snapshot to after the four extraction passes and before `index()`. The six counters only ever depended on those four arrays.

**Next**

F2 (as a rendering-layer defect), F5, F7 (the `kind` half only), F12, F14.

**Deferred pending a decision**

F3 + F13, merged into one hostile-input hardening item. Decide the threat model first — does this library defend against malicious binaries, and how was A4 settled? — then decide whether to fix. The check belongs at collection time, not in `SymbolTableBuilder`.

**Rejected or reduced**

F10 (wrong location), F17 (backwards), F6 (one-line nit), F15 (coverage improvement), F9 (measure first).

---

## The must-fix set, and how to fix each

Six of the seventeen should not be merged as they stand. The reasons fall into three kinds, and the kind matters more than the severity ranking:

- **Merging them means merging a new bug** — F1, F11, F8.
- **Leaving them makes a claim this PR itself makes untrue** — F4 (the PR says `Closes #102`), F14 (the PR writes a rule into AGENTS.md and names this test as its enforcement).
- **One line, and it happens on every single run** — F16.

Everything else can follow later: F2 (a rendering-layer false negative, the CI gate is unaffected), F5, F6, F7, F9, F12, F15. **F10 and F17 must not be touched — they are wrong.** F3+F13 waits on a threat-model decision. F18 waits on checking whether adjudication A8 already covers it.

Ordering below is by how settled the fix is, not by severity: the first four are ready to write, F8 is blocked on a test seam, F1 needs two decisions first.

### F16 — `SwiftPrinting/SwiftDeclarationPrinter.swift:642`

```swift
context: SwiftIndexEvents.PrintingContext? = nil,
// becomes
context: @autoclosure () -> SwiftIndexEvents.PrintingContext? = nil,
```

with `:649` becoming `if let context = context()`. **None of the ~14 call sites change** — an autoclosure argument is spelled exactly as the value was.

Risk to verify at compile time: the function is `async` and carries `isolation: isolated (any Actor)?`. The closure is non-escaping and is called synchronously inside `catch`, never across an `await`, so this should hold — but if the compiler objects on `Sendable` grounds, the fallback is an explicit `() -> PrintingContext?` with a closure at each of the 14 sites.

Test: pass a `context` expression that sets a flag, let the body return normally, assert the flag is **not** set. Red before the fix, since a plain parameter is always evaluated.

### F11 — `SwiftDeclaration/Components/Definitions/ProtocolDefinition.swift:158`

```swift
guard !isIndexed else { return }
strippedSymbolicRequirements.removeAll(keepingCapacity: true)   // add
let dumpedProtocol = try materializedProtocol(in: machO)
```

Placing the reset **before** `materializedProtocol(in:)` is deliberate: a retry after that call itself throws then also starts from a clean array.

Deliberately untouched, because the cross-review confirmed each is already idempotent: `defaultedRequirementPWTOffsets` (`:185`, a `Set` insert), `associatedTypes` (`:172`, assignment), `orderedMembers` (`:201`, assignment), `setDefinitions` (assignment), `defaultImplementationExtensions` (`:209`, assignment). `strippedSymbolicRequirements` is the only accumulating one.

Test: `index(in:)` is `package`, so call it twice with `isIndexed` reset in between — the retry path without having to manufacture a failure. Assert `strippedSymbolicRequirements.count` is unchanged; it doubles before the fix.

### F14 — `Tests/SwiftInterfaceTests/PrintFailureEventTests.swift`, three separate holes

**(a) `:299`** — deleting `preceding != "."` is not the fix; that clause is why `node.print(using:)` does not fire. Instead, when the preceding character is `.`, walk back to the identifier before it and treat **`Swift`** as a bare call (module-qualified stdlib), while a value member access stays exempt.

**(b) `:199–205`** — add `debugPrint(`, `dump(`, `NSLog(`, and the `fwrite(`-to-stdout shape to the detection set.

**(c) `:169` / `:177` / `:188–189`** — match the allowlists on a repo-relative path instead of `lastPathComponent`, so a new file that happens to share a basename is not exempted wholesale.

Consequence to handle in the same change: `Sources/MachOFixtureSupport/Extensions.swift:45` and `:53` (`Swift.print(self)`) go red once (a) lands. **Fix those two lines rather than widening the allowlist** — widening the exemption is the exact thing this finding criticises.

Test: extend the existing self-check `theStreamWriteScannerDiscriminates` (`:309`) — `Swift.print(error)` must fire, `node.print(using:)` must not, `debugPrint(x)` must fire. Red before the fix.

### F4 — `swift-section/Commands/InterfaceCommand.swift:91,95,99,102` and `DumpCommand.swift:285-287`

The four `print(...)` calls become `fputs(… + "\n", stderr)`, following the shape the sibling commands already use (`DiffCommand.swift:240`, `EvolutionCommand.swift:115`); factor out a shared `log` while doing it. `DumpCommand.dumpError` moves to stderr too — it currently writes errors to stdout regardless of `-o`.

Deliberately untouched: `DumpCommand.swift:303`'s `print(string)` and `printColorfully`'s `print` are **product output**. This is also why the fix is not "drop `swift-section` from the scanner's `hostModules`" — that would flag every product-output write.

Test: `SwiftSectionCommandTests` already has `@testable import swift_section`; drive the interface command and assert stdout contains only Swift source.

### F8 — `SwiftIndexing/SwiftDeclarationIndexer.swift:353-361` moves up

Move the whole `preparationStatistics` block to just before `:303` — after the four extraction passes, before the symbol-index build and `index()`. The six counters read only `types` / `protocols` / `protocolConformances`, all populated by `:302`, so this is a pure move with no logic change.

The comment moves with it and needs rewriting: it currently explains the snapshot as "freeze before the populations are released", but after the move the motivation is "freeze before anything that can throw" — the release is merely what happens later.

**Blocked on a test seam.** Asserting the fix means making `index()` throw while extraction succeeded, and there is no injection point for that today. Write the test first and let it decide: if no seam can be built, the fallback is extracting the statistics computation into a pure function and testing that directly — weaker evidence, and it should be labelled as such rather than presented as a regression test.

### F1 — `SwiftIndexing/SwiftDeclarationIndexer.swift:259-378`, needs two decisions first

Not a one-liner. `isPrepared` (`:165-166`, `@Mutex`) is read at `:260` and written at `:377`, with the entire preparation run and many `await` points in between. Each access is atomic; the pair is not, and locking the flag harder does not help.

Proposed shape — in-flight task de-duplication:

```swift
@Mutex private var preparationTask: Task<Void, any Error>?

public func prepare() async throws {
    // under the lock: take the existing task, or create one
    // outside the lock: try await task.value
}
```

A second caller awaits the same task and receives the same outcome, so the preparation body cannot run twice concurrently at all.

**Decision 1 — do F18 in the same change?** They are two faces of one state machine: `updateConfiguration` (`:213`) is silently a no-op precisely because `isPrepared` never resets. Moving to a task gives "reset" a real meaning (discard the stored task), which fixes F18 for free. Doing F1 alone means deliberately preserving the never-resets behaviour, which is awkward. Recommendation: do both — but first check whether adjudication A8 already covers F18.

**Decision 2 — cancellation semantics.** `Task {}` escapes the caller's isolation and cancellation. If one caller cancels, what happens to the other waiter? The cheapest answer is that preparation does not respond to cancellation (which is today's behaviour anyway), but that should be written down as a decision rather than inherited by accident.

Test: two concurrent `prepare()` calls, then assert `allTypeDefinitions` is non-empty **and** extension definitions did not double (the cross-review confirmed `:521`/`:526`/`:532` and `:896`/`:900` are appends). Red before the fix.

### Two non-code prerequisites

- **CI cannot pass** until upstream `swift-demangling` ships a tag carrying `SharedNodeStore`, `NodeStoreBuilder.reserveCapacity(expectedSymbolCount:)`, `NodePrinterTarget.writtenUnitCount`, and the split node factories. `0.5.1` is the newest tag and has none of them; the local build works only through the sibling checkouts.
- **`Version.swift` is still `0.15.2` with no changelog entry**, while this PR removes public API (`Symbol.nlist`, `TypeName`/`ProtocolName`/`ExtensionName.node` retyped and no longer `Codable`, `parentContext` gone, `ConsoleEventHandler` on stderr). Either write them up in this round or decide explicitly to fold them into the next release — but it needs to be a decision, not an omission.

---

## Group A — silently produces a wrong result

### F1 — A concurrent second `prepare()` publishes an empty model over a finished one

`prepare()` now releases the section-wrapper transients at its end (`currentStorage.types/protocols/protocolConformances/associatedTypes = []`, :366–369) and sets `isPrepared` only afterwards (:379), while the guard at :260 is still a plain check-then-set on an `async` entry point. Two tasks interleave at any of the many awaits: task A clears the arrays; task B, already past the guard and inside `indexTypes()`, reads them empty (:425/431/462) and then **assigns** — not merges — its empty result over A's completed one (:537–538). Output is an interface with zero types: no error, no event.

Reachable in-repo: `addSubIndexer` is public (:223) and `prepare()` drives `for subIndexer in subIndexers { try await subIndexer.prepare() }` (:264), so two parents sharing one sub-indexer reach it. The PR's own registry comment (:1205) states the premise — "a concurrent second call genuinely reaches the registration."

On `main` the arrays were never released, so the identical race was wasteful but correct. **This PR converts a benign race into silent total data loss.**

> **Cross-review — upheld, with a second consequence the original write-up missed.** Beyond "empty overwrites full", a concurrent or repeated `prepare()` also **doubles** extension definitions: `currentStorage.typeExtensionDefinitions[...].append(contentsOf:)` (:896/:900) and the `indexTypes` sites at :521/:526/:532 are appends, not assignments. The original only described the assignment overwrite at :537–538. Probability is low in practice (no in-repo caller prepares concurrently; the exposure is SPI consumers), which is why the revised order puts F16 ahead of it — but it stays in the "before merging" set.

### F2 — A failed header on one side makes a real ABI change read as `.unchanged`

`resolveHeaders`, `:538` and its mirror at `:540`: `case let (.failed, .rendered(newHeader)): (old: newHeader, new: newHeader)` — the surviving side's text is substituted for the failed one. The marker was already fixed to `.unchanged` (both definitions present), and `DiffContainerAssembler.assemble` decides visibility with `if oldHeader.string != newHeader.string` (`DiffContainerAssembler.swift:32`). Identical strings take the else branch and emit a single unchanged line.

Concretely: old binary `struct Foo: Codable`, new binary `struct Foo: Codable, Sendable`, old header throws → the diff prints the **new** binary's header as an unchanged declaration and reports no header change. ~~`--fail-on-breaking` passes.~~

Header rendering genuinely throws on this path since proposal 0002 put `materializedTypeContext(in:)` / `materializedProtocol(in:)` there. On `main` the failed side degraded to an empty `SemanticString`, which compared unequal and produced a visible `-`/`+` pair — malformed, but not a false negative. The three-state `HeaderOutcome` fixed the delete-from-both-sides bug and introduced this in its place.

> **Cross-review — downgraded from A to B; one claim struck.** The substitution and the string-equality else branch are both real and were verified. But **`--fail-on-breaking` is unaffected**: the verdict runs through `DiffCommand.swift:91-92`'s `ABIDiffer().diff(old: oldBuilder.abiModule(), new: newBuilder.abiModule())` and `:130`'s `hasBreakingChange`, both reading the indexed model, with no dependency on the renderer's headers. The CI gate cannot be fooled by this. The chosen example was also poorly picked — `Codable` → `Codable, Sendable` is additive, so `--fail-on-breaking` passing is correct behaviour regardless. What remains is a **rendering-layer false negative**: the human-readable diff drops a header change. Real, worth fixing, not a Group A defect.

### F3 + F13 — Hostile-input handling around mapped symbol names *(merged by the cross-review)*

**F3 (original, 5/5):** `canonicalRow(forName: String(cString: symbol.nameC), mappedNameByteOffset:…, nameByteLength:…)`. The key goes through `String(cString:)`, which replaces invalid UTF-8 with U+FFFD; the row stores the **raw** bytes of the mapped string table. Two consequences:

1. Two symbols whose names differ only in invalid bytes repair to one key, hit `tableRowByName`, take `updateRowInPlace` (`SymbolTable.swift:277–295`) and collapse onto one row — the second's `canonicalOffset` overwrites the first's, so the first symbol's members resolve to the wrong address.
2. The surviving row is unfindable by name forever: `SymbolTable.row(forName:)` (`:201–220`) byte-compares the query's UTF-8 (repaired) against the stored raw bytes, misses, and the query falls through to `lateDemangledNode` — re-demangling under the late-cache lock and breaking the PR's own `tableCoveredNameNeverEntersLateCache` invariant.

The `MachOFile` leg is self-consistent (key and bytes are both `name.utf8`); only the reader-split image leg diverges. The doc comment at `SymbolTable.swift:185–187` asserts the two decoders are equivalent, which is true — but the comparison here is decoded-against-raw, not decoder-against-decoder. Before evolution 0001 each row held one resident `String` and there was no raw/decoded split at all.

**F13 (original, 1/5):** geometry is validated only against `PackedNameReference`'s packing budgets (2^40 offset, ~4 MB length), never against the string table's actual extent. A crafted `n_strx` pointing past LINKEDIT but into other mapped memory containing a `$s` prefix and a later NUL passes `nameBytesHaveSwiftManglingPrefix`, terminates `strlen`, packs fine, and is stored. Every later `DemangledSymbol.name` / `.symbol` / `materializedName` re-derives `mappedStringTableBase.unsafelyUnwrapped.advanced(by:)` and decodes whatever is there. ~~Threading a `stringTableByteCount` into `SymbolTableBuilder` fixes it.~~

> **Cross-review — merged, and both entries corrected.**
>
> These are one threat model, and grading one 5/5-into-Group-A while listing the other as a 1/5 aside is not self-consistent. The **only** source of divergence between the repaired key and the raw bytes is invalid UTF-8 in a symbol name — and Swift mangling is all-ASCII (non-ASCII identifiers go through punycode), with `nameBytesHaveSwiftManglingPrefix` already filtering non-Swift symbols out. **A well-formed binary cannot trigger either consequence.**
>
> F13's "diff-introduced: yes" is **wrong**. The first out-of-bounds access happens at collection time, in `nameBytesHaveSwiftManglingPrefix(symbol.nameC)` and `strlen(symbol.nameC)` (`:505`/`:512`) — and `main` reaches the same memory through `for symbol in machO.symbols where symbol.name.isSwiftSymbol` (`:525`), where MachOKit's `MachOImage.Symbol.name` is `String(cString: nameC)` over `nameC = stringBase.advanced(by: n_strx)`, equally unchecked (`MachOKit/Sources/MachOKit/MachOImage+Symbols.swift:13/25/175-186`). **The same out-of-bounds read exists on `main`.**
>
> Consequently the proposed fix is also wrong: threading a byte count into `SymbolTableBuilder` cannot prevent a `strlen` that has already run. The check must go at the collection site or upstream in MachOKit.
>
> **Deferred pending a threat-model decision** — does this library defend against malicious binaries, and on what terms was A4 settled? Answer that first, then decide.

---

## Group B — diagnostics land in the wrong place (this PR's own subject)

### F4 — `swift-section interface` still writes progress to stdout

`:91`, `:95`, `:99`, `:103` are bare `print(...)`, and `:107` streams the generated interface to the same stream. `swift-section interface <binary> > out.swift` therefore produces a file whose first lines are English prose — not compilable Swift, and the same failure mode as issue #102's embedded `unexpected(at: 8)`. ~~`DumpCommand` has the same shape.~~

Every library site was converted this PR and `ConsoleEventHandler` moved to `fputs(…, stderr)` precisely to end this. The new guard cannot see it: `PrintFailureEventTests.swiftSourceFiles()` excludes the `swift-section` module (`hostModules`, `:276`).

> **Cross-review — upheld; the `DumpCommand` sentence is wrong and hides a better target.** `DumpCommand` has no progress prints (`:303`/`:310` are product output). What it does have is `dumpError` (`:285-287`), which routes errors through `printColorfully` to **stdout**, regardless of whether `-o` was passed. That is the line worth fixing there. `InterfaceCommand`'s four prints stand as reported.

### F5 — Two real losses classified as progress in the zero-handler floor

`unhandledFailureDescription` puts `.extensionTargetNotFound` (`:404`) and `.nameExtractionWarning` (`:407`) in the `return nil` arm, so `Dispatcher.reportUnhandled` (`:134`) drops them and a host with no handler attached learns nothing. Both are losses at their dispatch sites: `SwiftDeclarationIndexer.swift:623` dispatches `.nameExtractionWarning(for: .protocolConformance)` on the line before `failedConformances += 1` (`:647` likewise for associated types), and `:791` dispatches `.extensionTargetNotFound` immediately before a `continue` that discards a whole extension and every member in it. `SwiftIndexEventReporter` and `OSLogEventHandler` both treat them as warnings — only the floor disagrees.

The method's own doc (`:366–368`) states the rule being broken: the whitelist is a whitelist so that "a new failure case added without a branch here would silently opt out of the floor, which is exactly the class of regression the floor exists to stop."

> **Cross-review — upheld, and the frequency question answered.** Both dispatch sites are genuine losses as described. Trigger frequency is low: `typeInfoByName` and the query key both come from the same `print(using: .interfaceTypeBuilderOnly)` (`SymbolIndexStore.swift:716-722` vs the indexer's `:789`), so `extensionTargetNotFound` is essentially a defensive branch. Adding both to the floor will not flood the log — safe to fix.

### F6 — The SPI init leaves the injected indexer and printer sink-less

`init(indexer:printer:eventHandlers:in:)` (`:64–70`) creates a fresh `Dispatcher`, calls `addHandlers` on it, and never touches `indexer.eventDispatcher` or `printer.eventDispatcher` — while `SwiftDeclarationPrinter` has a `package init(eventDispatcher:in:)` designed for exactly that, and the public init (`:54–61`) does seed all three. A consumer passing `[ConsoleEventHandler()]` gets `printRoot`'s block-level events and loses every printer-internal one.

~~This is byte-for-byte the defect the PR diagnosed and fixed in `SwiftDiffableInterfaceRenderer.init`.~~

> **Cross-review — downgraded to a one-line nit.** Not the same defect. The diff renderer constructed its *own* sink-less printer via `.init(in:)`; this init receives an indexer and printer the **caller already built**, and a caller that cares about handlers will have constructed them with its own. `grep 'SwiftInterfaceBuilder(indexer:'` across the repo: zero hits. Adding the `addHandlers` line is cheap and fine to do — but "byte-for-byte the same defect" overstates it.

### F7 — The shared header reporter hardcodes `kind: .type`

`header(_:subject:dispatchingTo:_:)` builds `context: .init(name: subject ?? "<unnamed>", kind: .type)` unconditionally (`:503`), but `renderProtocol` uses it too (`:210`/`:215`). A failed protocol header reports as `Failed to print type 'SwiftUI.View'`, and is invisible to any consumer filtering on kind. ~~It cannot be paired with its `.protocol` start event.~~

> **Cross-review — half rejected.** The hardcoded `kind` is real and worth a parameter. The pairing argument must be struck: **there is no start event on this path at all.** Neither `printTypeHeader` nor `printProtocolHeader` (`SwiftDeclarationPrinter+DiffRendering.swift:27`/`:61`) dispatches `.definitionPrintStarted`, so there is nothing to pair with in the first place.

### F8 — Statistics report 0 after a failed `prepare()`

The six public accessors (`:1113–1128`) read `currentStorage.preparationStatistics`, assigned in one block (`:353–361`) reached only when `index()` did not throw. On `main` they were computed live off the arrays and stayed correct on the failure path. Now a host that catches the prepare error and reports progress shows "0 types, 0 protocols" for an image whose extraction succeeded and whose `rootTypeDefinitions` is populated — indistinguishable from a binary with no Swift content, which is the outcome the snapshot's own comment says it exists to prevent.

> **Cross-review — upheld as a genuine regression.** `git show 32bf83c1:` confirms `main`'s accessors compute live from the arrays. Fix is placement, not logic: move the snapshot to after the four extraction passes and before `index()`, since the six counters only ever depended on those four arrays. Folds naturally into the F1 batch.

---

## Group C — resource handling and robustness

### F9 — Two of five per-image caches are never evicted

`grep ': SharedCache<' Sources/` yields five: `SymbolIndexStore`, `InternedNodeReferenceCache`, `MetadataReaderCache`, `MultiPayloadEnumDescriptorCache`, `PrimitiveTypeMappingCache`. `SwiftDeclarationIndexer.deinit` evicts the first three (`:189`/`:205`/`:208`); `grep '\.remove(for:' Sources/` finds no call site for the other two.

`MultiPayloadEnumDescriptorCache.Storage` holds `[Node: MultiPayloadEnumDescriptor]` — class `Node` trees, one entry per multi-payload enum, keyed per image. ~~That is exactly the retention class this PR exists to remove (208,809 → 44 live `Node` instances).~~

> **Cross-review — downgraded; magnitude overstated.** The missing eviction is real (the grep result holds). But `MultiPayloadEnumDescriptorCache.Storage` holds on the order of the image's `__swift5_mpenum` record count — hundreds of nodes, not a comparable quantity to 208,809 — and `PrimitiveTypeMappingCache` is a small fixed table. **Measure before deciding whether this deserves its own item.**

### F10 — ~~The whole teardown runs inside an `os_unfair_lock`~~ **REJECTED**

Original claim: `_subIndexers.withLock { registeredSubIndexers.remove(at: index); return true }` (`:250–254`) discards the removed element **inside** the closure, so when that was the last reference the sub-indexer's `deinit` runs under the lock, dragging an `NSLock`, three cache evictions and a 185,988-row table free into a non-recursive spin lock's critical section.

> **Cross-review — REJECTED at the cited location.** `removeSubIndexer(_:)`'s parameter is itself a strong reference, and Swift's `@guaranteed` convention requires the caller to keep it alive for the whole call. `remove(at:)` therefore **cannot** be dropping the last reference, and the deinit cannot run inside that `withLock`. The proposed one-line fix (hoist the removed element out of the closure) is a **no-op** here.
>
> The mechanism is real, but in a **different function**: `removeSubIndexer(at:)` (`:228–231`). `@Mutex` generates a `_modify` accessor (FrameworkToolbox `Sources/SwiftStdlibToolboxMacros/MutexMacro.swift`, `makeModify`: `_unsafeLock()` → `yield` → `defer { _unsafeUnlock() }`), so `subIndexers.remove(at: index)` runs entirely inside the `os_unfair_lock` and the discarded return value is released there — and at that call site the caller may genuinely hold no other reference. That function dates to `47b5961f` and is **identical on `main`**: not diff-introduced, and not at the line this finding named.

### F11 — A retry duplicates every stripped-requirement record

`ProtocolDefinition.index(in:)` appends to `strippedSymbolicRequirements` (`:188`) inside a loop that can throw at `:187` (`try await Symbols.resolve`) or `:193` (`try requirement.defaultImplementationSymbols`), and this PR added a further throwing `try materializedProtocol(in: machO)` at the head (`:159`). `isIndexed = true` is only reached at `:212`, left false on purpose "so a failed read can be retried" — but the array is never reset, so the retry appends the same records again.

Unlike the sibling case the PR documented (`ExtensionDefinition.swift:69–72`, "inert only because nothing reads the array"), **this array is read**: `ABIDiffer.swift:292` projects one `pwtslot:<offset>` record per entry (duplicates become exactly the key collisions `ABISnapshot.keyCollisions()` reports as a defect) and `SwiftDeclarationPrinter.swift:240–241` emits one `MemberList` per entry (the protocol prints each requirement twice).

Reachable in the browse flow: `printProtocolDefinition` guards on `!isIndexed`, so a host re-rendering a protocol after a caught failure re-indexes it. `SwiftDiffableInterfaceBuilder.prepare()` documents `index(in:)` as "idempotent, so this is safe and cheap to re-enter," which this makes false. The sweep for the same shape stopped one file short.

> **Cross-review — upheld and promoted.** Considered the closest thing in the list to "silently wrong on real input". The exclusivity claim was checked and holds: `setDefinitions` assigns, `defaultedRequirementPWTOffsets` is a `Set`, and `TypeDefinition.index` uses a local `indexedFields` (`:179`/`:209`) — so `strippedSymbolicRequirements` is the **only** accumulating array, and `ExtensionDefinition.missingSymbolWitnesses` has no readers repo-wide, as the PR documents. Fix is one line: clear the array at the head of `index(in:)`.

### F12 — `snapshot` truncates its baseline silently and exits 0

`_ = fwrite(buffer.baseAddress, 1, buffer.count, stdout)` (`:44`) drops the byte count, the following `fputs("\n", stdout)` drops its result, and nothing checks `ferror(stdout)` or flushes before return. On a full disk, a quota-limited volume, or a closed pipe, `swift-section snapshot Foo > baseline.json` writes a partial document and reports success — and that baseline is what `diff --fail-on-breaking` / `evolution` gate CI against.

The replaced `FileHandle.standardOutput.write(encoded)` raised on failure. Removing it was correct (the ObjC bridge aborts the host — that is round four's whole point), but it traded a loud failure for a silent one. ~~Check the count against `buffer.count` and exit non-zero.~~

> **Cross-review — upheld, but the proposed fix does not work.** stdout redirected to a file is **fully buffered**, so a full-disk or quota error will almost never surface as a short `fwrite` return — the error appears when the buffer flushes, and `exit()`'s stream cleanup swallows it. Comparing against `buffer.count` does not catch the scenario the finding describes. The fix must be `fflush(stdout)` followed by `ferror(stdout)`. (The body of the finding mentions both; only the closing recommendation was wrong, and implementing that closing line verbatim would produce a fix that does not fix.)

---

## Group D — the guards themselves do not hold

### F14 — The stream-write scan cannot see `Swift.print(`

`containsBareCall` skips any occurrence whose preceding character is `.` (`:299`, `preceding != "."`). The line this PR removed from `Node+OpaqueType.swift` was literally `Swift.print(error)` — so re-introducing the exact bug the guard commemorates leaves it green. Two live instances already pass it today: `Sources/MachOFixtureSupport/Extensions.swift:45` and `:53` (`Swift.print(self)`, compiled in unless `MACHO_SWIFT_SECTION_SILENT_TEST` is exported), in a module the scan does include.

Two further holes: the scan looks for none of `debugPrint(`, `dump(`, `NSLog(`, `fwrite(`; and `sinkImplementations` / `knownBaselineDebt` match on `fileURL.lastPathComponent`, so a new file anywhere under `Sources/` with one of those basenames is exempt wholesale — the set can grow, contradicting the comment's "may shrink, never grow."

> **Cross-review — upheld, premise verified against git history.** `6141c753 fix(printing): report dropped definitions as events, not on stdout` did remove a `Swift.print` from `Node+OpaqueType.swift`, so "the guard cannot see the very line it commemorates" is literally true. The two `Swift.print(self)` instances in `MachOFixtureSupport/Extensions.swift` are in scan scope and passing today — confirmed by the same green run that included `libraryModulesWriteToNoProcessStream`.

### F15 — The detach-contract test only walks `TypeDefinition`

The suite enumerates `indexer.allTypeDefinitions` and probes a hardcoded six-collection list, asserting `retainedSymbolTableRowCount == 1`. `ExtensionDefinition` and `ProtocolDefinition` store `DemangledSymbol` values through the same `DefinitionBuilder` paths and are never visited. ~~A new storing site that forgets `detachedFromSharedTable()` pins a 185,988-row table per image with the suite green.~~

> **Cross-review — downgraded to a coverage improvement.** Four of the six storing sites are in `DefinitionBuilder` (`:26`/`:72`/`:134`/`:194`), which extension and protocol definitions go through as **the same code**; the other two (`TypeDefinition.swift:305`/`:306`, deallocator/destructor) are `TypeDefinition`-only by nature. So all six existing sites *are* covered today. What remains is the future risk: a new storing site reachable only from `ExtensionDefinition` or `ProtocolDefinition`. Worth hardening (drive off `OrderedMember.allMembers(from:)`, or make detachment type-enforced), but there is no live hole.

---

## Group E — performance and hygiene

### F16 — ~14 new eager full-name print walks on the success path

`printCatchedThrowing` takes `context:` as a plain parameter, so `.init(name: typeDefinition.typeName.name, kind: .type)` evaluates before the body, for every definition, whether or not anything throws. `DefinitionName.name` is `node.print(using: .interfaceTypeBuilderOnly)` with **no memoization** (`DefinitionName.swift:9–15`).

Sites: `SwiftInterfaceBuilder.swift:157/174/186/198/210`, `SwiftDeclarationPrinter.swift` (the four nested-child loops and the default-implementation loop), `SwiftDiffableInterfaceRenderer.swift` (two `subject:` arguments). For root types and protocols it is a literal duplicate — `printTypeDefinition` / `printProtocolDefinition` compute the same name again for their own printing context.

Fix: `context: @autoclosure () -> PrintingContext?` — the same treatment upstream just applied to `NodePrinterTarget.write(_:context:)` in this very PR.

> **Cross-review — upheld and promoted to first place; the mechanism is worse than the finding claimed.** The full chain was traced: `DefinitionName.name` → `NodeReference.print(using:)` (synchronous) → `DemanglingPrinter.print(_:options:)` (`swift-demangling/Sources/Demangling/Node/Printer/NodePrinter.swift:111-116`) → `StackSafeExecutor.executeWithUncheckedSendability`. `minimumRemainingStackSize` is **2 MB** (`StackSafeExecutor.swift:50-52`) while every Darwin thread except the main one gets a **512 KB** stack — as that file's own header comment states. So on a cooperative thread `currentThreadHasSufficientStack` is **always false**: the thread hop and `DispatchSemaphore` block are not a possibility, they happen **every single time**. `context:` is confirmed a plain parameter (`SwiftDeclarationPrinter.swift:639-644`). `@autoclosure` is the right fix.
>
> **Same shape on `main`, possibly larger**: `ProtocolDefinition.index`'s `_symbol` (`ProtocolDefinition.swift:163-171`) runs `protocolNode.print(using:)` once per **candidate symbol** per requirement — one hop each. `git show 32bf83c1:` confirms `main` has the same shape, so it is not this PR's debt, but if F16 is being fixed, the payoff here may exceed all ~14 new sites combined.

### F17 — ~~One interning site uses the process scope instead of the image scope~~ **REJECTED**

Original claim: `baseClassConstraintTypeName` uses the no-`machO` overload of `InternedNodeReferenceCache.shared.reference(interning:)`, landing in a process-scoped store the per-image eviction can never drop, while every other converted site in the PR passes the image.

> **Cross-review — REJECTED; the PR improves this line.** `git log -L 625,635:Sources/SwiftSpecialization/GenericSpecializer.swift` shows commit `b19ac66a` changed it from **bare `NodeReference(interning: typeNode)`** — a fresh independent store per call, the spelling AGENTS.md explicitly forbids — to the shared process-scoped store. Both retention and the `store ===` fast path got *better*, not worse.
>
> The supporting claim was also false: the no-`machO` overload is used at `SwiftDeclaration/Extensions.swift:80/89/100/132/140/160/191` and `SwiftInspection/MetadataReader.swift:713/737`. It is the documented process-keyed scope design, not an oversight at one site.

---

## F18 — `updateConfiguration` is silently a no-op after the first `prepare()` *(found by the cross-review)*

`updateConfiguration` (`SwiftDeclarationIndexer.swift:213–221`) calls `try await prepare()` when `showCImportedTypes` changes, but `prepare()` opens with `if isPrepared { return }` (`:260`) and `isPrepared` is **never reset** once set at `:377` (three sites — `:135`/`:181`/`:259` — and `git show 32bf83c1:` confirms `main` has no reset either). Changing that configuration after the first prepare therefore does nothing, with no error and no event.

Pre-existing on `main`, so not this PR's debt — but it is a public API behaving incorrectly.

Note this is adjacent to, but distinct from, adjudication A8 (`updateConfiguration`'s re-prepare is a no-op because of the `isPrepared` early return — adjudicated "zero call sites, unreachable in RuntimeViewer"). **Check whether A8 already covers this before writing it up**; if it does, this is a duplicate and belongs in the adjudication file, not here.

---

## Verified and dropped

Recorded so later rounds do not re-raise them. Each was checked against the source during the review, not merely triaged:

- `RuntimeFieldLayoutBackend`'s contents/children factory split is **correct** — upstream `d2fd438` made the combination unspellable, so dispatching on payload is the only correct form (this is commit `e06eb3d6` in this branch).
- `Node.create` in the build sweep does not touch the global cache: non-leaf `createInterned` no longer interns.
- `memberSymbolsByGenericSignature`'s bare-`NodeReference` keys are single-store and therefore safe.
- `SymbolTable.row(forName:)`'s comparator is a consistent strict weak ordering, shared with the sort that built the permutation.
- `FixtureImageLock` has no lost-wakeup.
- `lateDemangledNode`'s lock-free demangle window is benign.
- `TypeDefinition.parentContext`'s removal is a documented breaking change, not a defect.

## What has not been done

- **The four questions are answered only where the cross-review answered them.** It ran Q1 (reproduce) and Q2 (baseline) on the findings it overturned, gave Q3 (worth fixing) as a recommendation throughout, and ran Q4 (fixed before) only on F14 and F17. Everything else is still a review claim with a source citation, not an adjudicated defect.
- **No rendering A/B verification** was run on either side. The full test suite was run once by the cross-review: green, 1433 tests / 270 suites.
- Nothing has been fixed, and nothing has been written into `ReviewAdjudications.md` — including the two rejections (F10, F17), which belong there once the four questions are formally recorded.

# PR #97 Code Review Findings

Review date: 2026-07-30
PR: `feature/node-store-migration` → `main` (63 files, +2811/−581)
Review depth: automated multi-agent review at `max` effort, followed by manual re-verification of the mechanism behind the top findings (see [Verification status](#verification-status)).

Status: **Recorded, not yet fixed.**

All file/line references are against `origin/feature/node-store-migration` as of 2026-07-30. References to "upstream" mean the `swift-demangling` package: `origin/main` is the released `0.4.3` line, `origin/feature/node-store` is the branch this PR re-pins onto.

---

## Root cause: the dependency re-pin

Four of the findings below are not independent mistakes. They share one origin: `Package.swift` moves `swift-demangling` from `from: "0.4.3"` to `branch: "feature/node-store"`, and that branch changed four APIs whose misuse produces **no compile error and no warning**:

| Upstream change | `main` (0.4.3) | `feature/node-store` | Finding |
|---|---|---|---|
| `NodePrinterTarget.write(_:context:)` | `context: NodePrintContext?` | `context: @autoclosure () -> NodePrintContext?` | C1 |
| `NodeBuilder.init(_:)` | `node.copy()` (deep) | `node.shallowCopy()` (children shared by instance) | C2 |
| `Node.description` | plain recursive dump | emits `(shared #N)` / `(see #N)` keyed on instance identity | H2 |
| `Node: Codable` | synthesized recursive encoding | flat node-table format, explicitly not backward compatible | M2 |

Three of the four are silent because the protocol supplies a default implementation, because a change of copy semantics turns a dead branch live, or because a debug-description format is being used as a cache key. The adaptation in this PR covered some call sites and missed others. **Any future re-pin of this dependency should be treated as an API audit, not a version bump.**

---

## Verification status

Findings whose mechanism was re-verified directly against the two upstream trees and the PR branch, beyond the automated review:

- **C1** — upstream requirement signature (`NodePrinterTarget.swift:23`), its forwarding default (`:55-57`), the eager implementation on the branch (`Node+.swift:17`), and the two test assertions (`BoundDumpedTypeNameRendererTests.swift:113/119`) were all read directly. Upstream's own doc comment (`NodePrinterTarget.swift:14-22`) documents this exact trap: *"An implementation written against the earlier eager signature does not satisfy this requirement, so the forwarding default below silently takes its place… Nothing warns about this."*
- **C2** — `NodeBuilder.init(_:)` confirmed as `node.copy()` on upstream `main:Node.swift:302` versus `node.shallowCopy()` on `feature/node-store:Node.swift:467`.
- **C3** — both pins read from `Package.swift:215` on each branch.
- **H2** — `(shared #N)` / `(see #N)` confirmed present only on `feature/node-store` (`Node+CustomStringConvertible.swift:84/88`), absent on `main`; `Remangler.maxDepth` confirmed lowered 1024 → 384.
- **H4** — `DemanglingPrinter.print(_:options:)` confirmed to wrap the walk in `StackSafeExecutor.executeWithUncheckedSendability` unconditionally (`NodePrinter.swift:90-95`), with `minimumRemainingStackSize` = 2 MB (`StackSafeExecutor.swift:58`).

Everything else is **as reported by the review and not independently re-verified**. The memory- and cost-shaped findings (H1, H3, L1–L3, M4) are reasoning about ownership and call frequency rather than measurements; they should be confirmed with a profile before any of them is used to justify a large refactor.

The claim in C1 that the test suite is currently red was **not** confirmed by running the suite — it follows from the assertions read at `BoundDumpedTypeNameRendererTests.swift:113/119`, but no build was run on this branch.

---

## Critical

### C1. `SemanticString` silently stops being the `write(_:context:)` witness — every semantic annotation is lost

- **File:** `Sources/SwiftDeclarationRendering/Extensions/Node+.swift:17`
- **Problem:** The implementation is `write(_ content: String, context: NodePrintContext?)` (eager), while the upstream requirement is now `write(_ content: String, context: @autoclosure () -> NodePrintContext?)`. An eager method does not satisfy an `@autoclosure` requirement, so it is not the witness; the protocol extension's forwarding default (`write(content)`, dropping the context) takes over. The sibling hook `pushTypeReferenceScope` on line 6 **was** updated to `@autoclosure`; this one was not.
- **Impact:** Every identifier / module / keyword emitted through `printSemantic` collapses to `.standard`, and `replacingTypeNameOrOtherToTypeDeclaration()` becomes a no-op in six dumpers. The engine dispatches through the witness table at 5 sites plus ~51 inside `SwiftPrinting`'s `extension NodePrintable`. Plain-text output is byte-identical, so snapshot tests cannot see it — but `Tests/SwiftDumpTests/BoundDumpedTypeNameRendererTests.swift:113` (`"Int"` must be `.type(.struct, .name)`) and `:119` (`"TestModule"` must be `.other`) assert exactly the dropped values.
- **Potential fix:** Change the signature to `context: @autoclosure () -> NodePrintContext?` and evaluate it once at the top of the body. Consider adding a compile-time guard so this cannot regress silently — e.g. a test that asserts a non-`.standard` semantic type survives a full `printSemantic` round trip (the two assertions above already serve that role, but only for the dump path).

### C2. Shallow-copy semantics turn a dead `replacingDescendant` into a live rewrite that drops `where`-clause constraints

- **File:** `Sources/SwiftDeclarationRendering/Extensions/OpaqueType+.swift:24`
- **Problem:** `Node.replacingDescendant(_:with:)` matches strictly by instance identity (`if self === old`). Before the re-pin, `NodeBuilder.init(_:)` deep-copied, so `associatedTypeRefNode` — taken from the *original* `sameTypeRequirementNode` tree — could never `===`-match anything inside the copy. `sameTypeRequirementCopy` was therefore structurally identical to `sameTypeRequirementNode`, and the `!usedRequirements.contains(sameTypeRequirementCopy)` test on line 28 was redundant with the test immediately before it. With `shallowCopy()`, the replacement now fires, so the copy really is the variant with `dependentAssociatedTypeRef`'s second child removed — and that variant can be found in `usedRequirements`, excluding a `GenericRequirementDescriptor` that used to be appended to `results`.
- **Impact:** `swift-section dump` / `interface` on a `some P` return type whose same-type requirement carries a two-child associated-type ref loses a `where` constraint it previously printed. No call site, comment, or test was touched, so the behavior change is invisible in the diff.
- **Potential fix:** Decide which behavior is intended. If line 28 was meant to be a real filter, keep it and add a test pinning the rendered `where` clause; if it was always meant to be redundant (the likelier reading, given it was written when it could not fire), delete it and the `replacingDescendant` call.

### C3. Re-pinning `swift-demangling` to a branch makes the package unresolvable for versioned consumers

- **File:** `Package.swift:215`
- **Problem:** `from: "0.4.3"` → `branch: "feature/node-store"`, with `*.resolved` gitignored.
- **Impact:** SwiftPM refuses to resolve a package required *by version* whose own manifest carries a *branch* requirement. Every consumer following `README.md:38` (`from: "0.10.0"`) — RuntimeViewer included — fails to resolve once this merges, and `release.yml` would tag a release nobody can consume. With no committed `Package.resolved`, the `swift package update` that AGENTS.md mandates before every build re-resolves to whatever the upstream tip is, so two builds of the same commit can compile against different `Demangling` sources.
- **Potential fix:** Merge and tag the upstream branch (e.g. `0.5.0`) and pin to that version before this PR merges. This is a merge blocker independent of everything else in this document.

---

## High

### H1. `DemangledSymbol` pins the whole per-image symbol table, so the advertised reclamation never happens

- **File:** `Sources/MachOSymbols/DemangledSymbol.swift:12`
- **Problem:** The type swapped an inline `Symbol` for the whole per-image `[Symbol]` table, and `Node` for a `NodeReference` holding the whole `NodeStore`. `Storage.demangledSymbol(atRow:)` vends `DemangledSymbol(symbolTable: symbolTable, …)`, and those values are retained long-term as `FunctionDefinition.symbol` / `Accessor.symbol` / `VariableDefinition.accessors[].symbol` for every member of every indexed type.
- **Impact:** Index SwiftUI → hold the resulting `TypeDefinition`s (every consumer does) → `removeSubIndexer(indexer)` → sub-indexer deinits → `symbolIndexStore.remove(for: machO)`. Only the `Storage` object drops. The `[Symbol]` buffer (a 32-byte row plus a retained mangled-name `String` per unique Swift symbol) and the `NodeStore` arena stay alive. `SwiftDeclarationIndexer.swift:196` explicitly claims "per-image memory is actually reclaimed".
- **Potential fix:** Either shrink `DemangledSymbol` back to what an escaped value actually needs (the row's own data), or make the retention explicit in the doc comment and drop the reclamation claim. The first is preferable if `TypeDefinition`s are expected to outlive their indexer.

### H2. `instantiationKey`'s remangle-failure fallback keys on `Node.description`, which now encodes instance identity

- **File:** `Sources/SwiftLayout/StaticTypeLayoutResolver.swift:476`
- **Problem:** The fallback key is `qualifiedTypeName + "|" + String(describing: node)`. Upstream's `description` now builds `sharedLabels: [ObjectIdentifier: Int]` and prints `(shared #N)` on the first occurrence of a multiply-referenced instance, `(see #N)` thereafter. Two structurally identical trees therefore render different strings depending only on which subtree instances happen to be shared — and `demangleAsNode` hash-conses through `NodeCache.shared`, so whether the two `Bar` arguments of `Foo<Bar, Bar>` are one instance depends on what the process demangled earlier.
- **Impact:** At `:460-467` this string is both the `memoizationCache` key (misses ⇒ unbounded re-resolution of the same instantiation) and the `inProgressKeys` cycle guard (`guard !inProgressKeys.contains(key)`). A self-embedding instantiation reached through differently-shared instances no longer collides with its own in-progress marker, so `.cyclicLayout` is never raised and the resolver recurses. Upstream also lowered `Remangler.maxDepth` from 1024 to 384, which makes this fallback branch fire more often than before.
- **Potential fix:** Build the fallback key from a structural walk (kind / contents / child arity, preorder) rather than `description`. A debug-description format is not a stable key under any circumstances; the depth-limit change just made the latent problem reachable.

### H3. `removeSubIndexer(_:)` invalidates its cache outside the lock and only at one level

- **File:** `Sources/SwiftIndexing/SwiftDeclarationIndexer.swift:203`
- **Problem:** The lookup and removal are atomic, but `allStorageCache` is reset *after* the lock is released, and only on `self`. The `all*` accessors (`allTypes` at `:881`, ~15 in total) read the memo under `@Mutex`, compute `subIndexers.flatMap { … }` outside any lock, then write back with get-modify-set.
- **Impact:** Interleave: a reader misses and snapshots the list including sub-indexer X → `removeSubIndexer(X)` removes X under the lock, then resets the cache → the reader writes its pre-removal result back. Nothing clears the cache again (only `prepare` / `add` / `remove` do), so X's `TypeDefinition`s keep being vended, and — holding `NodeReference`s and `DemangledSymbol`s — X's `NodeStore` and symbol table stay pinned (compounding H1). Separately, the aggregates memoize per level, so `child.removeSubIndexer(grandchild)` leaves `root.allAllTypeDefinitions` still returning the grandchild's declarations.
- **Potential fix:** Reset the cache inside the same critical section as the removal, and propagate invalidation up the parent chain (or key the aggregates so a child's invalidation is observable from an ancestor).

### H4. Every `printSemantic` call hops to a large-stack thread and blocks on a semaphore

- **File:** `Sources/SwiftDeclarationRendering/Extensions/Node+.swift:78`
- **Problem:** The new entry routes through `DemanglingPrinter<SemanticString, Self>.print`, which wraps the walk in `StackSafeExecutor.executeWithUncheckedSendability` **unconditionally**. That executor requires 2 MB of *remaining* stack (`minimumRemainingStackSize`), measured on the caller's thread, not on the tree's depth. `swift-section dump` / `interface` run dumpers as `async` code on cooperative workers (512 KB), so the check can never pass and every call submits work and `semaphore.wait()`s.
- **Impact:** `DemangleResolver.resolve(for:)` calls `printSemantic` once per rendered member (~20 per-member loops across the dumpers), so a framework dump pays tens of thousands of thread round-trips that the pre-PR inline `NodePrinter<SemanticString>().printRoot` did not. Blocking a cooperative worker on an OS semaphore is also a forward-progress hazard.
- **Doc mismatch:** Lines 65-76 assert that `print(_:options:)` "runs the recursion inline against a stack floor and pays for a worker only for a tree that actually reaches it." No such per-tree budget exists — upstream's own comment at `NodePrinter.swift:87-89` says the opposite ("This is the only public way to run the walk: it routes through `StackSafeExecutor`"). The comment should be corrected regardless of what is done about the cost.
- **Potential fix:** Measure first. If the hop is real on the dump path, either keep a depth-gated inline path for shallow trees or hoist the large-stack hop to the top of the dump (one worker for the whole run, not one per member).

### H5. The forked printer missed upstream's truncation-aware cache guard

- **File:** `Sources/SwiftPrinting/NodePrintables/InterfaceNodePrintable.swift:51`
- **Problem:** This module keeps a hand-copied fork of the upstream printer that memoizes every fragment unconditionally (`printCache[cacheKey] = subTarget`). Upstream's version now tracks `truncationCount` and caches only `if truncationCount == truncationCountBefore`, because a truncated rendering is position-dependent.
- **Impact:** On a symbol with substitution back-references (a SwiftUI `View.Body` typealias is the canonical case), a shared subtree first reached near `maxPrintDepth` (768) renders as `<<too complex>>` and is memoized under its `ObjectIdentifier`; the same interned instance reached later at depth 3 hits the cache, and the truncated fragment is spliced into a shallow position where the full type would have printed.
- **Potential fix:** Port the guard. More durably: record why this fork exists and what it diverges from, so the next upstream printer change has a checklist — this is the second finding in this review caused by a partial port.

---

## Medium

### M1. Two public APIs vend dictionaries whose key equality flipped to store identity

- **Files:** `Sources/MachOSymbols/SymbolIndexStore.swift:747` (`memberSymbols(of:excluding:in:)`), `:802` (`allOpaqueTypeDescriptorSymbols(in:)`)
- **Problem:** Both return `OrderedDictionary<NodeReference, …>`. `NodeReference`'s `Hashable` is `store === store && index == index`, where `Node`'s was structural.
- **Impact:** An external caller could previously subscript these with its own demangled node. Now any lookup node interned elsewhere (`NodeReference(interning:)` mints a fresh private store per call; `demangledNodeReference` falls back to a per-name mini store) hashes and compares distinct, so the subscript returns nil forever. No compile error and no test coverage, because the repo only ever iterates these two dictionaries. Every internal cross-store collection was moved to `StructuralNodeReferenceKey`; these two escape unwrapped. (Same hazard class as the `NodeReference` store-identity trap already known to drop override/vtable comments.)
- **Potential fix:** Wrap the keys in `StructuralNodeReferenceKey` at the public boundary, or return an array of pairs so no caller can form the expectation that lookup works.

### M2. The new hand-written `Codable` claims wire compatibility that upstream removed

- **Files:** `Sources/SwiftDeclaration/Components/Names/TypeName.swift:48`, `ProtocolName.swift:37`, `ExtensionName.swift:54`
- **Problem:** The doc comment says "Wire-compatible with the historical `node: Node` encoding". On 0.4.3, `Node` was `Codable` via the synthesized recursive `Payload` conformance; `feature/node-store` adds `Node+Codable.swift` encoding `{"nodes":[{kind,contents,children:[Int]}…],"root":Int}`, whose own header states that "data encoded by earlier releases does not decode with this version".
- **Impact:** `TypeName.init(from:)` calls `container.decode(Node.self, forKey: .node)`, so any archive written by a pre-PR build throws `DecodingError`, and anything written here cannot be read by a 0.14.0 consumer. Only the outer `{node, kind}` envelope survives. The comment tells the next maintainer no format migration is needed.
- **Potential fix:** Correct the comment to state exactly what is preserved (the envelope) and what is not (the node payload). If any persisted artifact crosses this boundary — check `ABISnapshotDocument`'s `formatVersion` contract — it needs a version bump.

### M3. One cross-store-capable dictionary key was missed by the PR's own rule

- **File:** `Sources/SwiftIndexing/SwiftDeclarationIndexer.swift:736`
- **Problem:** `memberSymbolsByGenericSignature` is still keyed on a bare `NodeReference`, keyed from `memberSymbol.demangledNode.first(of: .dependentGenericSignature)`.
- **Impact:** Today every symbol reaching this loop comes from the single hash-consed image store, so index equality accidentally coincides with structural equality. The moment a symbol is vended from another store — `demangledNodeReference` already falls back to `lateDemangledNode(forName:)`'s mini store for any name outside the build sweep — two members sharing one `where` clause land in two buckets, and the indexer emits two separate `extension … where …` blocks for one constrained extension.
- **Potential fix:** Use `StructuralNodeReferenceKey` here too. Longer term, the fact that this rule has to be applied by hand at every site is itself the problem — see L2.

### M4. `machOFile(by:)` lost its early exit and now scans every image in every sub-cache

- **File:** `Sources/MachOExtensions/DyldCache+.swift:133`
- **Problem:** Rank is `pathShapeRank * 2 + catalystPenalty`, so only a native canonical `<name>.framework` binary can reach `bestMatchRank`; a plain `.dylib` scores 2, a Catalyst dylib 3, a bundle 4. `scanReachedBestMatch` never returns true for those.
- **Impact:** `swift-section --dyld-shared-cache -n libswiftCore` walks `self.machOFiles()`, then `mainCache.machOFiles()`, then `subcache(for:)` + `machOFiles()` for every entry of `mainCache.subCaches`. A current macOS cache lists ~3,600 images across 7+ sub-cache files, and each `MachOFile` construction parses a header and reads `imagePath`. The old `first(where:)` stopped at the first leaf-name hit. `SwiftLayout`'s offline dependency closure resolves cache-resident dependencies by bare name, multiplying this by N.
- **Potential fix:** Give the non-framework path shapes a reachable best rank, or keep the ranked scan but exit as soon as the best *achievable* rank for the query shape is hit.

---

## Low — cost and cleanliness

### L1. `structurallyEquals` replaced an O(1) identity compare on a hot indexing path

- **File:** `Sources/SwiftDeclaration/Components/Definitions/OverrideSymbolMatcher.swift:30`
- **Problem:** Before the change both sides came from `demangleAsNode`, i.e. NodeCache-interned canonical instances, so `classNode == typeNode.first(of: .class)` hit `Node.==`'s `lhs === rhs` fast path in O(1) with no allocation. Now `typeClassNode` is a `Node` from `MetadataReader.demangleContext` while `classNode` is a `NodeReference` into the image store, and `NodeReference.structurallyEquals(_ node: Node)` has no identity short-circuit and — unlike `Node.==`, which defers its memo until 256 pairs — allocates `Set<VisitedPair>()` and inserts from the first pair.
- **Impact:** `TypeDefinition.index` runs this for every method / override / default-override descriptor of every class, over every symbol aliased at the implementation address.
- **Potential fix:** Add an identity/short-circuit fast path to `structurallyEquals`, and defer the visited-set allocation the way `Node.==` does.

### L2. `NodeReference(interning:)` allocates a ~24 KB intern table per name

- **File:** `Sources/SwiftDeclaration/Extensions.swift:46`
- **Problem:** This is the construction path for every `TypeName` / `ProtocolName` at 29 call sites (14 in this file, 6 in `SwiftDeclarationIndexer` at `:410/:415/:428/:478/:481/:575`, 4 in `SwiftSpecialization`, plus the three decoders). `NodeStoreBuilder.init` allocates and zeroes `compactSlots` (4096 × UInt32 = 16 KB) + `manyChildrenSlots` (4 KB) + `textSlots` (4 KB) for a tree of ~10 nodes.
- **Impact:** Beyond the memset cost, it severs hash-consing across names (tens of thousands of separate `Module("SwiftUI")` leaves) and is the structural cause of the cross-store hazard that forced `StructuralNodeReferenceKey` into existence (M1, M3).
- **Potential fix:** One shared arena per image. Structural equality would coincide with index equality again, which removes the hazard class rather than patching it site by site — this is the highest-leverage item in this document even though its direct symptom is only cost.

### L3. The print path re-materializes the whole `Node` tree per declaration

- **File:** `Sources/SwiftPrinting/SwiftDeclarationPrinter.swift:432` (also `:442`, `:452`, `:255`; `+Members.swift:36/:59`; `+DiffRendering.swift:46/:62`; `ClassDumper.swift:90/:92`; `+Headers.swift:142` — 11 of the 18 `materialize()` sites in `Sources/`)
- **Problem:** Every printed declaration calls `.materialize()`, which allocates a `[UInt32: Node]` memo, a `[UInt32]` child-index array per node, and one `Node` per node, all discarded immediately. A generic method's getter is 100+ nodes; an interface dump of SwiftUI prints ~10^5 members.
- **Impact:** Reintroduces on the output side the per-declaration class-tree cost the migration removed on the storage side.
- **Potential fix:** The generic seam already exists (`DemangleResolver.resolve(for: some DemanglingNode)`, `DemanglingPrinter<Target, SomeNode>`); `VariableNodePrinter` / `FunctionNodePrinter` / `SubscriptNodePrinter` / `printThrowingType` / `printType` were left `Node`-only and would need the same generic treatment.

---

## Not itemized

Surfaced by the review but cut below the reporting threshold, recorded here so they are not rediscovered:

- `symbols(for:in:)` rebuilds `Symbol` values on every call.
- `collectModules` allocates a `String` per module node per symbol.
- Three matchers were left on the old materializing `MetadataReader.demangleSymbol` + `OrderedSet<Node>` path.
- `DemangleResolver`'s concrete `Node` overload shadows the new generic one.
- Three near-identical hand-written `Codable` / `Hashable` pairs across the `*Name` types invite divergence.
- `ProjectEvolutionLog.md:348` has a dead link, and §19 is stale.
- New assertions were added under `Tests/IntegrationTests/`, which repo convention says must stay assertion-free — and which `--skip IntegrationTests` never runs anyway.
- Two new tests are vacuous: `buildPipelineStaysOffGlobalNodeCache` asserts a property of `demangleAsNodeTransient` alone (reverting the build sweep to `demangleAsNode` still passes), and `typeInfoLookupMatchesIndexedNames` compares a dictionary value to itself.

---

## Suggested order

1. **C3** first — it is a merge blocker on its own, and pinning a tagged version is the precondition for trusting anything else here.
2. **C1**, **C2**, **H5** — the three silent behavior regressions from the partial API port. C1 also gates the test suite.
3. **H2** — a wrong cache/cycle key is a correctness bug that surfaces as a hang, not a wrong answer.
4. **H1** + **H3** together — same ownership story, and H3 makes H1 worse.
5. Everything else after the branch is green.

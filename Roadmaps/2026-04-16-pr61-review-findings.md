# PR #61 Code Review Findings

Review date: 2026-04-16
PR: `feature/vtable-offset-and-member-ordering` → `main` (81 commits, 190 files, +32574/−1518)

Status: **Recorded, not yet fixed.**

---

## Medium

### M1. `SharedCache` deadlock risk between build closure and memory pressure handler

- **File:** `Sources/MachOCaches/SharedCache.swift:54-65`
- **Problem:** `storage(in:buildUsing:)` runs the caller-supplied `build` closure inside `withLockUnchecked`. The memory pressure handler calls `removeAll()` on the same `@Mutex`-backed dictionary. Since the underlying lock is non-recursive (`os_unfair_lock` / Swift `Mutex`), if memory pressure fires during a build, the handler will attempt to acquire the already-held lock → deadlock.
- **Relation to KNOWN_ISSUES:** The lock contention issue is already documented there. The deadlock risk with the memory pressure handler is an additional concern.
- **Potential fix:** Release the lock before calling `build`, then re-acquire to insert (double-check pattern). Or ensure the memory pressure handler skips acquisition when the lock is already held.

### M2. `MemberAttributeInferrer` is unused in production

- **File:** `Sources/SwiftInterface/AttributeInference/MemberAttributeInferrer.swift`
- **Problem:** This struct is only referenced in `MemberAttributeInferrerTests.swift`. The actual member-level attribute detection is done inline: `@dynamic` in `DefinitionBuilder`, `@objc`/`@nonobjc` in `TypeDefinition.applyThunkAttributes`.
- **Potential fix:** Either integrate `MemberAttributeInferrer` as the single production entry point for member-level attributes (replacing inline checks), or move it to the test target.

### M3. `TypeAttributeInferrer.inferObjCType` is a no-op stub called on every print

- **File:** `Sources/SwiftInterface/AttributeInference/TypeAttributeInferrer.swift:146-158`
- **Problem:** The method extracts the class descriptor, immediately discards it (`_ = classDescriptor`), and the body is all comments. It runs on every type definition during printing.
- **Potential fix:** Remove from the `infer(for:)` call chain until it can produce results. Keep the commented-out investigation notes if desired.

### M4. `SymbolIndexStore` — `offset >= 0` admits offset 0

- **File:** `Sources/MachOSymbols/SymbolIndexStore.swift:225`
- **Problem:** Changed from `offset != 0` to `offset >= 0`. Offset 0 in a Mach-O file points to the header, not executable code. This creates a spurious lookup entry.
- **Potential fix:** Use `offset > 0` instead.

---

## Low

### L1. `OrderedMember.classOrdered` — redundant nil-coalescing

- **File:** `Sources/SwiftInterface/Components/Definitions/OrderedMember.swift:46-51`
- **Problem:** `withVTable` is already filtered to non-nil `minVTableOffset`, but the sort uses `?? 0` which is unreachable. Misleading.
- **Potential fix:** Force-unwrap or use `guard` inside the sort closure.

### L2. `ConcurrentMap` — `nonisolated(unsafe)` lacks safety justification

- **File:** `Sources/Utilities/ConcurrentMap.swift:19,47`
- **Problem:** The pattern is correct (disjoint-index writes from `concurrentPerform`), but no comment explains why the `nonisolated(unsafe)` annotation is safe.
- **Potential fix:** Add a comment documenting the disjoint-index write guarantee.

### L3. `applyThunkAttributes` — all allocators get `@objc` when any init is `@objc`

- **File:** `Sources/SwiftInterface/Components/Definitions/TypeDefinition.swift`
- **Problem:** When a thunk symbol's `memberName` is an init, the attribute is applied to ALL allocators without distinguishing overloads. This is a known limitation of demangled thunk symbols not carrying overload-distinguishing info.
- **Potential fix:** Add a comment explaining the limitation. No code fix possible without richer symbol info.

### L4. Extension offset comment prefix says "field offset"

- **File:** `Sources/SwiftInterface/SwiftInterfacePrinter.swift:250`
- **Problem:** For extensions (neither protocol nor type definition), the offset comment prefix falls through to `"field offset"`, which is incorrect for extensions.
- **Potential fix:** Use a distinct prefix for extensions, or omit the offset for extension definitions.

### L5. `conformingProtocolNames` timing dependency is implicit

- **File:** `Sources/SwiftInterface/SwiftInterfaceIndexer.swift:~510`
- **Problem:** `TypeAttributeInferrer.infer(for:)` is called at print time, after conformances are populated — correct but fragile. Moving `infer` to index time would silently break `@globalActor` detection.
- **Potential fix:** Document the ordering dependency, or move inference to a well-defined post-conformance phase in the indexer.

---

## Nit

### N2. Typo: `currentIdentifer` → `currentIdentifier`

- **File:** `Sources/MachOCaches/SharedCache.swift:67`
- **Note:** Pre-existing, not introduced by this PR.

### N4. Repetitive lookup-dict parameter threading

- **Files:** `DefinitionBuilder`, `TypeDefinition.index`
- **Problem:** Four dictionaries (`methodDescriptorLookup`, `vtableOffsetLookup`, `implOffsetDescriptorLookup`, `implOffsetVTableSlotLookup`) are threaded through every call site.
- **Potential fix:** Group into a `DescriptorLookupContext` struct.

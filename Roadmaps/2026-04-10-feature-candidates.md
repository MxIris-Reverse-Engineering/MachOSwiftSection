# Feature Candidates — 2026-04-10

Draft list of new feature ideas for MachOSwiftSection. Not a commitment — a brainstorming snapshot. Each entry records the motivation, what it uniquely leverages from this project, a rough scope, and the target user.

## Guiding Principle

Focus on capabilities that can only exist *because* this project can read binary ABI details that `.swiftinterface` files do not contain:

- Field offsets, vtable slots, metadata flags, witness table contents
- Dyld shared cache (the only place many private frameworks live)
- Symbols that exist in the binary but are hidden from the shipped `.swiftinterface`

Features already covered by the current codebase (attribute inference for `@propertyWrapper` / `@resultBuilder` / `@dynamicMemberLookup` / actor / retroactive, vtable offsets, member ordering, generic specializer, class hierarchy dump, enum layout, etc.) are intentionally excluded.

---

## A. Binary ABI Compatibility Diff

Compare two versions of the same framework at the **binary ABI** level — not at the source API level.

Reports:
- Field offset changes (even when field names are unchanged)
- VTable slot reordering
- Protocol requirement reordering
- `@frozen` ↔ resilient transitions
- Witness table entry additions / removals
- New or removed conformances

**Unique capability**: `.swiftinterface` diff tools cannot see this information. This project is the only thing that can.

**Target users**: framework authors (CI gate), runtime injection / tweak developers, resilience researchers.

**CI integration**: fits naturally with the `docs/ci-snapshot-testing-design` branch — PRs can automatically fail if ABI is broken.

**Effort**: Medium.

---

## B. Hidden API / SPI Finder

A set-difference between:
1. The interface reconstructed from the binary (via `SwiftInterfaceBuilder`)
2. The official `.swiftinterface` parsed by `TypeIndexing.SwiftInterfaceParser`

Produces a list of everything the framework ships in its binary but hides from its public `.swiftinterface`.

**Unique capability**: both building blocks already exist. This feature is essentially a join.

**Target users**: private-API researchers, security researchers, Apple SPI investigators.

**Effort**: Low. This is the lowest-hanging fruit on the list.

---

## C. Dyld Shared Cache Query Engine

Today the project can iterate a shared cache image-by-image. Promote this into a cross-image query layer backed by a persistent index (e.g. `~/.cache/swift-section`).

Example queries:

```
swift-section query cache 'conformers-of View'
swift-section query cache 'types-with-field-of-type String'
swift-section query cache 'classes-overriding NSObject.dealloc'
swift-section query cache 'propertywrappers'
swift-section query cache 'actors'
swift-section query cache 'frozen-types in SwiftUICore'
```

The query language can start as structured flags and grow toward a `jq`-like expression syntax.

**Unique capability**: no other tool can perform Swift-semantic queries across an entire dyld shared cache.

**Target users**: reverse engineers, security researchers, framework archaeologists.

**Effort**: Medium-large (indexing + query layer + CLI surface).

---

## D. IDA Pro / Ghidra Swift Type Export

Generate type definitions that disassemblers can consume directly:

- IDA `.idc` / `.til` files with Swift struct / class layouts and vtable comments
- Ghidra `.gdt` or DataType scripts
- LLDB `type summary` / `type synthetic` scripts

Result: in IDA, clicking on a Swift object shows real field and method names instead of `qword_xxx`. Combined with the existing `ida-pro-mcp-headless` integration, this closes a useful loop for reverse engineering sessions.

**Target users**: the reverse engineering community (the project's stated audience).

**Effort**: Medium.

---

## E. Protocol Witness Table Content Reconstruction

Commit `eff0f42` already prints PWT *addresses*. The next step is parsing the PWT *contents* and explaining each entry:

```
extension SomeStruct : View {  // PWT @ 0x12345
    // requirement #0: body  ← SomeStruct.body.getter  (0x6789)
    // requirement #1: _viewListCount:inputs:  ← default impl in View  (0xABCD)
    // requirement #2: makeDebugView  ← missing (uses dispatch thunk)
}
```

Gives the complete picture of how Swift protocol dispatch resolves at runtime — especially valuable for closed-source frameworks like SwiftUI.

**Unique capability**: this level of detail is only available by reading the binary; nothing else reconstructs it.

**Target users**: deep Swift runtime researchers, SwiftUI investigators.

**Effort**: Medium.

---

## F. Memory Layout Visualization

The data is already available via `SpareBitAnalyzer`, `EnumLayoutCalculator`, and field offsets. The missing piece is a visual rendering.

Text rendering (terminal):

```
UIEdgeInsets  (32 bytes, align 8)
┌────────┬────────┬────────┬────────┐
│ top    │ left   │ bottom │ right  │   Double × 4
└────────┴────────┴────────┴────────┘
 0        8        16       24

Optional<Bool>  (1 byte)
┌────────┐
│DDDDDDD?│   D = data bits, ? = spare bit for .none
└────────┘
```

Optional SVG output for documentation and blog posts.

**Target users**: Swift learners, debugging sessions, educational content.

**Effort**: Low.

---

## G. Swift Runtime Hook Code Generator

Given a framework and a target (class, method, or protocol requirement), emit ready-to-use injection code:

- VTable slot index
- fishhook-compatible symbol name
- Or a MachOKit runtime patch snippet
- Handles Swift-specific ABI details: indirect return, self register, method descriptor dispatch

**Target users**: tweak authors, runtime injector developers.

**Effort**: Medium.

---

## Comparison Matrix

| Candidate | Unique capability leveraged | Effort | Uniqueness | Target audience |
|---|---|---|---|---|
| A. ABI Diff | Binary offset / vtable / flags | Medium | High | Framework devs, injection devs |
| B. Hidden API Finder | Binary vs `.swiftinterface` set difference | **Low** | Medium | Private API / security researchers |
| C. Shared Cache Query Engine | Full-cache Swift parsing | Medium-large | **Very high** | Reverse engineers, security researchers |
| D. IDA / Ghidra Type Export | Runtime types + vtable | Medium | High | Reverse engineering community |
| E. PWT Content Reconstruction | Binary PWT parsing | Medium | **Very high** | Deep Swift runtime research |
| F. Memory Layout Visualization | SpareBitAnalyzer + layout data | **Low** | Medium | Education, debugging |
| G. Hook Code Generator | VTable + dispatch details | Medium | High | Tweak / injection developers |

## Shortlist

Based on uniqueness vs. cost:

1. **B — Hidden API Finder** (lowest-hanging fruit, reuses existing infrastructure)
2. **C — Shared Cache Query Engine** (capability no other tool can offer)
3. **E — PWT Content Reconstruction** (pairs well with recent PWT-address work)
4. **A — ABI Diff** (the "hardcore" version of SDK diff)

## Status

Not yet scoped. Awaiting user selection of which candidate(s) to promote to a design spec and implementation plan.

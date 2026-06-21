# Diffable Interface — Implementation Plan

> Status: IMPLEMENTED (first full increment). The annotated full-interface diff
> renders end-to-end via `swift-section diff --interface`, validated on
> SwiftUICore (macOS 15.5↔26.0 caches, ~45s, ~68k lines). Remaining items are
> refinements, listed under "Deferred / known gaps".
> Build/test require `USING_LOCAL_DEPENDENCIES=1` (model Codable needs the local
> swift-demangling's Codable `Node`).

## What shipped (this increment)

- **`SwiftPrinting/SwiftDeclarationPrinter+Members.swift`** — per-member render
  primitives returning one member as a standalone `SemanticString`:
  `printField` (stored field, from the model `FieldDefinition` + `FieldFlags`;
  `TypeNodePrinter` auto-strips the `.weak`/`.unowned` reference-storage prefix),
  `printEnumCase` (payload presence decided on the *rendered* payload string, so
  empty cases print bare `case name`), `printDeinit`, `printAssociatedType`, plus
  header-only `printTypeHeader` / `printProtocolHeader`. The symbol-backed members
  reuse the pre-existing `printVariable`/`printFunction`/`printSubscript`.
- **`SwiftPrinting/SwiftDeclarationPrinter.swift`** — extracted `printExtensionHeader`
  from `printExtensionDefinition` (behavior-preserving; the definition printer
  calls it, so one source of truth). Covered by the passing `SwiftInterfaceTests`
  (`outputContainsRetroactiveAnnotation`, `…ConditionalConformanceWhereClause`).
- **`SwiftInterface/DiffMarking.swift`** — `DiffMarker` + `markLines`: prefixes
  every line of a rendered unit with `+`/`-`/` ` at column 0, then the level
  indent; multi-line safe; empty in → empty out. Unit-tested
  (`Tests/SwiftInterfaceTests/DiffMarkingTests.swift`, 5 tests).
- **`SwiftInterface/SwiftDiffableInterfaceRenderer.swift`** — the renderer. Holds
  two prepared `SwiftDiffableInterfaceBuilder`s + a `SwiftDeclarationPrinter` per
  binary. `printAnnotatedInterface()` walks globals → types → protocols →
  extension buckets, matches containers on `ABIKey.makeUnwrappingType`, diffs each
  member category with the same keying as `ABIDiffer`, and assembles header +
  inline-marked members + brace. Modified members show `-old`/`+new`; a `.modified`
  whose rendered old == new collapses to a single context line (the payload key —
  a remangle — can differ while the printed signature is byte-identical; the
  change-list keeps the precise record). Header changes on a surviving container
  show `-oldHeader`/`+newHeader`.
- **`SwiftDiffing/ABIDiffer.swift`** — exposed `public static extensionBucketKey(for:)`
  so the renderer matches extension buckets with the differ's exact key.
- **`swift-section diff --interface`** — emits the annotated interface; plain text
  to `-o`, or per-line green/red colorized to the terminal.

## Deferred / known gaps (next increments)

- Extensions render at the **bucket level** (`extension <Target> {` + merged
  members), matching `ABIDiffer`'s bucket-merge. No per-conformance `: Protocol`
  header / `where` block on the annotated extension yet (same TODO(P2) as the
  differ's per-conformance attribution).
- Protocol **default-implementation extensions** and type **specialized children**
  are not yet walked by the renderer.
- **Constructors** are intentionally not emitted (mirrors `printMembersByCategory`,
  which prints `allocators` only); the change-list still reports them.
- Removed members are appended at their category's end (not interleaved by old
  position). Top-level decls are blank-line separated; separator lines are
  unmarked.
- Future: access-level *split* (public/package/private interfaces). Still NO
  filtering — full surface, discriminators kept.

## Goal (corrected)

`SwiftDiffableInterfaceBuilder` should produce a **full Swift interface with
inline `+`/`-` annotations** — i.e. render the new binary's interface (exactly
like `SwiftInterfaceBuilder.printRoot()`), with git-diff-style markers showing
what was added / removed / modified relative to the old binary. It is NOT a
bare change-list (the current `ABIDiffReporter` is the secondary/summary output).

**Surface = FULL.** Include public **and** package/internal/private declarations
(the existing interface generation is full). Do NOT filter to public.

**Access level is a FUTURE SPLIT dimension, not a filter.** Later the output can
be split into `public.swiftinterface` / `package.swiftinterface` /
`private.swiftinterface`. So per-declaration access *category* may be captured
as metadata, but nothing is dropped now.

- The private discriminator `(X in _HEX)` is `private`/`fileprivate`'s mangling
  (hash of the source file name, brute-forceable back to the file). KEEP it —
  it is valuable; never strip/normalize it.

## What is already built (do not redo)

- **SwiftDiffing module** (peer over SwiftDeclaration; deps SwiftDeclaration +
  Demangling + OrderedCollections; Mach-O-free):
  - `ABIKey` — identity = remangle the demangled `Node` (`mangleAsString`), with
    a `.printed(node.print(using: .default))` fallback. (Print options were
    switched to `.default` for max info; container names use
    `name(using: .default)`.)
  - `ABIDiff` (8 buckets: types/protocols/4 extension kinds/globalVars/
    globalFuncs), `ContainerChange`, `MemberChange`, `ChangeStatus`,
    `ContainerKind`, `MemberKind` — all `Codable + Equatable`.
  - `ABISnapshot` / `ContainerSnapshot` / `MemberRecord` — `Codable` frozen diff
    currency.
  - `ABIDiffer` — `snapshot(of: ABIModule) -> ABISnapshot` (freeze, the only
    place with model knowledge), `diff(old:new:)` on ABISnapshot (pure) and on
    ABIModule (= freeze both, diff). Reuses `threeWayMatch`/`diffMembers`/
    `sorted`/`keyed`. Extensions diffed per `ExtensionName` bucket (members
    merged).
  - `ABIDiffReporter` — `+`/`-`/`~` text change-list (summary output).
  - `Compatibility` — `breaking`/`additive`, `ABIDiff.hasBreakingChange` /
    `.isBackwardCompatible`.
  - 33 unit tests pass (`Tests/SwiftDiffingTests/`).
- **`SwiftDiffableInterfaceBuilder<MachO>`** (in `Sources/SwiftInterface/`):
  per-binary — `prepare()` indexes AND fully `index(in:)`-es every definition
  (members are lazy otherwise); `abiModule()` (1:1 passthrough of the indexer's
  10 buckets); `snapshot()`.
- **`swift-section diff` CLI** (`Sources/swift-section/Commands/DiffCommand.swift`):
  two file paths (thin/fat, arm64 slice) OR `--dyld-shared-cache -n SwiftUICore`
  two caches. Outputs `ABIDiffReporter` text + breaking verdict.
- Validated end-to-end on SwiftUICore: iOS 18.6 vs 26.5 (standalone, 88s) and
  macOS 15.5 vs 26.0 (dyld cache, 42s).

## Known findings (context for the work)

- Keying churn: a decl that is `private` in old and promoted (→internal/public)
  in new keys differently (`(X in _HEX)` vs clean) → shows as remove+add. With
  FULL surface this stays; it is a *real* access change, honest to show.
  (Future refinement: detect "access changed" by matching modulo discriminator.)
- `(unknown context at _HEX)` = parent-chain resolution failed (cross-module ref
  into Foundation when loading a standalone dylib). Loading from a dyld cache
  (where Foundation is present) fixes it. So prefer cache inputs for real runs.
- Access-level detection (for the FUTURE split, not now):
  - private/fileprivate: exact — `node.first(of: .privateDeclName, .localDeclName) != nil`.
  - public(+@usableFromInline): proxy = the decl's descriptor/metadata symbol is
    in `machO.exportedSymbols` (nlist `N_EXT`). `SymbolIndexStore` already has
    `isExternal`/`exportedSymbols`.
  - internal vs package: not separable from this data.

## New work: `printAnnotatedInterface`

Add to `SwiftDiffableInterfaceBuilder` (or a sibling renderer in SwiftInterface,
which already depends on SwiftIndexing + SwiftPrinting + SwiftDiffing):

```
printAnnotatedInterface(old: SwiftDiffableInterfaceBuilder, new: …) -> SemanticString
```

Flow:
1. Both sides `prepare()`d (index + full member index).
2. `ABIDiffer().diff(old.abiModule(), new.abiModule())` → `ABIDiff` (per
   container/member status, keyed by `ABIKey`).
3. Render a FULL interface, annotated:
   - Iterate the declaration set = NEW's declarations ∪ OLD-only declarations.
   - Per declaration, render via `SwiftDeclarationPrinter`, then mark:
     - added (only in new) → `+` whole block.
     - removed (only in old) → render from OLD, `-` whole block.
     - unchanged → ` ` (verbatim).
     - modified → render NEW; inside, member-level `+` for added members and
       `-` for removed members (removed members rendered from OLD).
4. Output a `SemanticString` like `SwiftInterfaceBuilder.printRoot()`, plus the
   `+`/`-` annotation channel.

### Decisions (CONFIRMED)
1. Granularity: **line-level** — prefix every line, git-style.
2. Modified containers: **inline member-level `+`/`-`** — one block, added &
   removed members interleaved in place (NOT old-block/new-block hunks).
3. **The printer WILL be refactored to support per-member inline rendering**
   (user approved). See the rendering-path note below.

### Rendering paths — what must be refactored for inline per-member `+`/`-`
`SwiftDeclarationPrinter.printTypeDefinition` (SwiftPrinting) renders a WHOLE
type by composing several sources; member rendering is SPLIT across two modules:
- `dumper.declaration` (**SwiftDump** — the per-kind dumpers Struct/Class/Enum…):
  the type header.
- `dumper.fields` (**SwiftDump**): the **stored variables / stored fields**.
  ⚠️ This is the user's key point — stored-variable declarations are emitted by
  SwiftDump, so per-member inline annotation MUST hook the dumper's field
  emission, not just the SwiftPrinting node printers.
- `printDefinition(typeDefinition)` (**SwiftPrinting** — node printers): the
  methods / computed vars / subscripts / inits (symbol-backed members).

So the refactor spans BOTH modules: each must be able to emit members
**one at a time with a per-member annotation hook** (e.g. a callback / a
`SemanticString` segment tagged with its `ABIKey` + status), so the renderer
can prefix each member's line(s) with `+`/`-`/` `. To render REMOVED members
(present only in old), the renderer pulls them from the OLD binary's
`*Definition` and emits them with `-`; the renderer holds both binaries' models
and the `ABIDiff` (which gives each member's `ABIKey` + status). Need to design
the per-member emission seam in SwiftDump's dumpers and SwiftPrinting's
`printDefinition` (a member-keyed emit, so a line maps back to its `ABIKey`).

### Open implementation detail
- Ordering when interleaving NEW + OLD-only declarations (and added/removed
  members within a modified type) into one readable file. Use the printer's
  existing ordering for present-side members; insert removed (old-only) members
  at a stable position (e.g. by their old order, or grouped).

## Build order

1. ~~Confirm granularity decisions~~ — DONE: line-level, inline member-level,
   printer refactor approved.
2. ~~Per-member emission seam~~ — DONE, but **simpler than first planned**: stored
   fields are rendered from the **model** (`FieldDefinition` + `FieldFlags`) in a
   new SwiftPrinting `printField`, NOT by threading a callback through SwiftDump's
   `dumper.fields`. That keeps the heavily-tested SwiftDump dumpers untouched while
   still giving the renderer a per-field unit. Enum cases / deinit / associated
   types got the same model-based per-member primitives; vars/funcs/subscripts
   reuse the existing per-member printer methods.
3. ~~Implement `printAnnotatedInterface`~~ — DONE as
   `SwiftDiffableInterfaceRenderer.printAnnotatedInterface()`.
4. ~~Wire `swift-section diff --interface`~~ — DONE.
5. (Future, separate) per-decl access category + split into public/package/
   private interfaces. Capture access via the signals above; do NOT filter now.

## Build/test cadence (each step)

```bash
USING_LOCAL_DEPENDENCIES=1 swift build 2>&1 | xcsift
USING_LOCAL_DEPENDENCIES=1 MACHO_SWIFT_SECTION_SILENT_TEST=1 swift test --filter SwiftDiffingTests --skip IntegrationTests
```
The SwiftDump refactor must not regress the existing `interface`/`dump` output —
run `SwiftPrintingTests` / `SwiftInterfaceTests` / `SwiftDumpTests` too.

## How to run (current diff)

```bash
USING_LOCAL_DEPENDENCIES=1 swift build -c release --product swift-section
# files:
.build/release/swift-section diff --architecture arm64 <old> <new> -o out.txt
# dyld caches:
.build/release/swift-section diff --dyld-shared-cache -n SwiftUICore <oldCache> <newCache> -o out.txt
```

SwiftUICore binaries used:
- iOS 18.6: `/Library/Developer/CoreSimulator/Volumes/iOS_22G86/.../iOS 18.6.simruntime/.../SwiftUICore.framework/SwiftUICore` (fat)
- iOS 26.5: `/Library/Developer/CoreSimulator/Volumes/iOS_23F77/.../iOS 26.5.simruntime/.../SwiftUICore.framework/SwiftUICore` (thin arm64)
- macOS caches: `/Volumes/Code/Dump/DyldSharedCaches/macOS/{15.5,26.0}/dyld_shared_cache_arm64e`

## Uncommitted state

All of this session's SwiftDiffing work + `SwiftDiffableInterfaceBuilder` + the
`diff` CLI command + the `.default` print change are UNCOMMITTED on branch
`feature/swift-diffing`. (Last commit: `be79e15`.)

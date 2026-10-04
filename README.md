# MachOSwiftSection

A Swift library that recovers Swift metadata — types, protocols, conformances, field layouts — from Mach-O files and dyld shared caches without loading them into a process. It carries its own demangler, symbolic references included, and reimplements the Swift runtime's own reading logic.

On top of that model it generates complete Swift interfaces, diffs a module's ABI between two builds or tracks it across many versions, and computes field offsets and enum layouts statically. The companion `swift-section` CLI exposes all of it, and covers the Objective-C side of a binary as well.

> [!NOTE]
> This library is developed as an extension of [MachOKit](https://github.com/p-x9/MachOKit) for Swift

## Requirements

- Swift 6.2+
- Xcode 26.0+
- macOS 10.15+ / iOS 13+ / tvOS 13+ / watchOS 6+ / visionOS 1+

## MachOSwiftSection Library

### Roadmap

- [x] Protocol Descriptors
- [x] Protocol Conformance Descriptors
- [x] Type Context Descriptors
- [x] Associated Type Descriptors
- [x] Method Symbol For Dyld Caches
- [x] Builtin Type Descriptors
- [x] Swift Interface Support
- [x] Runtime Metadata Inspection (`SwiftInspection`)
- [x] Type Member Layout (`SwiftLayout`, computed statically — `MachOFile` included)

### Swift Package Manager

Add the package to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/MxIris-Reverse-Engineering/MachOSwiftSection", from: "0.21.0"),
],
targets: [
    .target(
        name: "YourTarget",
        dependencies: [
            .product(name: "MachOSwiftSection", package: "MachOSwiftSection"),
            // Optional higher-level products:
            .product(name: "MachOFoundation", package: "MachOSwiftSection"),
            .product(name: "SwiftInspection", package: "MachOSwiftSection"),
            .product(name: "SwiftDump", package: "MachOSwiftSection"),
            .product(name: "SwiftInterface", package: "MachOSwiftSection"),
        ]
    ),
]
```

Declare every product whose module you import. In particular, `MachOSwiftSection` no longer re-exports the symbol index (since 0.19.0): a file that uses `SymbolIndexStore`, `DemangledSymbol` or `DependencyClosure` needs `import MachOFoundation` **and** the `MachOFoundation` product on its target.

**The ABI model and the Mach-O layer**

| Product | Purpose |
| --- | --- |
| `MachOSwiftSection` | The ABI model: the `__swift5_*` sections, every descriptor in them, and the wrappers built from them (`Struct`, `Enum`, `Class`, `Protocol`, `ProtocolConformance`, …). Depends on `MachOBase` only — no symbol index, no demangler. |
| `MachOBase` | Reading, address resolution and relative pointers — everything the ABI model sees. Re-exported by `MachOSwiftSection`. |
| `MachOFoundation` | `MachOBase` plus the symbol index, demangling, and dependency resolution. |
| `MachODependencies` | Resolves the images a binary links, in process or from files and dyld shared caches. |

**Analysis**

| Product | Purpose |
| --- | --- |
| `SwiftInspection` | Symbol attribution and runtime metadata analysis — `SymbolicDemangler` (formerly `MetadataReader`), `EnumLayoutCalculator`, `ClassHierarchyDumper`. |
| `SwiftLayout` | The static layout engine: field offsets, type layouts and enum layouts computed offline, the way the runtime computes them at load time. |
| `SwiftThunkAnalysis` | Reads a type stored behind a metadata accessor thunk (availability-conditional opaque types, noncopyable fields) by evaluating its ARM64 code instead of running it, and ties a class's ObjC method table to its Swift members. |
| `SwiftSpecialization` | Runtime specialization of generic types (`GenericSpecializer`). |
| `TypeIndexing` | Attributes `__C` types to their real module (`__C.NSString` → `Foundation.NSString`) through SDK module interfaces and APINotes. macOS only. |

**Declarations and output**

| Product | Purpose |
| --- | --- |
| `SwiftDump` | `dump(using:in:)` on the ABI wrappers — what `swift-section dump` prints. |
| `SwiftInterface` | End-to-end interface generation: a single version, a two-version diff, or an N-version evolution. |
| `SwiftDiffing` | ABI comparison over the indexed model, with no Mach-O needed: `ABIDiffer`, `ABIEvolution`, `ABISnapshot`. |
| `SwiftDeclaration` | The declaration model shared by indexing, printing and diffing. |
| `SwiftIndexing` | Builds the declaration model from an image. |
| `SwiftPrinting` | Renders the declaration model as Swift source. |
| `SwiftAttributeInference` | Infers source-level attributes (`@propertyWrapper`, `@resultBuilder`, `@dynamicMemberLookup`, `@objc`, …). |
| `SwiftDeclarationRendering` | The comment rendering shared by dump and interface (field layouts, opaque types, specialized metadata). |
| `SwiftOutputTransformer` | Token templates for the layout comments, shared with RuntimeViewer's settings UI. |

**The command-line tool as a library**

| Product | Purpose |
| --- | --- |
| `SwiftSectionKit` | Everything `swift-section` does, one request type per subcommand (`DumpRequest`, `InterfaceRequest`, `ABIDiffRequest`, `ObjCDumpRequest`, …), with the product and diagnostics delivered to an output you supply. The `swift-section` executable is a thin wrapper around it. |

### Usage

#### Basic

Swift information from a `MachOFile` or `MachOImage` is reached through its `swift` property.

```swift
import MachOKit
import MachOSwiftSection

let machO: MachOFile // or MachOImage

// Types
for typeContextDescriptor in try machO.swift.typeContextDescriptors {
    switch typeContextDescriptor {
    case .enum(let enumDescriptor):
        let enumType = try Enum(descriptor: enumDescriptor, in: machO)
    case .struct(let structDescriptor):
        let structType = try Struct(descriptor: structDescriptor, in: machO)
    case .class(let classDescriptor):
        let classType = try Class(descriptor: classDescriptor, in: machO)
    }
}

// Protocols
for protocolDescriptor in try machO.swift.protocolDescriptors {
    let protocolType = try Protocol(descriptor: protocolDescriptor, in: machO)
}

// Protocol conformances
for protocolConformanceDescriptor in try machO.swift.protocolConformanceDescriptors {
    let protocolConformance = try ProtocolConformance(descriptor: protocolConformanceDescriptor, in: machO)
}
```

`machO.swift.types`, `.protocols`, `.protocolConformances`, `.associatedTypes` and `.builtinTypes` build the same wrappers in one step. `SwiftDump` renders any of them as text:

```swift
import SwiftDump

let text = try await structType.dump(using: .demangleOptions(.default), in: machO).string
```

#### Generate Complete Swift Interface

For generating complete Swift interface files, you can use the `SwiftInterface` library which provides a more comprehensive interface generation capability.

```swift
import MachOKit
import SwiftInterface

let builder = try SwiftInterfaceBuilder(configuration: .init(), eventHandlers: [], in: machO)
try await builder.prepare()
let interface = try await builder.printRoot().string
```

Generated interfaces reflect a wide range of Swift language features:

- Type / member attributes: `@objc`, `@nonobjc`, `dynamic`, `@retroactive`, `@globalActor`, `@escaping`, `consuming` / `borrowing` parameter modifiers
- `@objc`, `override` and `@objc(selector)` recovered from a class's ObjC method table, including in OS frameworks that strip the thunk symbols these used to be read from
- `@objc(Name)` on a class its source renamed for the Objective-C runtime (`@_objcRuntimeName(Name)` on a native Swift class), read from the class metadata — AppKit alone renames dozens (`NSScrollPocket`, `NSColorModel`)
- `@objc @implementation extension` for classes implemented through SE-0436, with their stored properties
- Property wrappers as the source declared them (`@SwiftUI.State var name`), with the synthesized `_name` / `$name` hidden — for wrappers defined in other images too
- Types stored behind a metadata accessor — availability-conditional `some View`, noncopyable fields — read without running any code, with their availability branches as a comment
- `distributed actor` declarations and `distributed func` members
- `deinit` for classes and noncopyable types
- VTable offset comments alongside class members, ordered to match the on-disk layout
- Expanded field offsets for nested struct fields, rendered as a tree
- Inverted protocols (`~Copyable`, `~Escapable`) on types and generic requirements

#### Inspect Runtime Metadata

`SwiftInspection` exposes higher-level inspection utilities built on top of `MachOSwiftSection`:

- `EnumLayoutCalculator` — compute the on-disk layout of Swift enums, including single-payload and multi-payload (tagged and untagged) cases. Mirrors the ABI rules in `swift/ABI/Enum.h`.
- `ClassHierarchyDumper` — walk a class's inheritance chain across Swift/ObjC boundaries (requires `@_spi(Internals) import SwiftInspection`, `MachOImage` only).
- `SymbolicDemangler` — demangle types, symbols, context descriptors, and build generic signatures against a Mach-O (requires `@_spi(Internals) import SwiftInspection`). Named `MetadataReader` before 0.20.0; the old name remains as a deprecated alias for one release.

#### Run a swift-section Command from Code

`SwiftSectionKit` runs any `swift-section` subcommand in process and hands its output to you, piece by piece. A request produces what the matching command line prints.

```swift
import SwiftSectionKit

struct PrintingOutput: SwiftSectionOutput {
    func write(_ product: SwiftSectionProduct) {
        if case .text(let line) = product {
            print(line)
        }
    }

    func report(_ diagnostic: SwiftSectionDiagnostic) {}
}

let outcome = try await ABIDiffRequest(
    old: .path("Old.framework/Old"),
    new: .path("New.framework/New"),
    report: .summary
).run(
    output: PrintingOutput(),
    environment: SwiftSectionEnvironment(generator: GeneratorIdentity(name: "MyTool", version: "1.0"))
)
// outcome.hasBreakingChange tells a CI gate whether the ABI broke.
```

The output contract — concurrent calls, three separate channels, a newline after every product piece, and the kind and name `dump` and `objc dump` attach to each declaration they hand over — is described in [SwiftSectionKit.md](Documentations/SwiftSectionKit.md).

## swift-section CLI Tool

### Installation

You can get the swift-section CLI tool in three ways:

- **GitHub Releases**: Download from [GitHub releases](https://github.com/MxIris-Reverse-Engineering/MachOSwiftSection/releases)
- **Homebrew**: Install via `brew install swift-section`
- **Build from Source**: Build with `./build-executable-product.sh` (requires Xcode 26.0 / Swift 6.2+ toolchain), or build and install in one step with `./install.sh [install-directory]` (defaults to `/usr/local/bin`, using `sudo` only when that directory is not writable)

### Usage

The swift-section CLI tool provides seven subcommands: `dump`, `interface`, `diff`, `snapshot`, `evolution`, `transformer`, and `objc` — the Objective-C side, with five subcommands of its own.

> [!IMPORTANT]
> As of 0.10.0, when the input is a fat / universal binary you must pass `--architecture <arch>`. The tool no longer picks a default slice silently.

#### dump - Dump Swift Information

Dump Swift information from a Mach-O file or dyld shared cache.

```bash
swift-section dump [options] [file-path]
```

**Basic usage:**
```bash
# Dump all Swift information from a Mach-O file
swift-section dump /path/to/binary

# Dump only types and protocols. `--sections` takes space-separated values up to
# the next option, so the file path must come before it (or the list must be
# terminated with `--`).
swift-section dump /path/to/binary --sections types protocols

# Only the classes implemented through `@objc @implementation` (SE-0436), with
# their ivars and ObjC method lists. Every class dump (this section and `types`)
# also names the class's ObjC ancestors and marks each member tied to an ObjC
# method with its selector: `overrides -[NSView layout]`, `@objc -[Class selector]`,
# or `explicit selector` where the source spelled `@objc(name)`.
swift-section dump /path/to/binary --sections objcImplementationClasses

# Save output to file
swift-section dump --output-path output.txt /path/to/binary

# Use specific architecture (required for fat binaries)
swift-section dump --architecture arm64 /path/to/binary
```

**Static memory-layout comments (computed offline, no process loaded):**
```bash
# Field offsets for struct/class stored properties
swift-section dump --emit-field-offsets /path/to/binary

# Field offsets + per-field type layout (size / stride / alignment)
swift-section dump --emit-field-offsets --emit-type-layout /path/to/binary

# Expand nested struct fields with their absolute offsets
swift-section dump --emit-expanded-field-offsets /path/to/binary

# Enum layout (strategy / per-case / spare bits)
swift-section dump --emit-enum-layout /path/to/binary

# Enum layout with a different comment style — detailed (default), explained
# (bit ranges in plain words), standard (no per-byte lines), inline (one line
# per case with the byte summary), or compact
swift-section dump --enum-layout-style explained /path/to/binary
```

**Header and export-status annotations:**
```bash
# Leading header block: generator, image path, UUID, architecture,
# library-evolution detection (dispatch-thunk count), and a short digest of
# facts the binary provably cannot recover (IUO spelling, @available, …)
swift-section dump --emit-header /path/to/binary

# Annotate member-symbol lines whose symbol (including its Tj/Tq/Tu derived
# forms) has no export-trie entry — a symbol-table fact, not an access-level
# guess. Override implementation symbols and @objc members are exempt (they
# are reachable through the parent's dispatch thunk / objc_msgSend without
# any exported symbol of their own). Nothing is emitted when the image
# carries no export information.
swift-section dump --emit-export-status /path/to/binary
```

**Addresses and ordering:**
```bash
# The address of each member's symbol
swift-section dump --emit-member-addresses /path/to/binary

# The vtable slot offset of each class method
swift-section dump --emit-vtable-offsets /path/to/binary

# The protocol witness table (PWT) address of each conformance
swift-section dump --emit-pwt-addresses /path/to/binary

# Types and protocols in the order the binary stores them, instead of by kind
swift-section dump --preferred-binary-order /path/to/binary
```

The field-offset, type-layout, enum-layout, member-address and vtable-offset
comments can also be reformatted with your own template — see
[transformer](#transformer---customize-comment-formats). Passing a template
option implies the matching `--emit-…` flag.

These offsets are computed statically by the `SwiftLayout` engine — no runtime,
no metadata accessor, no loading the binary into a process — so they work on any
on-disk Mach-O file (including resilient classes and cross-module field types,
resolved through the dependency closure over the dyld shared cache, as well as
value-generic and parameter-pack instantiations such as `InlineArray<5, Int8>`
or `Variadic<Int, String>` fields). The
`interface` command's `--emit-offset-comments` / `--emit-expanded-field-offsets`
flags use the same static engine.

**Working with dyld shared cache:**
```bash
# Dump from system dyld shared cache
swift-section dump --uses-system-dyld-shared-cache --cache-image-name SwiftUICore

# Dump from specific dyld shared cache
swift-section dump --dyld-shared-cache --cache-image-path /path/to/cache /path/to/dyld_shared_cache
```

**Types read out of other images' metadata accessors:** an availability-conditional
opaque result type (SE-0360) and a noncopyable field type are stored as a pointer
to a metadata accessor thunk, which `dump` and `interface` read without executing
it. A binary that is not in a dyld cache — an app, an embedded framework, an
iOS 26 or earlier simulator runtime's framework — calls the accessors it needs in
other images by name, so those images must be findable. By default they are
looked for where the binary sits (a simulator runtime's `RuntimeRoot`, or its own
`dyld_sim_shared_cache` from iOS 27 on) and then in the running system's cache;
pass `--dependency-search-path` (repeatable) when neither applies, for example a
simulator app whose runtime is not an ancestor of the app. The same paths let the
interface recognize a property wrapper defined in another image (`@State`,
`@EnvironmentObject`, …), so a wrapped property prints as the source declared it —
`@SwiftUI.State var name: Swift.String` — instead of its `_name` storage, and let
both `dump` and `interface` follow a class's ObjC ancestors into the images that
define them (a standalone file's superclass is a bind), which is where the
`override` of an ObjC-inherited member and the explicit-selector verdict come from.
Images of another platform in the running system's cache are never candidates, so an
iOS binary on a macOS host needs its simulator runtime named here:
```bash
swift-section dump --dependency-search-path "/Library/Developer/CoreSimulator/Volumes/iOS_24A434/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS 27.0.simruntime/Contents/Resources/RuntimeRoot/System/Library/Caches/com.apple.dyld/dyld_sim_shared_cache_arm64" /path/to/MyApp.app/MyApp
```
A directory is used as a system root under which absolute install names resolve,
a `dyld_shared_cache_*` / `dyld_sim_shared_cache_*` file as a cache, anything else
as a Mach-O file. `interface` and `snapshot` take the same option. The same paths
also feed the static field-offset / type-layout comments, ahead of the running
system's cache, so a binary can be laid out against the OS version whose cache you
name rather than the host's.

Dump output includes richer annotations:

- Protocol witness table (PWT) entries are annotated with the requirement they satisfy
- Inverted protocol constraints (`~Copyable`, `~Escapable`) are rendered on types and generic requirements
- Protocol conformances can include the PWT address (`--emit-pwt-addresses`)

#### interface - Generate Swift Interface

Generate a complete Swift interface file from a Mach-O file, similar to Swift's generated interfaces.

```bash
swift-section interface [options] [file-path]
```

**Basic usage:**

```bash
# Generate Swift interface from a Mach-O file
swift-section interface /path/to/binary

# Save interface to file
swift-section interface --output-path interface.swiftinterface /path/to/binary

# Use specific architecture (required for fat binaries)
swift-section interface --architecture arm64 /path/to/binary
```

**Static memory-layout comments:**

```bash
# Field offsets (and PWT offsets) on the generated interface
swift-section interface --emit-offset-comments /path/to/binary

# Per-field type layout (size / stride / alignment) and enum layout
swift-section interface --emit-type-layout --emit-enum-layout /path/to/binary

# Member addresses and vtable slot offsets
swift-section interface --emit-member-addresses --emit-vtable-offsets /path/to/binary

# Members sorted by their binary layout offset instead of grouped by kind
# (either way, a class's vtable members come first, in vtable slot order)
swift-section interface --sort-members-by-offset /path/to/binary
```

These use the same static `SwiftLayout` engine as `dump`, and accept the same
comment-template options — see
[transformer](#transformer---customize-comment-formats).

**Objective-C members:** `@objc`, the `override` of an ObjC-inherited member, and
`@objc(selector)` are recovered from each class's ObjC method table and printed by
default — Swift metadata carries none of them, and OS frameworks strip the thunk
symbols that used to be the only evidence. One case stays opt-in: an override
whose body the optimizer inlined into its thunk (`viewDidHide`,
`encodeWithCoder:` in an OS framework) ties to no Swift symbol, and can only be
matched to a member by its selector's name. `dump` always shows such ties, marked
`(selector name, no symbol evidence)`; `interface` marks them `override` only
when asked. It can add `override`, never `@objc(name)` — a method no ancestor
implements is left alone.

```bash
swift-section interface --infer-objc-overrides /path/to/binary
```

**C-imported types and opaque result types:**

```bash
# Include the imported C types in the generated interface
swift-section interface --show-c-imported-types /path/to/binary

# Attribute `__C` types to their real modules (`__C.NSString` → `Foundation.NSString`)
# by indexing the SDK modules the binary links. macOS only and requires Xcode;
# the first run per SDK is slow, later runs reuse the cached extraction.
swift-section interface --resolve-c-module-names /path/to/binary

# Frameworks with no SDK module (AttributeGraph, …) take user-provided APINotes
swift-section interface --resolve-c-module-names --supplementary-apinotes AttributeGraph.apinotes /path/to/binary

# Experimental: spell opaque result types (`some View`) from their opaque type
# descriptors; complex return types may fail to parse
swift-section interface --parse-opaque-return-type /path/to/binary
```

Writing supplementary APINotes is covered in
[Supplementary Type Mappings](Documentations/SupplementaryTypeMappings.md).

**Header and export-status annotations:**

```bash
# Leading header block ahead of the imports: generator, image path, UUID,
# architecture, library-evolution detection (dispatch-thunk count), and a
# short digest of facts the binary provably cannot recover
swift-section interface --emit-header /path/to/binary

# Annotate members none of whose symbols (including Tj/Tq/Tu derived forms)
# have an export-trie entry with a `// not exported` comment. `override` and
# `@objc` members are exempt — they are reachable through the parent's
# dispatch thunk / objc_msgSend without any exported symbol of their own.
swift-section interface --emit-export-status /path/to/binary

# Print only the declarations the image exports — the filtering counterpart of
# --emit-export-status. Types and protocols are ruled by their descriptor
# symbol's export-trie entry, extensions by whether their target is an
# in-image non-exported declaration, members by the same derived-form verdict
# the annotation uses. Still a symbol-table fact, never an access-level guess:
# anything without export evidence (and every `override` / `@objc` member) is
# kept, so an `-enable-testing` build keeps its `internal` declarations.
swift-section interface --exported-only /path/to/binary
```

All three flags default to off, keeping default output byte-identical.

**Working with dyld shared cache:**

```bash
# Generate from the system dyld shared cache
swift-section interface --uses-system-dyld-shared-cache --cache-image-name SwiftUICore

# Generate from a specific dyld shared cache
swift-section interface --dyld-shared-cache --cache-image-path /path/to/cache /path/to/dyld_shared_cache
```

#### diff - Compare the ABI of Two Versions

Diff the Swift ABI of two versions of the same module at the **binary** level — field retypes, enum-case tag renumbering, accessor changes, added/removed conformances — details a `.swiftinterface` diff cannot see. Extension changes are attributed **per conformance / per conditional block** (`Target: Protocol where …`), so adding or dropping a single conformance reads as one container-level change. Protocols whose requirement symbols are stripped (the OS-framework norm) still diff by their **witness-table slots**, so a protocol gaining or losing a requirement is visible with zero symbols; compare binaries in similar strip states, since a symbol-rich vs stripped pair reports the same requirement as a member swap.

```bash
# Change-list report with a breaking/backward-compatible verdict
swift-section diff old/Foo.framework/Foo new/Foo.framework/Foo

# Either side may be a persisted baseline produced by `snapshot`
swift-section diff baseline.json new/Foo.framework/Foo

# Machine-readable output / CI gating
swift-section diff old.dylib new.dylib --json
swift-section diff old.dylib new.dylib --summary-only --fail-on-breaking

# Full interface annotated with +/- diff markers (needs two binaries)
swift-section diff old.dylib new.dylib --interface --format unified
```

Both sides are indexed at once by default. `--jobs 1` indexes them one after the other; the result is identical either way.

#### snapshot - Persist an ABI Baseline

Index a binary once and freeze its ABI into a versioned JSON baseline; later diffs and evolution runs can consume the JSON without the original binary.

```bash
swift-section snapshot /path/to/binary --label 1.0 -o baseline-1.0.json

# From a dyld shared cache image
swift-section snapshot --dyld-shared-cache -n SwiftUICore /path/to/dyld_shared_cache --label 26.0 -o swiftuicore-26.0.json
```

#### evolution - Track ABI Across Many Versions

Track one module's ABI across an ordered series of versions (oldest first) and report each declaration's lifeline: introduced / modified / removed / re-added, with a per-transition additive-or-breaking verdict. Inputs mix freely between binaries, dyld shared caches, and `snapshot` baselines.

```bash
# Three OS versions of the same framework, one report
swift-section evolution 17.0.json 18.0.json /path/to/Foo-26.0.dylib --labels 17.0,18.0,26.0

# Across dyld shared caches (extracts the same image from each cache)
swift-section evolution --dyld-shared-cache -n SwiftUICore cache-17 cache-18 cache-26

# Summary or JSON, and CI gating on any breaking transition
swift-section evolution v1.json v2.json v3.json --summary-only --fail-on-breaking
swift-section evolution v1.json v2.json v3.json --json
```

`--jobs N` sets how many versions are indexed at once — the processor count by
default, `1` for one at a time. The result is identical either way; lower it
when memory is tight, since every version in flight holds its own index.

With `--interface`, the same axis renders as a single **annotated union
interface** instead of the lineage list: every declaration that ever existed
appears once (rendered from the last version that has it), declarations that
changed carry a trailing `// [●●○] removed in 26.0`-style comment (presence
bitmap + event phrases; the legend at the top maps bitmap positions to version
labels), and declarations present throughout with no changes stay bare. A
member whose signature changed shows its newest generation, with the old shape
in the comment (`modified in 26.0: old → new`). Because the interface renders
from live models, every input must be a binary or dyld shared cache in this
mode — snapshot JSON inputs are rejected.

```bash
# The union interface with lifecycle annotations, colorized on a terminal
swift-section evolution --interface v17/Foo.dylib v18/Foo.dylib v26/Foo.dylib --labels 17.0,18.0,26.0

# Across dyld shared caches, written to a file, gating CI on breaking changes
swift-section evolution --interface --dyld-shared-cache -n SwiftUICore cache-17 cache-18 cache-26 --fail-on-breaking -o SwiftUICore-evolution.swift
```

#### transformer - Customize Comment Formats

The memory-layout comments `dump` and `interface` emit are rendered from token
templates. Each of the five comment kinds — field offset, vtable offset, member
address, type layout, enum layout — has its own template, its own `${token}`
placeholders, and a set of built-in templates you can name. This subcommand
lists them and builds reusable configurations; the template options themselves
are accepted directly by `dump` and `interface`.

```bash
# What can a template say?
swift-section transformer tokens                        # every module
swift-section transformer tokens --module enum-layout   # one module

# Built-in templates — their names are accepted by the template options
swift-section transformer templates --module field-offset
```

**Using a template.** Pass either a built-in template name or a literal
template containing `${token}` placeholders. A name that matches nothing is an
error rather than a silently constant comment.

```bash
# Built-in template by name: "// 0x0 ..< 0x10"
swift-section dump --field-offset-template range /path/to/binary

# Literal template: "// @0x0"
swift-section dump --field-offset-template '@${startOffset}' /path/to/binary

# Enum layout is three templates: strategy line, per case, per fixed byte
swift-section dump \
    --enum-layout-template strategyOnly \
    --enum-layout-case-template inlineSummary \
    /path/to/binary
```

Passing any template option enables the comment kind it formats, so no separate
`--emit-…` flag is needed. Numbers can be switched between hexadecimal and
decimal per module (`--field-offset-hex` / `--no-field-offset-hex`, and so on).

**Reusable configurations.** A whole set of templates can be frozen into a JSON
file and replayed with `--transformer-config`. The file format is the one
RuntimeViewer persists, so a configuration tuned in its settings UI works here
unchanged.

```bash
# Freeze a command line into a file
swift-section transformer config \
    --field-offset-template range \
    --enum-layout-style compact \
    --output-path comments.json

# Replay it
swift-section dump --transformer-config comments.json /path/to/binary
swift-section interface --transformer-config comments.json /path/to/binary
```

#### objc - Objective-C Declarations and API Diffing

The Objective-C side of a binary, read without loading it into a process — including binaries
for another architecture or platform. `objc` has five subcommands of its own: `dump` (the
default), `interface`, `snapshot`, `diff` and `evolution`. They take the same `-n` / `-p` /
`--dyld-shared-cache` / `--uses-system-dyld-shared-cache` / `-a` input options as the Swift
commands. The Objective-C libraries underneath live in
[MachOObjCSection](https://github.com/MxIris-Reverse-Engineering/MachOObjCSection).

> [!NOTE]
> These commands used to ship as a separate `objc-section` executable from MachOObjCSection,
> last released as 0.8.106. Options, output and exit codes are unchanged; replace
> `objc-section <subcommand>` with `swift-section objc <subcommand>`.

```bash
# Every Objective-C declaration in a binary, as a header
swift-section objc dump /path/to/Some.framework/Some

# One class, protocol, category, struct or union
swift-section objc interface NSString /path/to/Some.framework/Some

# An image inside a dyld shared cache
swift-section objc dump /path/to/dyld_shared_cache_arm64e --dyld-shared-cache -n Foundation
swift-section objc interface NSError --uses-system-dyld-shared-cache -n Foundation

# A fat binary needs an architecture
swift-section objc dump /path/to/Universal -a arm64e
```

Each of the ten generation switches has a flag, and all of them default to off, so a bare
`dump` prints the metadata as it stands:

```bash
swift-section objc interface ACAssetSymbolGeneratorOptions ./AssetCatalogFoundation \
  --strip-synthesized-methods --strip-dtor-method \
  --emit-ivar-offsets --emit-method-imp-addresses \
  --c-type-replacement "long long=NSInteger"
```

```objc
@interface ACAssetSymbolGeneratorOptions : NSObject {
    NSInteger targetPlatform; // offset: 8
    BOOL generateExtensions; // offset: 16
    ...
}

@property (nonatomic, readonly) NSInteger targetPlatform;
...

- (id)init; // IMP: 0x10B400

@end
```

Other `dump` options: `-s/--sections` to pick declaration kinds (comma-separated:
`--sections classes,protocols`), `-f/--filter` to match names, `-o/--output-path` to write a
file, `-c/--color-scheme` for terminal colours, and `-v/--verbose` to report indexing progress
on stderr. A `dump` that finds nothing still exits 0, but says why on stderr — no Objective-C
metadata at all, an empty kind named in `--sections`, or a `--filter` that matched nothing.

`snapshot`, `diff` and `evolution` compare the Objective-C API across binaries, with the same
option spelling as their Swift counterparts. Any input can be a Mach-O / fat binary, a dyld
shared cache (with `--dyld-shared-cache -n <image>`), or a baseline JSON produced by
`snapshot`; the two are told apart automatically.

```bash
# Freeze a binary's Objective-C API as a baseline (indexing is the slow part;
# comparisons against the JSON later need no original binary)
swift-section objc snapshot 15.5/dyld_shared_cache_arm64e --dyld-shared-cache -n CoreLocation \
  --label 15.5 -o CoreLocation-15.5.json

# Classes, protocols and categories, with methods, properties, ivars, protocol
# adoptions and superclass changes classified as added / removed / modified
swift-section objc diff CoreLocation-15.5.json CoreLocation-26.5.json

# Every declaration's lifeline across N ordered versions
swift-section objc evolution CoreLocation-*.json --labels 15.5,26.0,26.5 --summary-only
```

Both `diff` and `evolution` support `--json`, `--summary-only`, `--fail-on-breaking` (exit
nonzero on an API-breaking change, for CI gating) and `-o`. Baselines carry a `formatVersion`;
one written by a different format version is rejected with an error rather than silently
mis-compared, so regenerate it with the current tool. Baselines written by `objc-section`
0.8.106 read unchanged.

The contracts that neither the signatures nor `--help` show — how file mode truncates the
superclass chain, why pure-Swift classes' ivar records do not line up, and the rest — are in
[Objective-C Command Line](Documentations/ObjCCommandLine.md).

## Agent Plugin

The `swift-section` plugin teaches coding agents to drive the CLI: which subcommand answers
which question, the flag spellings that differ between `dump` and `interface`, and the output
traps that produce a plausible but wrong answer. It is a skill only — install the CLI itself
separately (see [Installation](#installation)).

**Claude Code** — inside a session:

```
/plugin marketplace add MxIris-Reverse-Engineering/MachOSwiftSection
/plugin install swift-section@machoswiftsection
```

**Codex**:

```bash
codex plugin marketplace add MxIris-Reverse-Engineering/MachOSwiftSection
codex plugin add swift-section@machoswiftsection
```

The plugin's version follows the CLI's, and an installed plugin only picks up a new release
when that version changes. To pull one in: `claude plugin marketplace update machoswiftsection`
then `claude plugin update swift-section@machoswiftsection` for Claude Code,
`codex plugin marketplace upgrade machoswiftsection` for Codex.

## Documentation

- [Swift Enum Memory Layout](Documentations/SwiftEnumLayout.md) ([中文](Documentations/SwiftEnumLayout_zh.md)) — how Swift lays out enums, and how to read the `--emit-enum-layout` comments.
- [Supplementary Type Mappings](Documentations/SupplementaryTypeMappings.md) — user-provided APINotes for `interface --resolve-c-module-names`.
- [Objective-C Command Line](Documentations/ObjCCommandLine.md) ([中文](Documentations/ObjCCommandLine_zh.md)) — the contracts behind `swift-section objc`.
- [Changelogs](Changelogs/) — what changed in each release, including source-breaking API changes and how to migrate.
- [Documentations/README.md](Documentations/README.md) — the index of every document, maintainer notes and evolution proposals included.

## Running Tests

The snapshot and baseline tests rely on a fixture framework (`SymbolTestsCore`) built from an Xcode project in `Tests/Projects/SymbolTests/`. The framework binary is not checked in — build it once after cloning, and again whenever the fixture's sources change:

```bash
xcodebuild -project Tests/Projects/SymbolTests/SymbolTests.xcodeproj \
    -scheme SymbolTestsCore -configuration Release \
    -destination 'generic/platform=macOS' \
    -derivedDataPath Tests/Projects/SymbolTests/DerivedData/SymbolTests \
    CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO \
    build
```

Build it ad-hoc signed, as above and as CI does. The ABI baselines pin absolute implementation offsets, and an unsigned build (`CODE_SIGNING_ALLOWED=NO`) shifts every one of them, turning several suites red with no code change.

Then run the tests, skipping `IntegrationTests` — a manual-inspection target that prints results without asserting anything:

```bash
swift test --skip IntegrationTests
```

Without the fixture, every fixture-bound test fails within milliseconds with `The file 'SymbolTestsCore' doesn't exist`.

To regenerate the output snapshots after a legitimate Swift-compiler / metadata change:

```bash
SNAPSHOT_TESTING_RECORD=all swift test \
    --filter SymbolTestsCoreDumpSnapshotTests \
    --filter SymbolTestsCoreInterfaceSnapshotTests
```

To regenerate the ABI baselines under `Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/` after a fixture rebuild or a toolchain upgrade (run it from the package directory):

```bash
swift package --allow-writing-to-package-directory regen-baselines
```

Review the diff, then commit the updated `__Snapshots__/` and `__Baseline__/` files alongside the change that prompted the regeneration.

## Acknowledgements

- [MachOKit](https://github.com/p-x9/MachOKit) by p-x9 — the Mach-O reading foundation this library extends, used through the [MxIris-Reverse-Engineering fork](https://github.com/MxIris-Reverse-Engineering/MachOKit).
- [MachOObjCSection](https://github.com/p-x9/MachOObjCSection) by p-x9 — Objective-C metadata parsing, behind `swift-section objc` and the ObjC member recovery, used through the [MxIris-Reverse-Engineering fork](https://github.com/MxIris-Reverse-Engineering/MachOObjCSection).
- [CwlDemangle](https://github.com/mattgallagher/CwlDemangle) by Matt Gallagher — the origin of the demangler, which now lives in [swift-demangling](https://github.com/MxIris-Reverse-Engineering/swift-demangling).
- [Capstone](https://www.capstone-engine.org) — the disassembler `SwiftThunkAnalysis` decodes metadata accessor thunks with, through [swift-capstone](https://github.com/MxIris-Reverse-Engineering/swift-capstone).

## License

MachOSwiftSection is released under the MIT License. See [LICENSE](./LICENSE).

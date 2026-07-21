# MachOSwiftSection

A Swift library for parsing mach-o files to obtain Swift information.
（Types/Protocol/ProtocolConformance info）

It may be the most powerful swift dump you can find so far, as it uses a custom Demangler to parse symbolic references and restore the original logic of the Swift Runtime as much as possible.

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
- [ ] Type Member Layout (WIP, MachOImage only)
- [ ] Swift Section MCP

### Swift Package Manager

Add the package to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/MxIris-Reverse-Engineering/MachOSwiftSection", from: "0.10.0"),
],
targets: [
    .target(
        name: "YourTarget",
        dependencies: [
            .product(name: "MachOSwiftSection", package: "MachOSwiftSection"),
            // Optional higher-level products:
            .product(name: "SwiftInspection", package: "MachOSwiftSection"),
            .product(name: "SwiftDump", package: "MachOSwiftSection"),
            .product(name: "SwiftInterface", package: "MachOSwiftSection"),
            .product(name: "TypeIndexing", package: "MachOSwiftSection"),
        ]
    ),
]
```

| Product | Purpose |
| --- | --- |
| `MachOSwiftSection` | Low-level parsing of `__swift5_*` sections (raw descriptors). |
| `SwiftInspection` | Runtime metadata inspection — `EnumLayoutCalculator` (multi-payload enum layouts), `ClassHierarchyDumper`, `MetadataReader`. |
| `SwiftDump` | High-level type wrappers (`Struct`, `Enum`, `Class`, `Protocol`, `ProtocolConformance`, …). |
| `SwiftInterface` | End-to-end Swift interface generation. |
| `TypeIndexing` | Index types / extensions / conformances for cross-binary analysis. |

### Usage

#### Basic

Swift information from MachOImage or MachOFile can be retrieved via the `swift` property.

```swift
import MachOKit
import MachOSwiftSection

let machO //` MachOFile` or `MachOImage`

// Protocol Descriptors
let protocolDescriptors = try machO.swift.protocolDescriptors
for protocolDescriptor in protocolDescriptors {
    let protocolType = try Protocol(descriptor: protocolDescriptor, in: machO)
    // do somethings ...
}

// Protocol Conformance Descriptors
let protocolConformanceDescriptors = try machO.swift.protocolConformanceDescriptors
for protocolConformanceDescriptor in protocolConformanceDescriptors {
    let protocolConformance = try ProtocolConformance(descriptor: protocolConformanceDescriptor, in: machO)
    // do somethings ...
}

// Type/Nominal Descriptors
let typeContextDescriptors = try machO.swift.typesContextDescriptors
for typeContextDescriptor in typeContextDescriptors {
    switch typeContextDescriptor {
    case .type(let typeContextDescriptorWrapper):
        switch typeContextDescriptorWrapper {
        case .enum(let enumDescriptor):
            let enumType = try Enum(descriptor: enumDescriptor, in: machO)
            // do somethings ...
        case .struct(let structDescriptor):
            let structType = try Struct(descriptor: structDescriptor, in: machO)
            // do somethings ...
        case .class(let classDescriptor):
            let classType = try Class(descriptor: classDescriptor, in: machO)
            // do somethings ...
        }
    default:
        break
    }
}
```

#### Generate Complete Swift Interface

For generating complete Swift interface files, you can use the `SwiftInterface` library which provides a more comprehensive interface generation capability.

```swift
import MachOKit
import SwiftInterface

let builder = try SwiftInterfaceBuilder(configuration: .init(), eventHandlers: [], in: machO)
try await builder.prepare()
let result = try await builder.printRoot()
```

Generated interfaces reflect a wide range of Swift language features:

- Type / member attributes: `@objc`, `@nonobjc`, `dynamic`, `@retroactive`, `@globalActor`, `@escaping`, `consuming` / `borrowing` parameter modifiers
- `distributed actor` declarations and `distributed func` members
- `deinit` for classes and noncopyable types
- VTable offset comments alongside class members, ordered to match the on-disk layout
- Expanded field offsets for nested struct fields, rendered as a tree
- Inverted protocols (`~Copyable`, `~Escapable`) on types and generic requirements

#### Inspect Runtime Metadata

`SwiftInspection` exposes higher-level inspection utilities built on top of `MachOSwiftSection`:

- `EnumLayoutCalculator` — compute the on-disk layout of Swift enums, including single-payload and multi-payload (tagged and untagged) cases. Mirrors the ABI rules in `swift/ABI/Enum.h`.
- `ClassHierarchyDumper` — walk a class's inheritance chain across Swift/ObjC boundaries (requires `@_spi(Internals) import SwiftInspection`, `MachOImage` only).
- `MetadataReader` — demangle types, symbols, context descriptors, and build generic signatures against a Mach-O.

## swift-section CLI Tool

### Installation

You can get the swift-section CLI tool in three ways:

- **GitHub Releases**: Download from [GitHub releases](https://github.com/MxIris-Reverse-Engineering/MachOSwiftSection/releases)
- **Homebrew**: Install via `brew install swift-section`
- **Build from Source**: Build with `./build-executable-product.sh` (requires Xcode 26.0 / Swift 6.2+ toolchain)

### Usage

The swift-section CLI tool provides five subcommands: `dump`, `interface`, `diff`, `snapshot`, and `evolution`.

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

# Dump only types and protocols
swift-section dump --sections types,protocols /path/to/binary

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
swift-section dump --emit-enum-layout --enum-layout-style explained /path/to/binary
```

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

Dump output includes richer annotations:

- Protocol witness table (PWT) entries are annotated with the requirement they satisfy
- Inverted protocol constraints (`~Copyable`, `~Escapable`) are rendered on types and generic requirements
- Protocol conformances can include the PWT address

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

**Working with dyld shared cache:**

```bash
# Dump from system dyld shared cache
swift-section interface --uses-system-dyld-shared-cache --cache-image-name SwiftUICore

# Dump from specific dyld shared cache
swift-section interface --dyld-shared-cache --cache-image-path /path/to/cache /path/to/dyld_shared_cache
```

#### diff - Compare the ABI of Two Versions

Diff the Swift ABI of two versions of the same module at the **binary** level — field retypes, enum-case tag renumbering, accessor changes, added/removed conformances — details a `.swiftinterface` diff cannot see.

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

## Running Tests

The snapshot tests in this repository rely on a fixture framework (`SymbolTestsCore`) built from an Xcode project in `Tests/Projects/SymbolTests/`. The framework binary is not checked in — rebuild it once after cloning:

```bash
./Scripts/build-test-fixtures.sh
```

Then run the tests:

```bash
swift package update
swift test
```

Skipping the fixture build causes `MachOFileTests` to throw a "file not found" error at `Tests/Projects/SymbolTests/DerivedData/.../SymbolTestsCore` during test `init()`, before any assertions run.

To regenerate snapshots after a legitimate Swift-compiler / metadata change:

```bash
SNAPSHOT_TESTING_RECORD=all swift test \
    --filter SymbolTestsCoreDumpSnapshotTests \
    --filter SymbolTestsCoreInterfaceSnapshotTests
```

Commit the updated `__Snapshots__/` files alongside the source change that prompted the regeneration.

## License

[MachOObjCSection](https://github.com/p-x9/MachOObjCSection)

[MachOKit](https://github.com/p-x9/MachOKit)

[CwlDemangle](https://github.com/mattgallagher/CwlDemangle)

MachOSwiftSection is released under the MIT License. See [LICENSE](./LICENSE)

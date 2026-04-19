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
    .package(url: "https://github.com/MxIris-Reverse-Engineering/MachOSwiftSection", from: "0.9.1"),
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

The swift-section CLI tool provides two main subcommands: `dump`, and `interface`.

> [!IMPORTANT]
> As of 0.9.0, when the input is a fat / universal binary you must pass `--architecture <arch>`. The tool no longer picks a default slice silently.

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

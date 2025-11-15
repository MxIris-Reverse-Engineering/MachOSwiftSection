# MachOSwiftSection

A Swift library for parsing mach-o files to obtain Swift information.
（Types/Protocol/ProtocolConformance info）

It may be the most powerful swift dump you can find so far, as it uses a custom Demangler to parse symbolic references and restore the original logic of the Swift Runtime as much as possible.

> [!NOTE]
> This library is developed as an extension of [MachOKit](https://github.com/p-x9/MachOKit) for Swift

## MachOSwiftSection Library

### Roadmap

- [x] Protocol Descriptors
- [x] Protocol Conformance Descriptors
- [x] Type Context Descriptors
- [x] Associated Type Descriptors
- [x] Method Symbol For Dyld Caches
- [x] Builtin Type Descriptors
- [x] Swift Interface Support
- [ ] Type Member Layout (WIP, MachOImage only)
- [ ] Swift Section MCP

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

## swift-section CLI Tool

### Installation

You can get the swift-section CLI tool in three ways:

- **GitHub Releases**: Download from [GitHub releases](https://github.com/MxIris-Reverse-Engineering/MachOSwiftSection/releases)
- **Homebrew**: Install via `brew install swift-section`
- **Build from Source**: Build with `./build-executable-product.sh` (requires Xcode 26.0 / Swift 6.2+ toolchain)

### Usage

The swift-section CLI tool provides two main subcommands: `dump`, and `interface`.

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

# Use specific architecture
swift-section dump --architecture arm64 /path/to/binary
```

**Working with dyld shared cache:**
```bash
# Dump from system dyld shared cache
swift-section dump --uses-system-dyld-shared-cache --cache-image-name SwiftUICore

# Dump from specific dyld shared cache
swift-section dump --dyld-shared-cache --cache-image-path /path/to/cache /path/to/dyld_shared_cache
```

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

# Use specific architecture
swift-section interface --architecture arm64 /path/to/binary

**Working with dyld shared cache:**
```bash
# Dump from system dyld shared cache
swift-section interface --uses-system-dyld-shared-cache --cache-image-name SwiftUICore

# Dump from specific dyld shared cache
swift-section interface --dyld-shared-cache --cache-image-path /path/to/cache /path/to/dyld_shared_cache
```

## License

[MachOObjCSection](https://github.com/p-x9/MachOObjCSection)

[MachOKit](https://github.com/p-x9/MachOKit)

[CwlDemangle](https://github.com/mattgallagher/CwlDemangle)

MachOSwiftSection is released under the MIT License. See [LICENSE](./LICENSE)

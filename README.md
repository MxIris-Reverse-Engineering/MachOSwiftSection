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
- [ ] Type Member Layout (WIP)
- [ ] Builtin Type Descriptors
- [ ] Capture Descriptors

### Usage

#### Basic

Swift information from MachOImage or MachOFile can be retrieved via the `swift` property.

```swift
import MachOKit
import MachOSwiftSection

let machO //` MachOFile` or `MachOImage`

// Protocol Descriptors
let protocolDescriptors = machO.swift.protocolDescriptors ?? []
for protocolDescriptor in protocolDescriptors {
    let protocolType = try Protocol(descriptor: protocolDescriptor, in: machO)
    // do somethings ...
}

// Protocol Conformance Descriptors
let protocolConformanceDescriptors = machO.swift.protocolConformanceDescriptors ?? []
for protocolConformanceDescriptor in protocolConformanceDescriptors {
    let protocolConformance = try ProtocolConformance(descriptor: protocolConformanceDescriptor, in: machO)
    // do somethings ...
}

// Type/Nominal Descriptors
let typeContextDescriptors = machO.swift.typesContextDescriptors ?? []
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

#### Dump Swift Interface

Swift Interface definitions can be dump from Enum/Struct/Class/Protocol/ProtocolConformance/AssociatedType model

First, you need to import `SwiftDump` module.

#### Generate Complete Swift Interface

For generating complete Swift interface files, you can use the `SwiftInterface` library which provides a more comprehensive interface generation capability.

Options can customize the print content, such as using syntactic sugar types or strip the ObjC Module.

```swift
import MachOKit
import MachOSwiftSection
import SwiftDump

let typeContextDescriptors = machO.swift.typesContextDescriptors ?? []
for typeContextDescriptor in typeContextDescriptors {
    switch typeContextDescriptor {
    case .type(let typeContextDescriptorWrapper):
        switch typeContextDescriptorWrapper {
        case .enum(let enumDescriptor):
            let enumType = try Enum(descriptor: enumDescriptor, in: machO)
            try print(enumType.dump(using: printOptions, in: machO))
        case .struct(let structDescriptor):
            let structType = try Struct(descriptor: structDescriptor, in: machO)
            try print(structType.dump(using: printOptions, in: machO))
        case .class(let classDescriptor):
            let classType = try Class(descriptor: classDescriptor, in: machO)
            try print(classType.dump(using: printOptions, in: machO))
        }
    default:
        break
    }
}
```

<details>

<summary>Example of dumped string</summary>

```swift
enum Foundation.Date.ComponentsFormatStyle.Field.Option {
    case year
    case month
    case week
    case day
    case hour
    case minute
    case second
}
enum Foundation.Date.ComponentsFormatStyle.Field.CodingKeys {
    case option
}
struct Foundation.LocaleCache {
    let lock: LockedState<LocaleCache.State>
    let _currentCache: LockedState<_LocaleProtocol?>
    var _currentNSCache: LockedState<_NSSwiftLocale?>
}
struct Foundation.TimeZoneCache {
    let lock: LockedState<TimeZoneCache.State>
}
```

</details>

## swift-section CLI Tool

### Installation

You can get the swift-section CLI tool in three ways:

- **GitHub Releases**: Download from [GitHub releases](https://github.com/MxIris-Reverse-Engineering/MachOSwiftSection/releases)
- **Homebrew**: Install via `brew install swift-section`
- **Build from Source**: Build with `./build-executable-product.sh` (requires Xcode 16.3 / Swift 6.1+ toolchain)

### Usage

The swift-section CLI tool provides three main subcommands: `dump`, `demangle`, and `interface`.

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
swift-section dump --uses-system-dyld-shared-cache --cache-image-name UIKit

# Dump from specific dyld shared cache
swift-section dump --dyld-shared-cache --cache-image-path /path/to/cache /path/to/dyld_shared_cache
```

#### demangle - Demangle Swift Names

Demangle mangled Swift names in a Mach-O file.

```bash
swift-section demangle [options] [file-path] --mangled-name <mangled-name>
```

**Basic usage:**
```bash
# Demangle a specific mangled name
swift-section demangle /path/to/binary --mangled-name '$s10Foundation4DateV18ComponentsFormatStyleV5FieldV6OptionO4yearAIcACmF'

# Demangle with specific file offset
swift-section demangle /path/to/binary --mangled-name '$s...' --file-offset 0x1000

# Use simplified demangle options
swift-section demangle /path/to/binary --mangled-name '$s...' --demangle-options simplified
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
swift-section interface --output-path interface.swift /path/to/binary
```

## License

[MachOObjCSection](https://github.com/p-x9/MachOObjCSection)

[MachOKit](https://github.com/p-x9/MachOKit)

[CwlDemangle](https://github.com/mattgallagher/CwlDemangle)

MachOSwiftSection is released under the MIT License. See [LICENSE](./LICENSE)

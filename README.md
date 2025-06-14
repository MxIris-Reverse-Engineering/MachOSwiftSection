# MachOSwiftSection

A Swift library for parsing mach-o files to obtain Swift information.
（Types/Protocol/ProtocolConformance info）

It may be the most powerful swift dump you can find so far, as it uses a custom Demangler to parse symbolic references and restore the original logic of the Swift Runtime as much as possible.

> [!NOTE]
> This library is developed as an extension of [MachOKit](https://github.com/p-x9/MachOKit) for Swift

## Roadmap

- [x] Protocol Descriptors
- [x] Protocol Conformance Descriptors
- [x] Type Context Descriptors
- [x] Associated Type Descriptors
- [x] Method Symbol For Dyld Caches
- [ ] Type Member Layout (WIP)
- [ ] Builtin Type Descriptors
- [ ] Capture Descriptors

## Usage

### Basic

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

## License

[MachOObjCSection](https://github.com/p-x9/MachOObjCSection)

[MachOKit](https://github.com/p-x9/MachOKit)

[CwlDemangle](https://github.com/mattgallagher/CwlDemangle)

MachOSwiftSection is released under the MIT License. See [LICENSE](./LICENSE)

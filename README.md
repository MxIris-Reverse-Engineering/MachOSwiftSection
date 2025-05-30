# MachOSwiftSection

> [!NOTE]
> The dyld subCache parsing error is a known issues. please switch to `MachOKit`'s main branch as a temporary workaround.
> https://github.com/p-x9/MachOKit/commit/064dd49dda8ceeeae5857782bcd5037e34fc2e19

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
- [ ] Builtin Type Descriptors
- [ ] Capture Descriptors
- [ ] Type Member Layout
- [ ] Method Symbol For Dyld Caches

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
    try print(Protocol(descriptor: protocolDescriptor, in: machO))
}

// Protocol Conformance Descriptors
let protocolConformanceDescriptors = machO.swift.protocolConformanceDescriptors ?? []
for (index, protocolConformanceDescriptor) in protocolConformanceDescriptors.enumerated() {
    print(index)
    try print(ProtocolConformance(descriptor: protocolConformanceDescriptor, in: machO))
}

// Type/Nominal Descriptors
let typeContextDescriptors = machO.swift.typesContextDescriptors ?? []
for typeContextDescriptor in typeContextDescriptors {
    switch typeContextDescriptor.flags.kind {
    case .enum:
        let enumDescriptor = try typeContextDescriptor.enumDescriptor(in: machO)!
        let enumType = try Enum(descriptor: enumDescriptor, in: machO)
        try print(enumType.dump(using: .default, in: machO))
    case .struct:
        let structDescriptor = try typeContextDescriptor.structDescriptor(in: machO)!
        let structType = try Struct(descriptor: structDescriptor, in: machO)
        try print(structType.dump(using: .default, in: machO))
    case .class:
        let classDescriptor = try typeContextDescriptor.classDescriptor(in: machO)!
        let classType = try Class(descriptor: classDescriptor, in: machO)
        try print(classType.dump(using: .default, in: machO))
    default:
        break
    }
}
```

#### Dump Swift Interface

Swift Interface definitions can be dump from Enum/Struct/Class/Protocol/ProtocolConformance/AssociatedType model

Options can customize the print content, such as using syntactic sugar types or strip the ObjC Module.

```swift
let enumDescriptor = try typeContextDescriptor.enumDescriptor(in: machO)!
let enumType = try Enum(descriptor: enumDescriptor, in: machO)
try print(enumType.dump(using: .default, in: machO))
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

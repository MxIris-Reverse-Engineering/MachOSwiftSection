//
//  GenericRequirementFlags.swift
//  MachOSwiftSection
//
//  Created by JH on 2025/5/2.
//


public struct GenericRequirementFlags: OptionSet {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let isPackRequirement = GenericRequirementFlags(rawValue: 0x20)
    public static let hasKeyArgument = GenericRequirementFlags(rawValue: 0x80)
    public static let isValueRequirement = GenericRequirementFlags(rawValue: 0x100)

    public var kind: GenericRequirementKind {
        .init(rawValue: UInt8(rawValue & 0x1F))!
    }
}

//
//  GenericContextDescriptorFlags.swift
//  MachOSwiftSection
//
//  Created by JH on 2025/5/2.
//


public struct GenericContextDescriptorFlags: OptionSet {
    public let rawValue: UInt16

    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    public static let hasTypePacks = GenericContextDescriptorFlags(rawValue: 1 << 0)
    public static let hasConditionalInvertedProtocols = GenericContextDescriptorFlags(rawValue: 1 << 1)
    public static let hasValues = GenericContextDescriptorFlags(rawValue: 1 << 2)
}

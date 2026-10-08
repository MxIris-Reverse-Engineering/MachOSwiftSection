import Foundation

public struct GenericEnvironmentFlags: OptionSet, Sendable {
    public typealias RawValue = UInt32

    public let rawValue: RawValue

    public init(rawValue: RawValue) {
        self.rawValue = rawValue
    }

    private enum Bits {
        static let numGenericParameterLevelsMask: RawValue = 0xFFF
        static let numGenericRequirementsShift: RawValue = 12
        static let numGenericRequirementsMask: RawValue = 0xFFFF << Self.numGenericRequirementsShift
    }

    public var numberOfGenericParameterLevels: RawValue {
        rawValue & Bits.numGenericParameterLevelsMask
    }

    public var numberOfGenericRequirements: RawValue {
        (rawValue & Bits.numGenericRequirementsMask) >> Bits.numGenericRequirementsShift
    }
}

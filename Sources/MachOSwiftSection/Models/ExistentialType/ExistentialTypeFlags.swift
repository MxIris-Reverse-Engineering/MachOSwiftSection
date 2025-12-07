import Foundation
import MachOFoundation

public struct ExistentialTypeFlags: OptionSet, Sendable {
    public typealias RawValue = UInt32
    public let rawValue: RawValue
    public init(rawValue: RawValue) {
        self.rawValue = rawValue
    }

    private static let numWitnessTablesMask: RawValue = 0x00FF_FFFF
    private static let classConstraintMask: RawValue = 0x8000_0000
    private static let hasSuperclassMask: RawValue = 0x4000_0000
    private static let specialProtocolMask: RawValue = 0x3F00_0000
    private static let specialProtocolShift: RawValue = 24

    public var numberOfWitnessTables: RawValue {
        rawValue & Self.numWitnessTablesMask
    }

    public var classConstraint: ProtocolClassConstraint {
        .init(rawValue: .init(rawValue & Self.classConstraintMask))!
    }

    public var hasSuperclassConstraint: Bool {
        rawValue & Self.hasSuperclassMask != 0
    }

    public var specialProtocol: SpecialProtocolKind {
        .init(rawValue: .init((rawValue & Self.specialProtocolMask) >> Self.specialProtocolShift))!
    }
}

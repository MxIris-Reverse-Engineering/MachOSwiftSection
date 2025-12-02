import Foundation
import MachOFoundation

public struct ExistentialTypeFlags: OptionSet, Sendable {
    public typealias RawValue = UInt32
    public let rawValue: RawValue
    public init(rawValue: RawValue) {
        self.rawValue = rawValue
    }

    private enum Bits {
        static let numWitnessTablesMask: RawValue = 0x00FF_FFFF
        static let classConstraintMask: RawValue = 0x8000_0000
        static let hasSuperclassMask: RawValue = 0x4000_0000
        static let specialProtocolMask: RawValue = 0x3F00_0000
        static let specialProtocolShift: RawValue = 24
    }

    public var numberOfWitnessTables: RawValue {
        rawValue & Bits.numWitnessTablesMask
    }

    public var classConstraint: ProtocolClassConstraint {
        .init(rawValue: .init(rawValue & Bits.classConstraintMask))!
    }

    public var hasSuperclassConstraint: Bool {
        rawValue & Bits.hasSuperclassMask != 0
    }

    public var specialProtocol: SpecialProtocolKind {
        .init(rawValue: .init((rawValue & Bits.specialProtocolMask) >> Bits.specialProtocolShift))!
    }
}

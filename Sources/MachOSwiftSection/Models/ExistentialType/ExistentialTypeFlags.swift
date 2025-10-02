import Foundation
import MachOFoundation
import MachOMacro

public struct ExistentialTypeFlags: OptionSet {
    public typealias RawValue = UInt32
    public let rawValue: RawValue
    public init(rawValue: RawValue) {
        self.rawValue = rawValue
    }

    private enum Bits {
        static let numWitnessTablesMask: RawValue = 0x00FFFFFF
        static let classConstraintMask: RawValue = 0x80000000
        static let hasSuperclassMask: RawValue = 0x40000000
        static let specialProtocolMask: RawValue = 0x3F000000
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

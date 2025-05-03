import Foundation

public struct ProtocolContextDescriptorFlags: FlagSet {
    public let rawValue: UInt16

    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    private enum Bits {
        static let hasClassConstraint = 0
        static let hasClassConstraintWidth = 1
        static let isResilient = 1
        static let specialProtocolKind = 2
        static let specialProtocolKindWidth = 6
    }
    
    public var isResilient: Bool {
        return flag(bit: Bits.isResilient)
    }
    
    public var classConstraint: ProtocolClassConstraint {
        .init(rawValue: field(firstBit: Bits.hasClassConstraint, bitWidth: Bits.hasClassConstraintWidth, fieldType: UInt8.self))!
    }
    
    public var specialProtocolKind: SpecialProtocolKind {
        .init(rawValue: field(firstBit: Bits.specialProtocolKind, bitWidth: Bits.specialProtocolKindWidth, fieldType: UInt8.self))!
    }
}

public enum ProtocolClassConstraint: UInt8 {
    case `class`
    case any
}

public enum SpecialProtocolKind: UInt8 {
    case none
    case error
}

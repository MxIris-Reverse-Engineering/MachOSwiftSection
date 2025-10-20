public struct ProtocolDescriptorFlags {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    private enum Bits {
        static let isSwift: UInt32 = 1 << 0
        static let classConstraint: UInt32 = 1 << 1
        static let dispatchStrategyMask: UInt32 = 0xF << 2
        static let dispatchStrategyShift: UInt32 = 2
        static let specialProtocolMask: UInt32 = 0x000003C0
        static let specialProtocolShift: UInt32 = 6
        static let isResilient: UInt32 = 1 << 10
        static let objcReserved: UInt32 = 0xFFFF0000
    }

    public var isSwift: Bool {
        rawValue & Bits.isSwift != .zero
    }

    public var isResilient: Bool {
        rawValue & Bits.isResilient != .zero
    }

    public var classConstraint: ProtocolClassConstraint {
        .init(rawValue: UInt8(rawValue & Bits.classConstraint))!
    }

    public var dispatchStrategy: ProtocolDispatchStrategy {
        .init(rawValue: UInt8((rawValue & Bits.dispatchStrategyMask) >> Bits.dispatchStrategyShift))!
    }

    public var specialProtocolKind: SpecialProtocolKind {
        .init(rawValue: UInt8((rawValue & Bits.specialProtocolMask) >> Bits.specialProtocolShift))!
    }

    public var needsProtocolWitnessTable: Bool {
        switch dispatchStrategy {
        case .objc:
            false
        case .swift:
            true
        }
    }
}

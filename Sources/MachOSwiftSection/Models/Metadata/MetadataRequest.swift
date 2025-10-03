import Foundation

public struct MetadataRequest: MutableFlagSet {
    public typealias RawValue = Int

    public var rawValue: RawValue

    public init(rawValue: RawValue) {
        self.rawValue = rawValue
    }

    public init() {
        self.init(rawValue: 0)
    }

    public init(state: MetadataState, isBlocking: Bool) {
        self.init()
        self.state = state
        self.isBlocking = isBlocking
    }

    private enum Bits {
        static let stateBit: RawValue = 0
        static let stateWidth: RawValue = 8
        static let nonBlockingBit: RawValue = 8
    }

    public var state: MetadataState {
        set {
            setField(newValue.rawValue, firstBit: Bits.stateBit, bitWidth: Bits.stateWidth)
        }
        get {
            MetadataState(rawValue: field(firstBit: Bits.stateBit, bitWidth: Bits.stateWidth, fieldType: MetadataState.RawValue.self))!
        }
    }

    public var isBlocking: Bool {
        set {
            setFlag(newValue, bit: Bits.nonBlockingBit)
        }
        get {
            flag(bit: Bits.nonBlockingBit)
        }
    }
}

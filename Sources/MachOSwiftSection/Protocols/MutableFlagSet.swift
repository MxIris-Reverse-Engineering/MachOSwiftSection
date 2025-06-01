import Foundation

public protocol MutableFlagSet: FlagSet {
    var rawValue: RawValue { get set }

    mutating func setFlag(_ value: Bool, bit: Int)

    mutating func setField<FieldType: FixedWidthInteger>(
        _ value: FieldType,
        firstBit: Int,
        bitWidth: Int
    )
}

extension MutableFlagSet {
    @inline(__always)
    public mutating func setFlag(_ value: Bool, bit: Int) {
        precondition(bit >= 0 && bit < RawValue.bitWidth, "Bit index out of range.")
        let mask = Self.mask(forFirstBit: bit)
        if value {
            rawValue |= mask
        } else {
            rawValue &= ~mask
        }
    }

    @inline(__always)
    public mutating func setField<FieldType: FixedWidthInteger>(
        _ value: FieldType,
        firstBit: Int,
        bitWidth: Int
    ) {
        precondition(bitWidth > 0, "Bit width must be positive.")
        precondition(firstBit >= 0 && (firstBit + bitWidth) <= RawValue.bitWidth, "Field range is out of bounds for the storage type.")

        let valueMask = Self.lowMask(forBitWidth: bitWidth)
        let rawValueEquivalent = RawValue(truncatingIfNeeded: value)

        precondition((rawValueEquivalent & ~valueMask) == 0, "Value \(value) is too large to fit in a field of width \(bitWidth).")

        let fieldMask = Self.mask(forFirstBit: firstBit, bitWidth: bitWidth)
        rawValue &= ~fieldMask
        rawValue |= (rawValueEquivalent << firstBit) & fieldMask
    }
}

import Foundation

public protocol FlagSet: Equatable, RawRepresentable where RawValue: FixedWidthInteger {
    func flag(bit: Int) -> Bool

    func field<FieldType: FixedWidthInteger>(
        firstBit: Int,
        bitWidth: Int,
        fieldType: FieldType.Type
    ) -> FieldType where FieldType.Magnitude == FieldType
}

public protocol MutableFlagSet: FlagSet {
    var rawValue: RawValue { get set }

    mutating func setFlag(_ value: Bool, bit: Int)

    mutating func setField<FieldType: FixedWidthInteger>(
        _ value: FieldType,
        firstBit: Int,
        bitWidth: Int
    )
}

extension FlagSet {
    @inline(__always)
    fileprivate static func lowMask(forBitWidth bitWidth: Int) -> RawValue {
        precondition(bitWidth >= 0 && bitWidth <= RawValue.bitWidth, "Bit width must be between 0 and the storage type's bit width.")
        if bitWidth == RawValue.bitWidth {
            return ~RawValue(0) // All bits set
        }
        if bitWidth == 0 {
            return 0
        }
        let mask = (RawValue(1) << bitWidth) &- 1
        return mask
    }

    @inline(__always)
    fileprivate static func mask(forFirstBit firstBit: Int, bitWidth: Int = 1) -> RawValue {
        precondition(firstBit >= 0, "First bit index cannot be negative.")
        precondition(bitWidth >= 1, "Bit width must be at least 1.")
        precondition(firstBit + bitWidth <= RawValue.bitWidth, "Field extends beyond the storage type's bit width.")
        return lowMask(forBitWidth: bitWidth) << firstBit
    }

    @inline(__always)
    public func flag(bit: Int) -> Bool {
        precondition(bit >= 0 && bit < RawValue.bitWidth, "Bit index out of range.")
        return (rawValue & Self.mask(forFirstBit: bit)) != 0
    }

    @inline(__always)
    public func field<FieldType: FixedWidthInteger>(
        firstBit: Int,
        bitWidth: Int,
        fieldType: FieldType.Type = FieldType.self
    ) -> FieldType where FieldType.Magnitude == FieldType {
        precondition(bitWidth > 0, "Bit width must be positive.")
        precondition(firstBit >= 0 && (firstBit + bitWidth) <= RawValue.bitWidth, "Field range is out of bounds for the storage type.")
        precondition(FieldType.bitWidth >= bitWidth, "The requested FieldType is too small to represent a value of the specified bitWidth.")

        let mask = Self.lowMask(forBitWidth: bitWidth)
        let shiftedValue = rawValue >> firstBit
        let isolatedValue = shiftedValue & mask
        return FieldType(truncatingIfNeeded: isolatedValue)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        return lhs.rawValue == rhs.rawValue
    }
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

public struct ValueWitnessFlags: OptionSet, Sendable {
    public typealias RawValue = UInt32

    public let rawValue: RawValue

    public init(rawValue: RawValue) {
        self.rawValue = rawValue
    }

    public static let isNonPOD = ValueWitnessFlags(rawValue: 0x0001_0000)
    public static let isNonInline = ValueWitnessFlags(rawValue: 0x0002_0000)
    public static let hasSpareBits = ValueWitnessFlags(rawValue: 0x0008_0000)
    public static let isNonBitwiseTakable = ValueWitnessFlags(rawValue: 0x0010_0000)
    public static let hasEnumWitnesses = ValueWitnessFlags(rawValue: 0x0020_0000)
    public static let inComplete = ValueWitnessFlags(rawValue: 0x0040_0000)
    public static let isNonCopyable = ValueWitnessFlags(rawValue: 0x0080_0000)
    public static let isNonBitwiseBorrowable = ValueWitnessFlags(rawValue: 0x0100_0000)
    /// The type is `@_addressableForDependencies`: a value's address is part
    /// of its identity for lifetime-dependent borrows, so a borrow of it must
    /// use the pointer representation (`Builtin.Borrow`). Set by IRGen for
    /// the attribute and propagated through aggregates; the Swift 6.4 runtime
    /// also sets it on `Builtin.FixedArray` metadata.
    public static let isAddressableForDependencies = ValueWitnessFlags(rawValue: 0x0200_0000)

    public static let alignmentMask: UInt32 = 0x0000_00FF
    public static let maxNumExtraInhabitants: UInt32 = 0x7FFF_FFFF

    public var alignmentMask: StoredSize {
        numericCast(rawValue & Self.alignmentMask)
    }

    public var alignment: StoredSize {
        alignmentMask + 1
    }

    public var isPOD: Bool {
        !contains(.isNonPOD)
    }

    public var isInlineStorage: Bool {
        !contains(.isNonInline)
    }

    public var isBitwiseTakable: Bool {
        !contains(.isNonBitwiseTakable)
    }

    public var isBitwiseBorrowable: Bool {
        !contains(.isNonBitwiseBorrowable) && isBitwiseTakable
    }

    public var isCopyable: Bool {
        !contains(.isNonCopyable)
    }

    public var isAddressableForDependencies: Bool {
        contains(.isAddressableForDependencies)
    }

    public var hasEnumWitnesses: Bool {
        contains(.hasEnumWitnesses)
    }

    public var isIncomplete: Bool {
        contains(.inComplete)
    }
}

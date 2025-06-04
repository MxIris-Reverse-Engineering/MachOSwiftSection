public struct ValueWitnessFlags: OptionSet, Sendable {
    public typealias RawValue = UInt32
    
    public let rawValue: RawValue
    
    public init(rawValue: RawValue) {
        self.rawValue = rawValue
    }
    
    public static let isNonPOD = ValueWitnessFlags(rawValue: 0x00010000)
    public static let isNonInline = ValueWitnessFlags(rawValue: 0x00020000)
    public static let hasSpareBits = ValueWitnessFlags(rawValue: 0x00080000)
    public static let isNonBitwiseTakable = ValueWitnessFlags(rawValue: 0x00100000)
    public static let hasEnumWitnesses = ValueWitnessFlags(rawValue: 0x00200000)
    public static let inComplete = ValueWitnessFlags(rawValue: 0x00400000)
    public static let isNonCopyable = ValueWitnessFlags(rawValue: 0x00800000)
    public static let isNonBitwiseBorrowable = ValueWitnessFlags(rawValue: 0x01000000)

    public static let alignmentMask: UInt32 = 0x000000FF
    public static let maxNumExtraInhabitants: UInt32 = 0x7FFFFFFF
    
    
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
    
    public var hasEnumWitnesses: Bool {
        contains(.hasEnumWitnesses)
    }
    
    public var isIncomplete: Bool {
        contains(.inComplete)
    }
    
}

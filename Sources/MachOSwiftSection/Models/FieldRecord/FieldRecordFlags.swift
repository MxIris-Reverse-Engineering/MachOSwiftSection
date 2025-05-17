public struct FieldRecordFlags: OptionSet {
    public let rawValue: UInt32
    
    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let isIndirectCase = FieldRecordFlags(rawValue: 1 << 0)
    public static let isVariadic = FieldRecordFlags(rawValue: 1 << 1)
    public static let isArtificial = FieldRecordFlags(rawValue: 1 << 2)
}

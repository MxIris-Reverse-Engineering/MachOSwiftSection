public struct GenericContextDescriptorFlags: OptionSet, Sendable {
    public let rawValue: UInt16

    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    public static let hasTypePacks = GenericContextDescriptorFlags(rawValue: 1 << 0)
    public static let hasConditionalInvertedProtocols = GenericContextDescriptorFlags(rawValue: 1 << 1)
    public static let hasValues = GenericContextDescriptorFlags(rawValue: 1 << 2)
}

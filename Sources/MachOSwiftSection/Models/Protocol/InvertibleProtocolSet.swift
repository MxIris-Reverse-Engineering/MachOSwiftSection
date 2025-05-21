import Foundation

public struct InvertibleProtocolSet: OptionSet {
    public let rawValue: UInt16
    
    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }
    
    public static let hasCopyable = InvertibleProtocolSet(rawValue: 1 << InvertibleProtocolKind.copyable.rawValue)
    public static let hasEscapable = InvertibleProtocolSet(rawValue: 1 << InvertibleProtocolKind.escapable.rawValue)
}

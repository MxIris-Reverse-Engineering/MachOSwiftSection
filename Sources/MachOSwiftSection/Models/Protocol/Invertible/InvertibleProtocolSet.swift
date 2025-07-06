import Foundation

public struct InvertibleProtocolSet: OptionSet, Sendable {
    public let rawValue: UInt16
    
    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }
    
    public static let copyable = InvertibleProtocolSet(rawValue: 1 << InvertibleProtocolKind.copyable.rawValue)
    
    public static let escapable = InvertibleProtocolSet(rawValue: 1 << InvertibleProtocolKind.escapable.rawValue)
    
    public var hasCopyable: Bool {
        contains(.copyable)
    }
    
    public var hasEscapable: Bool {
        contains(.escapable)
    }
}

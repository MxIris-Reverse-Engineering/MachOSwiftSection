import Foundation
import SwiftStdlibToolbox

/// The invertible protocols a type or a generic parameter suppresses, one bit
/// per protocol.
///
/// Mirrors `swift::InvertibleProtocolSet` (`swift/ABI/InvertibleProtocols.h`),
/// whose kinds `swift/ABI/InvertibleProtocols.def` numbers.
@FlagSet
public struct InvertibleProtocolSet: Hashable, Sendable {
    public enum Flag: UInt16, CaseIterable, Sendable {
        case copyable = 0
        case escapable = 1
    }

    public var hasCopyable: Bool {
        contains(.copyable)
    }

    public var hasEscapable: Bool {
        contains(.escapable)
    }
}

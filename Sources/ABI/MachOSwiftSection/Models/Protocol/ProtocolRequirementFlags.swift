import SwiftStdlibToolbox

/// Mirrors `swift::ProtocolRequirementFlags` (`swift/ABI/MetadataValues.h`).
public struct ProtocolRequirementFlags: OptionSet, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let isInstance = ProtocolRequirementFlags(rawValue: 0x10)
    public static let maybeAsync = ProtocolRequirementFlags(rawValue: 0x20)

    /// The kind of requirement, or `nil` for a kind this reader does not
    /// know. Four bits hold it and nine values are defined so far.
    @BitField(bits: 0..<4)
    public var kind: ProtocolRequirementKind?

    /// Whether the requirement is a coroutine accessor. A kind this reader
    /// does not know is not taken for one.
    public var isCoroutine: Bool {
        switch kind {
        case .baseProtocol,
             .method,
             .`init`,
             .getter,
             .setter,
             .associatedTypeAccessFunction,
             .associatedConformanceAccessFunction,
             nil:
            return false
        case .readCoroutine,
             .modifyCoroutine:
            return true
        }
    }

    public var isAsync: Bool {
        return !isCoroutine && contains(.maybeAsync)
    }

    @BitField(bits: 4)
    public var isInstance: Bool
}

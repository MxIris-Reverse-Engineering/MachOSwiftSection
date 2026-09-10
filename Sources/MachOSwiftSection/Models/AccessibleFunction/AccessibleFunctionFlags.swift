/// Flags on an ``AccessibleFunctionRecord``.
///
/// Mirrors `swift::AccessibleFunctionFlags` (`swift/ABI/MetadataValues.h`),
/// which so far defines exactly one bit.
public struct AccessibleFunctionFlags: OptionSet, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    /// The record describes a `distributed` actor function, reached through a
    /// distributed actor system rather than by a direct call.
    public static let isDistributed = AccessibleFunctionFlags(rawValue: 1 << 0)
}

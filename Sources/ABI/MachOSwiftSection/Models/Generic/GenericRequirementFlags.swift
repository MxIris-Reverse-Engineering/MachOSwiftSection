import SwiftStdlibToolbox

/// Mirrors `swift::GenericRequirementFlags` (`swift/ABI/MetadataValues.h`).
public struct GenericRequirementFlags: OptionSet, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let isPackRequirement = GenericRequirementFlags(rawValue: 0x20)
    public static let hasKeyArgument = GenericRequirementFlags(rawValue: 0x80)
    public static let isValueRequirement = GenericRequirementFlags(rawValue: 0x100)

    /// The kind of requirement, or `nil` for a kind this reader does not
    /// know. Five bits hold it.
    @BitField(bits: 0..<5)
    public var kind: GenericRequirementKind?
}

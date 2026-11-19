import Foundation
import SwiftStdlibToolbox

/// Mirrors `swift::ProtocolContextDescriptorFlags`
/// (`swift/ABI/MetadataValues.h`).
public struct ProtocolContextDescriptorFlags: FlagSet {
    public let rawValue: UInt16

    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    @BitField(bits: 1)
    public var isResilient: Bool

    /// A single bit, both of whose values `ProtocolClassConstraint` names, so
    /// the default is never read.
    @BitField(bits: 0, default: ProtocolClassConstraint.any)
    public var classConstraint: ProtocolClassConstraint

    /// The special protocol this descriptor stands for, or `nil` for a value
    /// this reader does not know.
    @BitField(bits: 2..<8)
    public var specialProtocolKind: SpecialProtocolKind?
}

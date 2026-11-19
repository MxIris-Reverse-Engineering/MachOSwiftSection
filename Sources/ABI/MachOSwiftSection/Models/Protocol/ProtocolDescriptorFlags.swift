import SwiftStdlibToolbox

/// Mirrors `swift::ProtocolDescriptorFlags` (`swift/ABI/MetadataValues.h`).
/// The high 16 bits are reserved by the Objective-C runtime.
public struct ProtocolDescriptorFlags {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    @BitField(bits: 0)
    public var isSwift: Bool

    @BitField(bits: 10)
    public var isResilient: Bool

    /// Bit 1 is SET when the protocol is not class-constrained. A single bit,
    /// both of whose values `ProtocolClassConstraint` names, so the default is
    /// never read.
    @BitField(bits: 1, default: ProtocolClassConstraint.any)
    public var classConstraint: ProtocolClassConstraint

    /// How the protocol's requirements are dispatched, or `nil` for a
    /// strategy this reader does not know. Four bits hold it.
    @BitField(bits: 2..<6)
    public var dispatchStrategy: ProtocolDispatchStrategy?

    /// The special protocol this is, or `nil` for a value this reader does
    /// not know.
    @BitField(bits: 6..<10)
    public var specialProtocolKind: SpecialProtocolKind?

    /// Whether the protocol has a witness table. A dispatch strategy this
    /// reader does not know is not taken to have one.
    public var needsProtocolWitnessTable: Bool {
        switch dispatchStrategy {
        case .objc,
             nil:
            false
        case .swift:
            true
        }
    }
}

import Foundation
import MachOBase
import SwiftStdlibToolbox

/// Mirrors `swift::ExistentialTypeFlags` (`swift/ABI/MetadataValues.h`).
public struct ExistentialTypeFlags: OptionSet, Sendable {
    public typealias RawValue = UInt32
    public let rawValue: RawValue
    public init(rawValue: RawValue) {
        self.rawValue = rawValue
    }

    @BitField(bits: 0..<24)
    public var numberOfWitnessTables: RawValue

    /// Bit 31 is SET when the existential is not class-constrained — `Any`,
    /// or `any P` for a protocol that is not class-bound — so `.any` is the
    /// common case. A single bit, both of whose values
    /// `ProtocolClassConstraint` names, so the default is never read.
    @BitField(bits: 31, default: ProtocolClassConstraint.any)
    public var classConstraint: ProtocolClassConstraint

    @BitField(bits: 30)
    public var hasSuperclassConstraint: Bool

    /// The special protocol the existential stands for, or `nil` for a value
    /// this reader does not know.
    @BitField(bits: 24..<30)
    public var specialProtocol: SpecialProtocolKind?
}

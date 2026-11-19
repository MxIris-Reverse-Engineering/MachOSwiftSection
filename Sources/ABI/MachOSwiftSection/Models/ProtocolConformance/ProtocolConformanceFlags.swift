import Foundation
import SwiftStdlibToolbox

/// Flags that go in a TargetConformanceDescriptor structure.
///
/// Mirrors `swift::ConformanceFlags` (`swift/ABI/MetadataValues.h`). Bits
/// 0..<3 are the historical conformance kind and are not read.
public struct ProtocolConformanceFlags: RawRepresentable, Hashable, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    /// The kind of reference the conformance makes to its conforming type, or
    /// `nil` for a kind this reader does not know. Three bits hold it.
    @BitField(bits: 3..<6)
    public var typeReferenceKind: TypeReferenceKind?

    /// Is the conformance "retroactive"?
    ///
    /// A conformance is retroactive when it occurs in a module that is
    /// neither the module in which the protocol is defined nor the module
    /// in which the conforming type is defined. With retroactive conformance,
    /// it is possible to detect a conflict at run time.
    @BitField(bits: 6)
    public var isRetroactive: Bool

    /// Is the conformance synthesized in a non-unique manner?
    ///
    /// The Swift compiler will synthesize conformances on behalf of some
    /// imported entities (e.g., C typedefs with the swift_wrapper attribute).
    /// Such conformances are retroactive by nature, but the presence of multiple
    /// such conformances is not a conflict because all synthesized conformances
    /// will be equivalent.
    @BitField(bits: 7)
    public var isSynthesizedNonUnique: Bool

    /// Is this a conformance of a protocol to another protocol?
    ///
    /// The Swift compiler can synthesize a conformance of one protocol to
    /// another, meaning that every type that conforms to the first protocol
    /// can also produce a witness table conforming to the second. Such
    /// conformances cannot generally be written in the surface language, but
    /// can be made available for specific tasks. The only such instance at the
    /// time of this writing is that a (local) distributed actor can conform to
    /// a local actor, but the witness table can only be used via a specific
    /// builtin to form an existential.
    @BitField(bits: 18)
    public var isConformanceOfProtocol: Bool

    /// Does this conformance have a global actor to which it is isolated?
    @BitField(bits: 19)
    public var hasGlobalActorIsolation: Bool

    /// Bit 20, which marked a `SerialExecutor` conformance with its own
    /// `isIsolatingCurrentContext`. It existed on the Swift main branch for a
    /// few weeks in 2025 and is in no released compiler's headers — 6.1
    /// through 6.3 lack it — so it reads `false` on any binary a release
    /// produced.
    @BitField(bits: 20)
    public var hasNonDefaultSerialExecutorIsIsolatingCurrentContext: Bool

    /// Whether this conformance has any resilient witnesses.
    @BitField(bits: 16)
    public var hasResilientWitnesses: Bool

    /// Whether this conformance has a generic witness table that may need to
    /// be instantiated.
    @BitField(bits: 17)
    public var hasGenericWitnessTable: Bool

    /// Retrieve the # of conditional requirements.
    @BitField(bits: 8..<16)
    public var numConditionalRequirements: UInt32

    /// Retrieve the # of conditional pack shape descriptors.
    @BitField(bits: 24..<32)
    public var numConditionalPackShapeDescriptors: UInt32
}

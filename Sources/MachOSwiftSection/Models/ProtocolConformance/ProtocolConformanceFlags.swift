import Foundation

/// Flags that go in a TargetConformanceDescriptor structure.
public struct ProtocolConformanceFlags: RawRepresentable {
    public let rawValue: UInt32
    
    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }
    
    // historical conformance kind
    private static let unusedLowBits: UInt32 = 0x07

    // 8 type reference kinds
    private static let typeMetadataKindMask: UInt32 = 0x07 << 3
    private static let typeMetadataKindShift: UInt32 = 3

    private static let isRetroactiveMask: UInt32 = 0x01 << 6
    private static let isSynthesizedNonUniqueMask: UInt32 = 0x01 << 7

    private static let numConditionalRequirementsMask: UInt32 = 0xFF << 8
    private static let numConditionalRequirementsShift: UInt32 = 8

    private static let hasResilientWitnessesMask: UInt32 = 0x01 << 16
    private static let hasGenericWitnessTableMask: UInt32 = 0x01 << 17
    private static let isConformanceOfProtocolMask: UInt32 = 0x01 << 18
    private static let hasGlobalActorIsolation: UInt32 = 0x01 << 19

    // Used to detect if this is a conformance to SerialExecutor that has
    // an user defined implementation of 'isIsolatingCurrentContext'. This
    // requirement is special in the sense that if a non-default impl is present
    // we will avoid calling the `checkIsolated` method which would lead to a
    // crash. In other words, this API "soft replaces" 'checkIsolated' so we
    // must at runtime the presence of a non-default implementation.
    private static let hasNonDefaultSerialExecutorIsIsolatingCurrentContext: UInt32 = 0x01 << 20

    private static let numConditionalPackDescriptorsMask: UInt32 = 0xFF << 24
    private static let numConditionalPackDescriptorsShift: UInt32 = 24

    /// Retrieve the type reference kind kind.
    public var typeReferenceKind: TypeReferenceKind {
        return TypeReferenceKind(rawValue: numericCast((rawValue & Self.typeMetadataKindMask) >> Self.typeMetadataKindShift))!
    }

    /// Is the conformance "retroactive"?
    ///
    /// A conformance is retroactive when it occurs in a module that is
    /// neither the module in which the protocol is defined nor the module
    /// in which the conforming type is defined. With retroactive conformance,
    /// it is possible to detect a conflict at run time.
    public var isRetroactive: Bool {
        return (rawValue & Self.isRetroactiveMask) != 0
    }

    /// Is the conformance synthesized in a non-unique manner?
    ///
    /// The Swift compiler will synthesize conformances on behalf of some
    /// imported entities (e.g., C typedefs with the swift_wrapper attribute).
    /// Such conformances are retroactive by nature, but the presence of multiple
    /// such conformances is not a conflict because all synthesized conformances
    /// will be equivalent.
    public var isSynthesizedNonUnique: Bool {
        return (rawValue & Self.isSynthesizedNonUniqueMask) != 0
    }

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
    public var isConformanceOfProtocol: Bool {
        return (rawValue & Self.isConformanceOfProtocolMask) != 0
    }

    /// Does this conformance have a global actor to which it is isolated?
    public var hasGlobalActorIsolation: Bool {
        return (rawValue & Self.hasGlobalActorIsolation) != 0
    }

    public var hasNonDefaultSerialExecutorIsIsolatingCurrentContext: Bool {
        return (rawValue & Self.hasNonDefaultSerialExecutorIsIsolatingCurrentContext) != 0
    }

    /// Whether this conformance has any resilient witnesses.
    public var hasResilientWitnesses: Bool {
        return (rawValue & Self.hasResilientWitnessesMask) != 0
    }

    /// Whether this conformance has a generic witness table that may need to
    /// be instantiated.
    public var hasGenericWitnessTable: Bool {
        return (rawValue & Self.hasGenericWitnessTableMask) != 0
    }

    /// Retrieve the # of conditional requirements.
    public var numConditionalRequirements: UInt32 {
        return (rawValue & Self.numConditionalRequirementsMask) >> Self.numConditionalRequirementsShift
    }

    /// Retrieve the # of conditional pack shape descriptors.
    public var numConditionalPackShapeDescriptors: UInt32 {
        return (rawValue & Self.numConditionalPackDescriptorsMask) >> Self.numConditionalPackDescriptorsShift
    }
}

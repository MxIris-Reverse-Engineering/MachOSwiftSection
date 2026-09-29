import Foundation

/// The 4-byte header word shared by every key path component and by every
/// property descriptor.
///
/// A property descriptor's whole content is one serialized key path
/// component: this header, optionally followed by a body whose length depends
/// on the header (`propertyDescriptorBodySize`). A header word of exactly
/// zero is the *trivial* property descriptor marker, which means the
/// descriptor overrides nothing and an external module should use the
/// component it formed locally.
///
/// Mirrors the `_SwiftKeyPathComponentHeader_*` constants in
/// `swift/shims/KeyPath.h`; the body-size rules are ported from
/// `RawKeyPathComponent.Header._componentBodySize(forPropertyDescriptor:)` in
/// the standard library's `KeyPath.swift`.
public struct KeyPathComponentHeader: RawRepresentable, Hashable, Sendable {
    public typealias RawValue = UInt32

    public let rawValue: RawValue

    public init(rawValue: RawValue) {
        self.rawValue = rawValue
    }

    private static let payloadMask: RawValue = 0x00FF_FFFF
    private static let discriminatorMask: RawValue = 0x7F00_0000
    private static let discriminatorShift: RawValue = 24

    private static let trivialPropertyDescriptorMarker: RawValue = 0

    private static let storedOffsetPayloadMask: RawValue = 0x007F_FFFF
    private static let maximumOffsetPayload: RawValue = 0x007F_FFFC
    private static let unresolvedIndirectOffsetPayload: RawValue = 0x007F_FFFD
    private static let unresolvedFieldOffsetPayload: RawValue = 0x007F_FFFE
    private static let outOfLineOffsetPayload: RawValue = 0x007F_FFFF
    private static let storedMutableFlag: RawValue = 0x0080_0000

    private static let endOfReferencePrefixFlag: RawValue = 0x8000_0000

    private static let computedMutatingFlag: RawValue = 0x0080_0000
    private static let computedSettableFlag: RawValue = 0x0040_0000
    private static let computedIdentifierByStoredPropertyFlag: RawValue = 0x0020_0000
    private static let computedIdentifierByVTableOffsetFlag: RawValue = 0x0010_0000
    private static let computedHasArgumentsFlag: RawValue = 0x0008_0000
    private static let computedIdentifierResolutionMask: RawValue = 0x0000_000F
}

// MARK: - Kind

extension KeyPathComponentHeader {
    /// The raw discriminator, 7 bits wide. Only values 0...4 are defined.
    public var rawKind: RawValue {
        (rawValue & Self.discriminatorMask) >> Self.discriminatorShift
    }

    /// The component's kind, or `nil` when the discriminator is not one the
    /// runtime defines. Unlike `MethodDescriptorFlags.kind` this cannot force
    /// unwrap: the field is wider than the set of valid values, and the input
    /// is arbitrary binary content.
    public var kind: KeyPathComponentKind? {
        KeyPathComponentKind(rawValue: rawKind)
    }

    /// The low 24 bits, whose meaning depends on the kind.
    public var payload: RawValue {
        rawValue & Self.payloadMask
    }

    /// Whether this header is the trivial property-descriptor marker (the
    /// whole word is zero). Such a descriptor has no body, and a client
    /// forming a key path keeps the component it built locally.
    ///
    /// Note this is only meaningful for a property descriptor. Inside a key
    /// path pattern a zero word is a perfectly ordinary `external` component
    /// with no substitution arguments.
    public var isTrivialPropertyDescriptor: Bool {
        rawValue == Self.trivialPropertyDescriptorMarker
    }

    /// Set on the last component of a key path's reference prefix — the
    /// longest leading run of components that can be resolved to a mutable
    /// address. Only ever set inside a key path pattern.
    public var isEndOfReferencePrefix: Bool {
        rawValue & Self.endOfReferencePrefixFlag != 0
    }
}

// MARK: - Stored components

extension KeyPathComponentHeader {
    /// The low 23 bits of a `struct` / `class` component, before the sentinel
    /// values are interpreted.
    public var storedOffsetPayload: RawValue {
        rawValue & Self.storedOffsetPayloadMask
    }

    /// Whether the stored property is mutable through the key path.
    public var isStoredMutable: Bool {
        rawValue & Self.storedMutableFlag != 0
    }

    /// How to obtain the stored property's offset, without yet reading the
    /// body. `nil` when the component is not a stored one.
    ///
    /// The three sentinel payloads each mean "the body carries a 32-bit
    /// word"; what that word is differs, which is why they stay distinct.
    public var storedFieldOffsetKind: KeyPathStoredFieldOffsetKind? {
        switch kind {
        case .struct, .class:
            break
        default:
            return nil
        }
        switch storedOffsetPayload {
        case Self.outOfLineOffsetPayload:
            return .outOfLine
        case Self.unresolvedFieldOffsetPayload:
            return .unresolvedFieldOffset
        case Self.unresolvedIndirectOffsetPayload:
            return .unresolvedIndirectOffset
        default:
            return .inline
        }
    }

    /// The offset itself when it is small enough to sit in the header, `nil`
    /// when the component is not stored or the body carries the offset.
    ///
    /// Offsets up to `maximumOffsetPayload` are inline; the three values above
    /// it are sentinels.
    public var inlineStoredFieldOffset: RawValue? {
        guard storedFieldOffsetKind == .inline else { return nil }
        return storedOffsetPayload
    }
}

// MARK: - Computed components

extension KeyPathComponentHeader {
    /// Whether the computed property has a setter, which is what decides
    /// whether the body carries a third word.
    public var isComputedSettable: Bool {
        rawValue & Self.computedSettableFlag != 0
    }

    /// Whether the computed property's setter is mutating.
    public var isComputedMutating: Bool {
        rawValue & Self.computedMutatingFlag != 0
    }

    /// Whether the component carries subscript arguments. A property
    /// descriptor never does — the arguments come from the client's own
    /// pattern — so this only ever matters when walking a key path pattern.
    public var hasComputedArguments: Bool {
        rawValue & Self.computedHasArgumentsFlag != 0
    }

    /// What the body's identifier word means.
    public var computedIdentifierKind: KeyPathComputedIdentifierKind {
        if rawValue & Self.computedIdentifierByStoredPropertyFlag != 0 {
            return .storedPropertyOffset
        }
        if rawValue & Self.computedIdentifierByVTableOffsetFlag != 0 {
            return .vtableOffset
        }
        return .pointer
    }

    /// How a pointer-kind identifier reaches the identity value, or `nil`
    /// when the 4-bit field holds a value the runtime does not define.
    public var computedIdentifierResolution: KeyPathComputedIdentifierResolution? {
        KeyPathComputedIdentifierResolution(rawValue: rawValue & Self.computedIdentifierResolutionMask)
    }
}

// MARK: - Optional components

extension KeyPathComponentHeader {
    /// Which optional operation the component performs, `nil` when it is not
    /// an `optional` component or the payload is undefined.
    public var optionalComponentKind: KeyPathOptionalComponentKind? {
        guard kind == .optional else { return nil }
        return KeyPathOptionalComponentKind(rawValue: payload)
    }
}

// MARK: - Body size

extension KeyPathComponentHeader {
    /// Size in bytes of the body following this header when it heads a
    /// **property descriptor**.
    ///
    /// The trivial marker has no body, and a property descriptor never
    /// carries subscript arguments even when its component is a subscript's.
    public var propertyDescriptorBodySize: Int {
        guard !isTrivialPropertyDescriptor else { return 0 }
        return bodySize(forPropertyDescriptor: true)
    }

    /// Size in bytes of the body following this header when it heads a
    /// component inside a **key path pattern**.
    public var patternComponentBodySize: Int {
        bodySize(forPropertyDescriptor: false)
    }

    private func bodySize(forPropertyDescriptor: Bool) -> Int {
        switch kind {
        case .struct, .class:
            // Only the sentinel payloads push the offset into the body.
            return storedFieldOffsetKind == .inline ? 0 : MemoryLayout<UInt32>.size

        case .external:
            // A relative pointer to the external property descriptor,
            // followed by `payload` substitution arguments.
            return MemoryLayout<UInt32>.size * (1 + Int(payload))

        case .computed:
            // The identifier and the getter, at minimum.
            var size = MemoryLayout<UInt32>.size * 2
            if isComputedSettable {
                size += MemoryLayout<UInt32>.size
            }
            // A layout function, a witness table and an initializer follow
            // when there are arguments — never for a property descriptor.
            if !forPropertyDescriptor, hasComputedArguments {
                size += MemoryLayout<UInt32>.size * 3
            }
            return size

        case .optional:
            return 0

        case nil:
            // An undefined discriminator: refuse to guess a length.
            return 0
        }
    }
}

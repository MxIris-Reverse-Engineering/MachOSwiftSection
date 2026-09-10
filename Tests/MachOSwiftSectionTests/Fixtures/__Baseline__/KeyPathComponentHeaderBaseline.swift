// AUTO-GENERATED — DO NOT EDIT.
// Regenerate via: Scripts/regen-baselines.sh
// Source fixture: SymbolTestsCore.framework
//
// Every derived accessor of the four fixture descriptors' header
// words. Pure bit arithmetic, so identical across readers.

enum KeyPathComponentHeaderBaseline {
    static let registeredTestMethodNames: Set<String> = ["computedIdentifierKind", "computedIdentifierResolution", "hasComputedArguments", "init(rawValue:)", "inlineStoredFieldOffset", "isComputedMutating", "isComputedSettable", "isEndOfReferencePrefix", "isStoredMutable", "isTrivialPropertyDescriptor", "kind", "optionalComponentKind", "patternComponentBodySize", "payload", "propertyDescriptorBodySize", "rawKind", "rawValue", "storedFieldOffsetKind", "storedOffsetPayload"]

    struct Entry {
        let rawValue: UInt32
        let rawKind: UInt32
        let kindDescription: String
        let payload: UInt32
        let isTrivialPropertyDescriptor: Bool
        let isEndOfReferencePrefix: Bool
        let storedOffsetPayload: UInt32
        let isStoredMutable: Bool
        let storedFieldOffsetKindDescription: String
        let inlineStoredFieldOffset: UInt32?
        let isComputedSettable: Bool
        let isComputedMutating: Bool
        let hasComputedArguments: Bool
        let computedIdentifierKindDescription: String
        let computedIdentifierResolutionRawValue: UInt32?
        let optionalComponentKindDescription: String
        let propertyDescriptorBodySize: Int
        let patternComponentBodySize: Int
    }

    static let trivial = Entry(
    rawValue: 0x0,
    rawKind: 0,
    kindDescription: "Optional(MachOSwiftSection.KeyPathComponentKind.external)",
    payload: 0x0,
    isTrivialPropertyDescriptor: true,
    isEndOfReferencePrefix: false,
    storedOffsetPayload: 0x0,
    isStoredMutable: false,
    storedFieldOffsetKindDescription: "nil",
    inlineStoredFieldOffset: nil,
    isComputedSettable: false,
    isComputedMutating: false,
    hasComputedArguments: false,
    computedIdentifierKindDescription: "pointer",
    computedIdentifierResolutionRawValue: 0x0,
    optionalComponentKindDescription: "nil",
    propertyDescriptorBodySize: 0,
    patternComponentBodySize: 4
    )

    static let inlineStoredOffset = Entry(
    rawValue: 0x1800000,
    rawKind: 1,
    kindDescription: "Optional(MachOSwiftSection.KeyPathComponentKind.struct)",
    payload: 0x800000,
    isTrivialPropertyDescriptor: false,
    isEndOfReferencePrefix: false,
    storedOffsetPayload: 0x0,
    isStoredMutable: true,
    storedFieldOffsetKindDescription: "Optional(MachOSwiftSection.KeyPathStoredFieldOffsetKind.inline)",
    inlineStoredFieldOffset: 0x0,
    isComputedSettable: false,
    isComputedMutating: true,
    hasComputedArguments: false,
    computedIdentifierKindDescription: "pointer",
    computedIdentifierResolutionRawValue: 0x0,
    optionalComponentKindDescription: "nil",
    propertyDescriptorBodySize: 0,
    patternComponentBodySize: 0
    )

    static let unresolvedFieldOffset = Entry(
    rawValue: 0x1fffffe,
    rawKind: 1,
    kindDescription: "Optional(MachOSwiftSection.KeyPathComponentKind.struct)",
    payload: 0xfffffe,
    isTrivialPropertyDescriptor: false,
    isEndOfReferencePrefix: false,
    storedOffsetPayload: 0x7ffffe,
    isStoredMutable: true,
    storedFieldOffsetKindDescription: "Optional(MachOSwiftSection.KeyPathStoredFieldOffsetKind.unresolvedFieldOffset)",
    inlineStoredFieldOffset: nil,
    isComputedSettable: true,
    isComputedMutating: true,
    hasComputedArguments: true,
    computedIdentifierKindDescription: "storedPropertyOffset",
    computedIdentifierResolutionRawValue: nil,
    optionalComponentKindDescription: "nil",
    propertyDescriptorBodySize: 4,
    patternComponentBodySize: 4
    )

    static let computedSettable = Entry(
    rawValue: 0x2400000,
    rawKind: 2,
    kindDescription: "Optional(MachOSwiftSection.KeyPathComponentKind.computed)",
    payload: 0x400000,
    isTrivialPropertyDescriptor: false,
    isEndOfReferencePrefix: false,
    storedOffsetPayload: 0x400000,
    isStoredMutable: false,
    storedFieldOffsetKindDescription: "nil",
    inlineStoredFieldOffset: nil,
    isComputedSettable: true,
    isComputedMutating: false,
    hasComputedArguments: false,
    computedIdentifierKindDescription: "pointer",
    computedIdentifierResolutionRawValue: 0x0,
    optionalComponentKindDescription: "nil",
    propertyDescriptorBodySize: 12,
    patternComponentBodySize: 12
    )

    /// An `optional` chain component. No property descriptor can carry
    /// one, so it is synthesized from the encoding the runtime defines.
    static let synthesizedOptionalChain = Entry(
    rawValue: 0x4000000,
    rawKind: 4,
    kindDescription: "Optional(MachOSwiftSection.KeyPathComponentKind.optional)",
    payload: 0x0,
    isTrivialPropertyDescriptor: false,
    isEndOfReferencePrefix: false,
    storedOffsetPayload: 0x0,
    isStoredMutable: false,
    storedFieldOffsetKindDescription: "nil",
    inlineStoredFieldOffset: nil,
    isComputedSettable: false,
    isComputedMutating: false,
    hasComputedArguments: false,
    computedIdentifierKindDescription: "pointer",
    computedIdentifierResolutionRawValue: 0x0,
    optionalComponentKindDescription: "Optional(MachOSwiftSection.KeyPathOptionalComponentKind.chain)",
    propertyDescriptorBodySize: 0,
    patternComponentBodySize: 0
    )

    /// An `external` component with two substitution arguments, also
    /// synthesized: `4 * (1 + 2)` bytes of body.
    static let synthesizedExternalWithTwoArguments = Entry(
    rawValue: 0x2,
    rawKind: 0,
    kindDescription: "Optional(MachOSwiftSection.KeyPathComponentKind.external)",
    payload: 0x2,
    isTrivialPropertyDescriptor: false,
    isEndOfReferencePrefix: false,
    storedOffsetPayload: 0x2,
    isStoredMutable: false,
    storedFieldOffsetKindDescription: "nil",
    inlineStoredFieldOffset: nil,
    isComputedSettable: false,
    isComputedMutating: false,
    hasComputedArguments: false,
    computedIdentifierKindDescription: "pointer",
    computedIdentifierResolutionRawValue: 0x2,
    optionalComponentKindDescription: "nil",
    propertyDescriptorBodySize: 12,
    patternComponentBodySize: 12
    )

    /// A stored component flagged as the end of a reference prefix,
    /// synthesized: the flag only ever appears inside a pattern.
    static let synthesizedEndOfReferencePrefix = Entry(
    rawValue: 0x81800010,
    rawKind: 1,
    kindDescription: "Optional(MachOSwiftSection.KeyPathComponentKind.struct)",
    payload: 0x800010,
    isTrivialPropertyDescriptor: false,
    isEndOfReferencePrefix: true,
    storedOffsetPayload: 0x10,
    isStoredMutable: true,
    storedFieldOffsetKindDescription: "Optional(MachOSwiftSection.KeyPathStoredFieldOffsetKind.inline)",
    inlineStoredFieldOffset: 0x10,
    isComputedSettable: false,
    isComputedMutating: true,
    hasComputedArguments: false,
    computedIdentifierKindDescription: "pointer",
    computedIdentifierResolutionRawValue: 0x0,
    optionalComponentKindDescription: "nil",
    propertyDescriptorBodySize: 0,
    patternComponentBodySize: 0
    )
}

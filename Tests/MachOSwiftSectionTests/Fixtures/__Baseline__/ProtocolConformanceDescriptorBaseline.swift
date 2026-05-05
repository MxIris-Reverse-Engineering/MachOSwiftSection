// AUTO-GENERATED — DO NOT EDIT.
// Regenerate via: Scripts/regen-baselines.sh
// Source fixture: SymbolTestsCore.framework

enum ProtocolConformanceDescriptorBaseline {
    static let registeredTestMethodNames: Set<String> = ["layout", "offset", "protocolDescriptor", "resolvedTypeReference", "typeReference", "witnessTablePattern"]

    struct Entry {
        let offset: Int
        let layoutFlagsRawValue: UInt32
        let typeReferenceKindRawValue: UInt8
        let hasProtocolDescriptor: Bool
        let hasWitnessTablePattern: Bool
        let resolvedTypeReferenceIsDirectTypeDescriptor: Bool
    }

    static let structTestProtocolTest = Entry(
    offset: 0x2f120,
    layoutFlagsRawValue: 0x20000,
    typeReferenceKindRawValue: 0x0,
    hasProtocolDescriptor: true,
    hasWitnessTablePattern: true,
    resolvedTypeReferenceIsDirectTypeDescriptor: true
    )
}

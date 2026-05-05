// AUTO-GENERATED — DO NOT EDIT.
// Regenerate via: Scripts/regen-baselines.sh
// Source fixture: SymbolTestsCore.framework
//
// Live FieldDescriptor / GenericContext / MetadataAccessorFunction
// payloads aren't embedded as literals; the companion Suite
// (TypeContextDescriptorProtocolTests) verifies the methods produce
// cross-reader-consistent results at runtime against the presence
// flags recorded here.

enum TypeContextDescriptorProtocolBaseline {
    static let registeredTestMethodNames: Set<String> = ["fieldDescriptor", "genericContext", "hasCanonicalMetadataPrespecializations", "hasCanonicalMetadataPrespecializationsOrSingletonMetadataPointer", "hasForeignMetadataInitialization", "hasImportInfo", "hasLayoutString", "hasSingletonMetadataInitialization", "hasSingletonMetadataPointer", "metadataAccessorFunction", "typeGenericContext"]

    struct Entry {
        let hasFieldDescriptor: Bool
        let hasGenericContext: Bool
        let hasTypeGenericContext: Bool
        let hasSingletonMetadataInitialization: Bool
        let hasForeignMetadataInitialization: Bool
        let hasImportInfo: Bool
        let hasCanonicalMetadataPrespecializationsOrSingletonMetadataPointer: Bool
        let hasLayoutString: Bool
        let hasCanonicalMetadataPrespecializations: Bool
        let hasSingletonMetadataPointer: Bool
    }

    static let structTest = Entry(
    hasFieldDescriptor: true,
    hasGenericContext: false,
    hasTypeGenericContext: false,
    hasSingletonMetadataInitialization: false,
    hasForeignMetadataInitialization: false,
    hasImportInfo: false,
    hasCanonicalMetadataPrespecializationsOrSingletonMetadataPointer: false,
    hasLayoutString: false,
    hasCanonicalMetadataPrespecializations: false,
    hasSingletonMetadataPointer: false
    )
}

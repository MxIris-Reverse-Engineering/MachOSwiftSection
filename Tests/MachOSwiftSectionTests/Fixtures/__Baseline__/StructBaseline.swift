// AUTO-GENERATED — DO NOT EDIT.
// Regenerate via: Scripts/regen-baselines.sh
// Source fixture: SymbolTestsCore.framework

enum StructBaseline {
    static let registeredTestMethodNames: Set<String> = ["canonicalSpecializedMetadatas", "canonicalSpecializedMetadatasCachingOnceToken", "canonicalSpecializedMetadatasListCount", "descriptor", "foreignMetadataInitialization", "genericContext", "init(descriptor:)", "init(descriptor:in:)", "invertibleProtocolSet", "singletonMetadataInitialization", "singletonMetadataPointer"]

    struct Entry {
        let descriptorOffset: Int
        let hasGenericContext: Bool
        let hasForeignMetadataInitialization: Bool
        let hasSingletonMetadataInitialization: Bool
        let canonicalSpecializedMetadatasCount: Int
        let hasCanonicalSpecializedMetadatasListCount: Bool
        let hasCanonicalSpecializedMetadatasCachingOnceToken: Bool
        let hasInvertibleProtocolSet: Bool
        let hasSingletonMetadataPointer: Bool
    }

    static let structTest = Entry(
    descriptorOffset: 0x36b50,
    hasGenericContext: false,
    hasForeignMetadataInitialization: false,
    hasSingletonMetadataInitialization: false,
    canonicalSpecializedMetadatasCount: 0,
    hasCanonicalSpecializedMetadatasListCount: false,
    hasCanonicalSpecializedMetadatasCachingOnceToken: false,
    hasInvertibleProtocolSet: false,
    hasSingletonMetadataPointer: false
    )

    static let genericStructNonRequirement = Entry(
    descriptorOffset: 0x34e94,
    hasGenericContext: true,
    hasForeignMetadataInitialization: false,
    hasSingletonMetadataInitialization: false,
    canonicalSpecializedMetadatasCount: 0,
    hasCanonicalSpecializedMetadatasListCount: false,
    hasCanonicalSpecializedMetadatasCachingOnceToken: false,
    hasInvertibleProtocolSet: false,
    hasSingletonMetadataPointer: false
    )
}

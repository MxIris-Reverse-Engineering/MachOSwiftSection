// AUTO-GENERATED — DO NOT EDIT.
// Regenerate via: Scripts/regen-baselines.sh
// Source fixture: SymbolTestsCore.framework

enum ClassBaseline {
    static let registeredTestMethodNames: Set<String> = ["canonicalSpecializedMetadataAccessors", "canonicalSpecializedMetadatas", "canonicalSpecializedMetadatasCachingOnceToken", "canonicalSpecializedMetadatasListCount", "descriptor", "foreignMetadataInitialization", "genericContext", "init(descriptor:)", "init(descriptor:in:)", "invertibleProtocolSet", "methodDefaultOverrideDescriptors", "methodDefaultOverrideTableHeader", "methodDescriptors", "methodOverrideDescriptors", "objcResilientClassStubInfo", "overrideTableHeader", "resilientSuperclass", "singletonMetadataInitialization", "singletonMetadataPointer", "vTableDescriptorHeader"]

    struct Entry {
        let descriptorOffset: Int
        let hasGenericContext: Bool
        let hasResilientSuperclass: Bool
        let hasForeignMetadataInitialization: Bool
        let hasSingletonMetadataInitialization: Bool
        let hasVTableDescriptorHeader: Bool
        let methodDescriptorsCount: Int
        let hasOverrideTableHeader: Bool
        let methodOverrideDescriptorsCount: Int
        let hasObjCResilientClassStubInfo: Bool
        let hasCanonicalSpecializedMetadatasListCount: Bool
        let canonicalSpecializedMetadatasCount: Int
        let canonicalSpecializedMetadataAccessorsCount: Int
        let hasCanonicalSpecializedMetadatasCachingOnceToken: Bool
        let hasInvertibleProtocolSet: Bool
        let hasSingletonMetadataPointer: Bool
        let hasMethodDefaultOverrideTableHeader: Bool
        let methodDefaultOverrideDescriptorsCount: Int
    }

    static let classTest = Entry(
    descriptorOffset: 0x338d0,
    hasGenericContext: false,
    hasResilientSuperclass: false,
    hasForeignMetadataInitialization: false,
    hasSingletonMetadataInitialization: false,
    hasVTableDescriptorHeader: true,
    methodDescriptorsCount: 9,
    hasOverrideTableHeader: false,
    methodOverrideDescriptorsCount: 0,
    hasObjCResilientClassStubInfo: false,
    hasCanonicalSpecializedMetadatasListCount: false,
    canonicalSpecializedMetadatasCount: 0,
    canonicalSpecializedMetadataAccessorsCount: 0,
    hasCanonicalSpecializedMetadatasCachingOnceToken: false,
    hasInvertibleProtocolSet: false,
    hasSingletonMetadataPointer: false,
    hasMethodDefaultOverrideTableHeader: false,
    methodDefaultOverrideDescriptorsCount: 0
    )

    static let subclassTest = Entry(
    descriptorOffset: 0x3394c,
    hasGenericContext: false,
    hasResilientSuperclass: false,
    hasForeignMetadataInitialization: false,
    hasSingletonMetadataInitialization: false,
    hasVTableDescriptorHeader: false,
    methodDescriptorsCount: 0,
    hasOverrideTableHeader: true,
    methodOverrideDescriptorsCount: 9,
    hasObjCResilientClassStubInfo: false,
    hasCanonicalSpecializedMetadatasListCount: false,
    canonicalSpecializedMetadatasCount: 0,
    canonicalSpecializedMetadataAccessorsCount: 0,
    hasCanonicalSpecializedMetadatasCachingOnceToken: false,
    hasInvertibleProtocolSet: false,
    hasSingletonMetadataPointer: false,
    hasMethodDefaultOverrideTableHeader: false,
    methodDefaultOverrideDescriptorsCount: 0
    )
}

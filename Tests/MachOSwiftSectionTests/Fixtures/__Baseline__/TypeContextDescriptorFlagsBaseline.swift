// AUTO-GENERATED — DO NOT EDIT.
// Regenerate via: Scripts/regen-baselines.sh
// Source fixture: SymbolTestsCore.framework

enum TypeContextDescriptorFlagsBaseline {
    static let registeredTestMethodNames: Set<String> = ["classAreImmdiateMembersNegative", "classHasDefaultOverrideTable", "classHasOverrideTable", "classHasResilientSuperclass", "classHasVTable", "classIsActor", "classIsDefaultActor", "classResilientSuperclassReferenceKind", "hasCanonicalMetadataPrespecializationsOrSingletonMetadataPointer", "hasForeignMetadataInitialization", "hasImportInfo", "hasLayoutString", "hasSingletonMetadataInitialization", "init(rawValue:)", "noMetadataInitialization", "rawValue"]

    struct Entry {
        let rawValue: UInt16
        let noMetadataInitialization: Bool
        let hasSingletonMetadataInitialization: Bool
        let hasForeignMetadataInitialization: Bool
        let hasImportInfo: Bool
        let hasCanonicalMetadataPrespecializationsOrSingletonMetadataPointer: Bool
        let hasLayoutString: Bool
        let classHasDefaultOverrideTable: Bool
        let classIsActor: Bool
        let classIsDefaultActor: Bool
        let classResilientSuperclassReferenceKindRawValue: UInt8
        let classAreImmdiateMembersNegative: Bool
        let classHasResilientSuperclass: Bool
        let classHasOverrideTable: Bool
        let classHasVTable: Bool
    }

    static let structTest = Entry(
    rawValue: 0x0,
    noMetadataInitialization: true,
    hasSingletonMetadataInitialization: false,
    hasForeignMetadataInitialization: false,
    hasImportInfo: false,
    hasCanonicalMetadataPrespecializationsOrSingletonMetadataPointer: false,
    hasLayoutString: false,
    classHasDefaultOverrideTable: false,
    classIsActor: false,
    classIsDefaultActor: false,
    classResilientSuperclassReferenceKindRawValue: 0x0,
    classAreImmdiateMembersNegative: false,
    classHasResilientSuperclass: false,
    classHasOverrideTable: false,
    classHasVTable: false
    )

    static let classTest = Entry(
    rawValue: 0x8000,
    noMetadataInitialization: true,
    hasSingletonMetadataInitialization: false,
    hasForeignMetadataInitialization: false,
    hasImportInfo: false,
    hasCanonicalMetadataPrespecializationsOrSingletonMetadataPointer: false,
    hasLayoutString: false,
    classHasDefaultOverrideTable: false,
    classIsActor: false,
    classIsDefaultActor: false,
    classResilientSuperclassReferenceKindRawValue: 0x0,
    classAreImmdiateMembersNegative: false,
    classHasResilientSuperclass: false,
    classHasOverrideTable: false,
    classHasVTable: true
    )
}

// AUTO-GENERATED — DO NOT EDIT.
// Regenerate via: Scripts/regen-baselines.sh
// Source fixture: SymbolTestsCore.framework

enum ClassDescriptorBaseline {
    static let registeredTestMethodNames: Set<String> = ["areImmediateMembersNegative", "hasDefaultOverrideTable", "hasFieldOffsetVector", "hasObjCResilientClassStub", "hasOverrideTable", "hasResilientSuperclass", "hasVTable", "immediateMemberSize", "isActor", "isDefaultActor", "layout", "nonResilientImmediateMembersOffset", "offset", "resilientMetadataBounds", "resilientSuperclassReferenceKind", "superclassTypeMangledName"]

    struct Entry {
        let offset: Int
        let layoutNumFields: Int
        let layoutFieldOffsetVectorOffset: Int
        let layoutNumImmediateMembers: Int
        let layoutFlagsRawValue: UInt32
        let hasFieldOffsetVector: Bool
        let hasDefaultOverrideTable: Bool
        let isActor: Bool
        let isDefaultActor: Bool
        let hasVTable: Bool
        let hasOverrideTable: Bool
        let hasResilientSuperclass: Bool
        let areImmediateMembersNegative: Bool
        let hasObjCResilientClassStub: Bool
        let hasSuperclassTypeMangledName: Bool
        let immediateMemberSize: UInt
        let nonResilientImmediateMembersOffset: Int32
    }

    static let classTest = Entry(
    offset: 0x33860,
    layoutNumFields: 0,
    layoutFieldOffsetVectorOffset: 10,
    layoutNumImmediateMembers: 9,
    layoutFlagsRawValue: 0x80000050,
    hasFieldOffsetVector: true,
    hasDefaultOverrideTable: false,
    isActor: false,
    isDefaultActor: false,
    hasVTable: true,
    hasOverrideTable: false,
    hasResilientSuperclass: false,
    areImmediateMembersNegative: false,
    hasObjCResilientClassStub: false,
    hasSuperclassTypeMangledName: false,
    immediateMemberSize: 0x48,
    nonResilientImmediateMembersOffset: 10
    )

    static let subclassTest = Entry(
    offset: 0x338dc,
    layoutNumFields: 0,
    layoutFieldOffsetVectorOffset: 19,
    layoutNumImmediateMembers: 0,
    layoutFlagsRawValue: 0x40000050,
    hasFieldOffsetVector: true,
    hasDefaultOverrideTable: false,
    isActor: false,
    isDefaultActor: false,
    hasVTable: false,
    hasOverrideTable: true,
    hasResilientSuperclass: false,
    areImmediateMembersNegative: false,
    hasObjCResilientClassStub: false,
    hasSuperclassTypeMangledName: true,
    immediateMemberSize: 0x0,
    nonResilientImmediateMembersOffset: 19
    )
}

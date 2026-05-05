// AUTO-GENERATED — DO NOT EDIT.
// Regenerate via: Scripts/regen-baselines.sh
// Source fixture: SymbolTestsCore.framework

enum StructDescriptorBaseline {
    static let registeredTestMethodNames: Set<String> = ["layout", "offset"]

    struct Entry {
        let offset: Int
        let layoutNumFields: Int
        let layoutFieldOffsetVector: Int
        let layoutFlagsRawValue: UInt32
    }

    static let structTest = Entry(
    offset: 0x367a4,
    layoutNumFields: 0,
    layoutFieldOffsetVector: 2,
    layoutFlagsRawValue: 0x51
    )

    static let genericStructNonRequirement = Entry(
    offset: 0x34b74,
    layoutNumFields: 3,
    layoutFieldOffsetVector: 3,
    layoutFlagsRawValue: 0xd1
    )
}

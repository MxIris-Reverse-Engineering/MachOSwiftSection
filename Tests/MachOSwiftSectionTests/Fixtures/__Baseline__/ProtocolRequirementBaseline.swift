// AUTO-GENERATED — DO NOT EDIT.
// Regenerate via: Scripts/regen-baselines.sh
// Source fixture: SymbolTestsCore.framework

enum ProtocolRequirementBaseline {
    static let registeredTestMethodNames: Set<String> = ["defaultImplementationAddress", "defaultImplementationOffset", "layout", "offset"]

    struct Entry {
        let offset: Int
        let layoutFlagsRawValue: UInt32
        let defaultImplementationOffset: Int?
    }

    static let firstRequirement = Entry(
    offset: 0x4493c,
    layoutFlagsRawValue: 0x11,
    defaultImplementationOffset: nil
    )

    static let firstDefaultedRequirement = Entry(
    offset: 0x41290,
    layoutFlagsRawValue: 0x11,
    defaultImplementationOffset: 0xb0c8
    )
}

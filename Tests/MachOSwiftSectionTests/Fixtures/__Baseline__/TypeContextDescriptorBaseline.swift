// AUTO-GENERATED — DO NOT EDIT.
// Regenerate via: Scripts/regen-baselines.sh
// Source fixture: SymbolTestsCore.framework

enum TypeContextDescriptorBaseline {
    static let registeredTestMethodNames: Set<String> = ["classDescriptor", "enumDescriptor", "layout", "offset", "structDescriptor"]

    struct Entry {
        let offset: Int
        let layoutFlagsRawValue: UInt32
        let hasEnumDescriptor: Bool
        let hasStructDescriptor: Bool
        let hasClassDescriptor: Bool
    }

    static let structTest = Entry(
    offset: 0x36160,
    layoutFlagsRawValue: 0x51,
    hasEnumDescriptor: false,
    hasStructDescriptor: true,
    hasClassDescriptor: false
    )
}

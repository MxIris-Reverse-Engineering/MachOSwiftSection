// AUTO-GENERATED — DO NOT EDIT.
// Regenerate via: Scripts/regen-baselines.sh
// Source fixture: SymbolTestsCore.framework

enum ContextDescriptorFlagsBaseline {
    static let registeredTestMethodNames: Set<String> = ["hasInvertibleProtocols", "init(rawValue:)", "isGeneric", "isUnique", "kind", "kindSpecificFlags", "kindSpecificFlagsRawValue", "rawValue", "version"]

    struct Entry {
        let rawValue: UInt32
        let kindRawValue: UInt8
        let version: UInt8
        let kindSpecificFlagsRawValue: UInt16
        let hasKindSpecificFlags: Bool
        let hasInvertibleProtocols: Bool
        let isUnique: Bool
        let isGeneric: Bool
    }

    static let structTest = Entry(
    rawValue: 0x51,
    kindRawValue: 0x11,
    version: 0x0,
    kindSpecificFlagsRawValue: 0x0,
    hasKindSpecificFlags: true,
    hasInvertibleProtocols: false,
    isUnique: true,
    isGeneric: false
    )
}

// AUTO-GENERATED — DO NOT EDIT.
// Regenerate via: Scripts/regen-baselines.sh
// Source fixture: SymbolTestsCore.framework

enum ContextDescriptorKindSpecificFlagsBaseline {
    static let registeredTestMethodNames: Set<String> = ["anonymousFlags", "protocolFlags", "typeFlags"]

    struct Entry {
        let hasProtocolFlags: Bool
        let hasTypeFlags: Bool
        let hasAnonymousFlags: Bool
    }

    static let structTest = Entry(
    hasProtocolFlags: false,
    hasTypeFlags: true,
    hasAnonymousFlags: false
    )
}

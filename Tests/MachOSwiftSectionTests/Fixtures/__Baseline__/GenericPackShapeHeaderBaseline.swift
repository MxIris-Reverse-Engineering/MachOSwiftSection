// AUTO-GENERATED — DO NOT EDIT.
// Regenerate via: Scripts/regen-baselines.sh
// Source fixture: SymbolTestsCore.framework

enum GenericPackShapeHeaderBaseline {
    static let registeredTestMethodNames: Set<String> = ["layout", "offset"]

    struct Entry {
        let offset: Int
        let layoutNumPacks: UInt16
        let layoutNumShapeClasses: UInt16
    }

    static let parameterPackHeader = Entry(
    offset: 0x35380,
    layoutNumPacks: 1,
    layoutNumShapeClasses: 1
    )
}

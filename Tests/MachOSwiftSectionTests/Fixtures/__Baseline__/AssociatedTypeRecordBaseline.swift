// AUTO-GENERATED — DO NOT EDIT.
// Regenerate via: Scripts/regen-baselines.sh
// Source fixture: SymbolTestsCore.framework
//
// Live MangledName payloads aren't embedded as literals; the
// companion Suite (AssociatedTypeRecordTests) verifies the methods
// produce cross-reader-consistent results at runtime against the
// name string / presence flags recorded here.

enum AssociatedTypeRecordBaseline {
    static let registeredTestMethodNames: Set<String> = ["layout", "name", "offset", "substitutedTypeName"]

    struct Entry {
        let offset: Int
        let name: String
        let hasSubstitutedTypeName: Bool
    }

    static let firstRecord = Entry(
    offset: 0x32720,
    name: "First",
    hasSubstitutedTypeName: true
    )
}

// AUTO-GENERATED — DO NOT EDIT.
// Regenerate via: Scripts/regen-baselines.sh
// Source fixture: SymbolTestsCore.framework
//
// Live MangledName payloads aren't embedded as literals; the
// companion Suite (AssociatedTypeTests) verifies the methods
// produce cross-reader-consistent results at runtime against the
// counts / presence flags recorded here.

enum AssociatedTypeBaseline {
    static let registeredTestMethodNames: Set<String> = ["conformingTypeName", "descriptor", "init(descriptor:)", "init(descriptor:in:)", "protocolTypeName", "records"]

    struct Entry {
        let descriptorOffset: Int
        let recordsCount: Int
        let hasConformingTypeName: Bool
        let hasProtocolTypeName: Bool
    }

    static let concreteWitnessTest = Entry(
    descriptorOffset: 0x32790,
    recordsCount: 5,
    hasConformingTypeName: true,
    hasProtocolTypeName: true
    )
}

// AUTO-GENERATED — DO NOT EDIT.
// Regenerate via: Scripts/regen-baselines.sh
// Source fixture: SymbolTestsCore.framework
//
// Live MangledName payloads aren't embedded as literals; the
// companion Suite (AssociatedTypeDescriptorTests) verifies the
// methods produce cross-reader-consistent results at runtime
// against the counts / presence flags recorded here.

enum AssociatedTypeDescriptorBaseline {
    static let registeredTestMethodNames: Set<String> = ["actualSize", "associatedTypeRecords", "conformingTypeName", "layout", "offset", "protocolTypeName"]

    struct Entry {
        let offset: Int
        let layoutNumAssociatedTypes: UInt32
        let layoutAssociatedTypeRecordSize: UInt32
        let actualSize: Int
        let recordsCount: Int
        let hasConformingTypeName: Bool
        let hasProtocolTypeName: Bool
    }

    static let concreteWitnessTest = Entry(
    offset: 0x31e50,
    layoutNumAssociatedTypes: 5,
    layoutAssociatedTypeRecordSize: 8,
    actualSize: 56,
    recordsCount: 5,
    hasConformingTypeName: true,
    hasProtocolTypeName: true
    )
}

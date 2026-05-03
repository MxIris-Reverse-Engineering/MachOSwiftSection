// AUTO-GENERATED — DO NOT EDIT.
// Regenerate via: Scripts/regen-baselines.sh
// Source fixture: SymbolTestsCore.framework
//
// Live MangledName payloads aren't embedded as literals; the
// companion Suite (FieldRecordTests) verifies the methods produce
// cross-reader-consistent results at runtime against the field
// names / presence flags recorded here.

enum FieldRecordBaseline {
    static let registeredTestMethodNames: Set<String> = ["fieldName", "layout", "mangledTypeName", "offset"]

    struct Entry {
        let offset: Int
        let layoutFlagsRawValue: UInt32
        let fieldName: String
        let hasMangledTypeName: Bool
    }

    static let firstRecord = Entry(
    offset: 0x37828,
    layoutFlagsRawValue: 0x2,
    fieldName: "field1",
    hasMangledTypeName: true
    )

    static let secondRecord = Entry(
    offset: 0x37834,
    layoutFlagsRawValue: 0x2,
    fieldName: "field2",
    hasMangledTypeName: true
    )
}

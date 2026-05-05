// AUTO-GENERATED — DO NOT EDIT.
// Regenerate via: Scripts/regen-baselines.sh
// Source fixture: SymbolTestsCore.framework
//
// Live MangledName payloads aren't embedded as literals; the
// companion Suite (FieldDescriptorTests) verifies the methods
// produce cross-reader-consistent results at runtime against the
// presence flags / counts recorded here.

enum FieldDescriptorBaseline {
    static let registeredTestMethodNames: Set<String> = ["kind", "layout", "mangledTypeName", "offset", "records"]

    struct Entry {
        let offset: Int
        let kindRawValue: UInt16
        let layoutNumFields: Int
        let layoutFieldRecordSize: Int
        let recordsCount: Int
        let hasMangledTypeName: Bool
    }

    static let genericStructNonRequirement = Entry(
    offset: 0x38228,
    kindRawValue: 0x0,
    layoutNumFields: 3,
    layoutFieldRecordSize: 12,
    recordsCount: 3,
    hasMangledTypeName: true
    )

    static let structTest = Entry(
    offset: 0x38ea8,
    kindRawValue: 0x0,
    layoutNumFields: 0,
    layoutFieldRecordSize: 12,
    recordsCount: 0,
    hasMangledTypeName: true
    )
}

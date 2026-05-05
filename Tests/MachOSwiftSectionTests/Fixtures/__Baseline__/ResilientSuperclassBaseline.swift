// AUTO-GENERATED — DO NOT EDIT.
// Regenerate via: Scripts/regen-baselines.sh
// Source fixture: SymbolTestsCore.framework
//
// ResilientSuperclass is the trailing-object record on a class
// whose parent lives in a different module. The Suite drives
// `ResilientClassFixtures.ResilientChild` (parent
// `SymbolTestsHelper.ResilientBase`) and asserts cross-reader
// agreement on the record offset and the superclass reference's
// relative-offset scalar.

enum ResilientSuperclassBaseline {
    static let registeredTestMethodNames: Set<String> = ["layout", "offset"]

    struct Entry {
        let sourceClassOffset: Int
        let offset: Int
        let layoutSuperclassRelativeOffset: Int32
    }

    static let resilientChild = Entry(
        sourceClassOffset: 0x35e10,
        offset: 0x35e3c,
        layoutSuperclassRelativeOffset: 41452
    )
}

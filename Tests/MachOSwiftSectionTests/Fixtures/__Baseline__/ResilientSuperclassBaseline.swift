// AUTO-GENERATED — DO NOT EDIT.
// Regenerate via: Scripts/regen-baselines.sh
// Source fixture: SymbolTestsCore.framework
//
// ResilientSuperclass appears in classes with a resilient superclass.
// The Suite picks the first such class via Class.resilientSuperclass
// and asserts cross-reader agreement on the record offset.

enum ResilientSuperclassBaseline {
    static let registeredTestMethodNames: Set<String> = ["layout", "offset"]

    struct Entry {
        let sourceClassOffset: Int
        let offset: Int
    }

    static let firstResilientSuperclass = Entry(
        sourceClassOffset: 0x32b58,
        offset: 0x32b84
    )
}

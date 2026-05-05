// AUTO-GENERATED — DO NOT EDIT.
// Regenerate via: Scripts/regen-baselines.sh
// Source fixture: SymbolTestsCore.framework
//
// MethodOverrideDescriptor carries three relative pointers (class /
// method / implementation Symbols). Live payloads aren't embedded;
// the Suite verifies cross-reader agreement at runtime.

enum MethodOverrideDescriptorBaseline {
    static let registeredTestMethodNames: Set<String> = ["classDescriptor", "implementationSymbols", "layout", "methodDescriptor", "offset"]

    struct Entry {
        let offset: Int
    }

    static let firstSubclassOverride = Entry(
    offset: 0x32fcc
    )

    static let subclassOverrideCount = 9
}

// AUTO-GENERATED — DO NOT EDIT.
// Regenerate via: Scripts/regen-baselines.sh
// Source fixture: SymbolTestsCore.framework
//
// The implementation offset is pure relative-pointer arithmetic, so
// it is pinned as a literal (like MethodDescriptor's); the class /
// method descriptor pointers resolve to live wrappers and are
// checked for presence across readers at runtime instead.

enum MethodOverrideDescriptorBaseline {
    static let registeredTestMethodNames: Set<String> = ["classDescriptor", "implementationAddress", "implementationOffset", "layout", "methodDescriptor", "offset"]

    struct Entry {
        let offset: Int
        let implementationOffset: Int?
    }

    static let firstSubclassOverride = Entry(
    offset: 0x409d8,
    implementationOffset: 0x4014
    )

    static let subclassOverrideCount = 9
}

// AUTO-GENERATED — DO NOT EDIT.
// Regenerate via: Scripts/regen-baselines.sh
// Source fixture: SymbolTestsCore.framework
//
// The implementation offset is pure relative-pointer arithmetic, so
// it is pinned as a literal; the companion Suite
// (MethodDescriptorTests) also verifies cross-reader agreement.

enum MethodDescriptorBaseline {
    static let registeredTestMethodNames: Set<String> = ["implementationAddress", "implementationOffset", "layout", "offset"]

    struct Entry {
        let offset: Int
        let layoutFlagsRawValue: UInt32
        let implementationOffset: Int?
    }

    static let firstClassTestMethod = Entry(
    offset: 0x40960,
    layoutFlagsRawValue: 0x12,
    implementationOffset: 0x15f8
    )

    static let classTestMethodCount = 9
}

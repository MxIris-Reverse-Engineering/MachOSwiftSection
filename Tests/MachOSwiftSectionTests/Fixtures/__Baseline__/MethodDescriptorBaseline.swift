// AUTO-GENERATED — DO NOT EDIT.
// Regenerate via: Scripts/regen-baselines.sh
// Source fixture: SymbolTestsCore.framework
//
// Method descriptors carry a `Symbols?` implementation pointer; live
// payloads aren't embedded as literals. The companion Suite
// (MethodDescriptorTests) verifies cross-reader agreement at
// runtime.

enum MethodDescriptorBaseline {
    static let registeredTestMethodNames: Set<String> = ["implementationSymbols", "layout", "offset"]

    struct Entry {
        let offset: Int
        let layoutFlagsRawValue: UInt32
    }

    static let firstClassTestMethod = Entry(
    offset: 0x33904,
    layoutFlagsRawValue: 0x12
    )

    static let classTestMethodCount = 9
}

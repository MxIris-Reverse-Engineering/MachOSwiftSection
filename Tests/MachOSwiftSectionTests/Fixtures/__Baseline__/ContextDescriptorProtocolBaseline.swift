// AUTO-GENERATED — DO NOT EDIT.
// Regenerate via: Scripts/regen-baselines.sh
// Source fixture: SymbolTestsCore.framework
//
// Live wrapper payloads (parent/genericContext/moduleContextDescriptor)
// aren't embedded as literals; the companion Suite
// (ContextDescriptorProtocolTests) verifies the methods produce
// cross-reader-consistent results at runtime.

enum ContextDescriptorProtocolBaseline {
    static let registeredTestMethodNames: Set<String> = ["genericContext", "isCImportedContextDescriptor", "moduleContextDesciptor", "parent", "subscript(dynamicMember:)"]

    struct Entry {
        let hasParent: Bool
        let hasGenericContext: Bool
        let hasModuleContextDescriptor: Bool
        let isCImportedContextDescriptor: Bool
        let subscriptKindRawValue: UInt8
    }

    static let structTest = Entry(
    hasParent: true,
    hasGenericContext: false,
    hasModuleContextDescriptor: true,
    isCImportedContextDescriptor: false,
    subscriptKindRawValue: 0x11
    )
}

// AUTO-GENERATED — DO NOT EDIT.
// Regenerate via: Scripts/regen-baselines.sh
// Source fixture: SymbolTestsCore.framework
//
// The MangledName payload returned by `extendedContext(in:)` is a
// deep ABI tree we don't embed as a literal; the companion Suite
// (ExtensionContextDescriptorProtocolTests) verifies the methods
// produce cross-reader-consistent results at runtime.

enum ExtensionContextDescriptorProtocolBaseline {
    static let registeredTestMethodNames: Set<String> = ["extendedContext"]

    struct Entry {
        let hasExtendedContext: Bool
    }

    static let firstExtension = Entry(
    hasExtendedContext: true
    )
}

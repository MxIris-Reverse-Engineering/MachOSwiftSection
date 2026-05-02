// AUTO-GENERATED — DO NOT EDIT.
// Regenerate via: Scripts/regen-baselines.sh
// Source fixture: SymbolTestsCore.framework
//
// The MangledName payload is a deep ABI tree we don't embed as a
// literal; the companion Suite (NamedContextDescriptorProtocolTests)
// verifies the methods produce cross-reader-consistent results at
// runtime against the presence flag recorded here.

enum NamedContextDescriptorProtocolBaseline {
    static let registeredTestMethodNames: Set<String> = ["mangledName", "name"]

    struct Entry {
        let name: String
        let hasMangledName: Bool
    }

    static let structTest = Entry(
    name: "StructTest",
    hasMangledName: true
    )
}

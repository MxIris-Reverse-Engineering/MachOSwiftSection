// AUTO-GENERATED — DO NOT EDIT.
// Regenerate via: Scripts/regen-baselines.sh
// Source fixture: SymbolTestsCore.framework

enum ResilientWitnessBaseline {
    static let registeredTestMethodNames: Set<String> = ["implementationAddress", "implementationOffset", "implementationSymbols", "layout", "offset", "requirement"]

    struct Entry {
        let offset: Int
        let hasRequirement: Bool
        let hasImplementationSymbols: Bool
        let implementationOffset: Int
    }

    static let firstWitness = Entry(
    offset: 0x29428,
    hasRequirement: true,
    hasImplementationSymbols: true,
    implementationOffset: 0x1a14
    )
}

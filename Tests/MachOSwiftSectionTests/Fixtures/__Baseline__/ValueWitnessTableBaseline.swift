// AUTO-GENERATED — DO NOT EDIT.
// Regenerate via: Scripts/regen-baselines.sh
// Source fixture: SymbolTestsCore.framework
//
// ValueWitnessTable is reachable solely through
// `MetadataProtocol.valueWitnesses(in:)` from a loaded
// MachOImage — the function pointers live in the runtime image.
// The Suite materialises the table for Structs.StructTest and
// asserts cross-reader equality on the size / stride / flags /
// numExtraInhabitants ivars; per-process function pointers are
// not compared literally.
//
// `init(layout:offset:)` is filtered as memberwise-synthesized.

enum ValueWitnessTableBaseline {
    static let registeredTestMethodNames: Set<String> = ["layout", "offset", "typeLayout"]
}

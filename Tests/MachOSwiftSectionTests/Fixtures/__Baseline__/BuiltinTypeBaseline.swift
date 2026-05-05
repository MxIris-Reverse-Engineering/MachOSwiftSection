// AUTO-GENERATED — DO NOT EDIT.
// Regenerate via: Scripts/regen-baselines.sh
// Source fixture: SymbolTestsCore.framework
//
// BuiltinType wraps the first BuiltinTypeDescriptor of
// SymbolTestsCore. Live MangledName payload isn't embedded as a
// literal; the Suite verifies presence via the
// `hasMangledName` flag and equality of the descriptor offset.

enum BuiltinTypeBaseline {
    static let registeredTestMethodNames: Set<String> = ["descriptor", "init(descriptor:)", "init(descriptor:in:)", "typeName"]

    struct Entry {
        let descriptorOffset: Int
        let hasTypeName: Bool
    }

    static let firstBuiltin = Entry(
    descriptorOffset: 0x3a880,
    hasTypeName: true
    )
}

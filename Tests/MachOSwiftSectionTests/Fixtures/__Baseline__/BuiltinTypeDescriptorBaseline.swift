// AUTO-GENERATED — DO NOT EDIT.
// Regenerate via: Scripts/regen-baselines.sh
// Source fixture: SymbolTestsCore.framework
//
// BuiltinTypeDescriptor is the first record in the
// __swift5_builtin section of SymbolTestsCore. The Suite asserts
// cross-reader equality of the size/alignment/stride/extra-
// inhabitants layout fields and the typeName resolution.

enum BuiltinTypeDescriptorBaseline {
    static let registeredTestMethodNames: Set<String> = ["alignment", "hasMangledName", "isBitwiseTakable", "layout", "offset", "typeName"]

    struct Entry {
        let descriptorOffset: Int
        let size: UInt32
        let alignmentAndFlags: UInt32
        let stride: UInt32
        let numExtraInhabitants: UInt32
        let alignment: Int
        let isBitwiseTakable: Bool
        let hasMangledName: Bool
    }

    static let firstBuiltin = Entry(
    descriptorOffset: 0x4b764,
    size: 0x9,
    alignmentAndFlags: 0x10008,
    stride: 0x10,
    numExtraInhabitants: 0xfd,
    alignment: 0x8,
    isBitwiseTakable: true,
    hasMangledName: true
    )
}

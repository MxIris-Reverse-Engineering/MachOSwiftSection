// AUTO-GENERATED — DO NOT EDIT.
// Regenerate via: Scripts/regen-baselines.sh
// Source fixture: SymbolTestsCore.framework
//
// ClassFlags is a raw UInt32 enum with five named cases. The Suite
// (ClassFlagsTests) round-trips the raw values to catch any
// accidental case renumbering / renaming.

enum ClassFlagsBaseline {
    static let registeredTestMethodNames: Set<String> = []

    static let isSwiftPreStableABI: UInt32 = 0x1
    static let usesSwiftRefcounting: UInt32 = 0x2
    static let hasCustomObjCName: UInt32 = 0x4
    static let isStaticSpecialization: UInt32 = 0x8
    static let isCanonicalStaticSpecialization: UInt32 = 0x10
}

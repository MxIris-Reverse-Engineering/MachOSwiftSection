// AUTO-GENERATED — DO NOT EDIT.
// Regenerate via: Scripts/regen-baselines.sh
// Source fixture: SymbolTestsCore.framework
//
// ClassFlags is a UInt32 option set with five flags, built by
// @FlagSet. The Suite (ClassFlagsTests) round-trips the raw values to
// catch any accidental flag renumbering / renaming.

enum ClassFlagsBaseline {
    static let registeredTestMethodNames: Set<String> = []

    static let isSwiftPreStableABI: UInt32 = 0x1
    static let usesSwiftRefcounting: UInt32 = 0x2
    static let hasCustomObjCName: UInt32 = 0x4
    static let isStaticSpecialization: UInt32 = 0x8
    static let isCanonicalStaticSpecialization: UInt32 = 0x10
}

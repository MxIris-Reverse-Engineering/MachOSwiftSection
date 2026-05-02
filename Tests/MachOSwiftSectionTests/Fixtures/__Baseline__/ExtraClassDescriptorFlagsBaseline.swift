// AUTO-GENERATED — DO NOT EDIT.
// Regenerate via: Scripts/regen-baselines.sh
// Source fixture: SymbolTestsCore.framework
//
// ExtraClassDescriptorFlags is a UInt32 FlagSet with a single bit
// (`hasObjCResilientClassStub`). For the plain ClassTest picker
// the raw value is zero; we test the flag derivation by
// round-tripping a known raw value through `init(rawValue:)`.

enum ExtraClassDescriptorFlagsBaseline {
    static let registeredTestMethodNames: Set<String> = ["hasObjCResilientClassStub", "init(rawValue:)", "rawValue"]

    // Construct round-trip values: bit 0 set / unset.
    static let zeroRawValue: UInt32 = 0x0
    static let stubBitRawValue: UInt32 = 0x1
}

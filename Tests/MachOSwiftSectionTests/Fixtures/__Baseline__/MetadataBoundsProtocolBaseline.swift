// AUTO-GENERATED — DO NOT EDIT.
// Regenerate via: Scripts/regen-baselines.sh
// Source fixture: SymbolTestsCore.framework
//
// The derived sizes are computed from the closed-form formulas
//   totalSizeInBytes    = (neg + pos) * sizeof(StoredPointer)
//   addressPointInBytes =  neg        * sizeof(StoredPointer)
// The Suite drives a constant MetadataBounds(neg=2, pos=16) and
// checks both expressions.

enum MetadataBoundsProtocolBaseline {
    static let registeredTestMethodNames: Set<String> = ["addressPointInBytes", "totalSizeInBytes"]

    /// Constants matching `MetadataBoundsBaseline` so the Suites
    /// stay aligned without cross-baseline references.
    static let sampleNegativeSizeInWords: UInt32 = 0x2
    static let samplePositiveSizeInWords: UInt32 = 0x10
}

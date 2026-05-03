// AUTO-GENERATED — DO NOT EDIT.
// Regenerate via: Scripts/regen-baselines.sh
// Source fixture: SymbolTestsCore.framework
//
// FieldRecordFlags is exercised against synthetic raw values
// covering each option bit (isIndirectCase / isVariadic /
// isArtificial) plus the empty and all-bits combinations. Live
// carriers are also exercised by the FieldRecord Suite's
// per-fixture readings (the SymbolTestsCore fixture's records
// all carry flags == 0x0).

enum FieldRecordFlagsBaseline {
    static let registeredTestMethodNames: Set<String> = ["init(rawValue:)", "isArtificial", "isIndirectCase", "isVariadic", "rawValue"]

    struct Entry {
        let rawValue: UInt32
        let isIndirectCase: Bool
        let isVariadic: Bool
        let isArtificial: Bool
    }

    static let empty = Entry(
    rawValue: 0x0,
    isIndirectCase: false,
    isVariadic: false,
    isArtificial: false
    )

    static let isIndirectCase = Entry(
    rawValue: 0x1,
    isIndirectCase: true,
    isVariadic: false,
    isArtificial: false
    )

    static let isVariadic = Entry(
    rawValue: 0x2,
    isIndirectCase: false,
    isVariadic: true,
    isArtificial: false
    )

    static let isArtificial = Entry(
    rawValue: 0x4,
    isIndirectCase: false,
    isVariadic: false,
    isArtificial: true
    )

    static let allBits = Entry(
    rawValue: 0x7,
    isIndirectCase: true,
    isVariadic: true,
    isArtificial: true
    )
}

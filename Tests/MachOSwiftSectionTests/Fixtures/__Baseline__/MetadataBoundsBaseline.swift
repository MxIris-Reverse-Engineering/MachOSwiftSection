// AUTO-GENERATED — DO NOT EDIT.
// Regenerate via: Scripts/regen-baselines.sh
// Source fixture: SymbolTestsCore.framework
//
// MetadataBounds is exercised via constant round-trip; live class-
// metadata bounds are reachable only through MachOImage and are
// covered by the ClassMetadataBoundsProtocol Suite.

enum MetadataBoundsBaseline {
    static let registeredTestMethodNames: Set<String> = ["layout", "offset"]

    /// Constants used by the companion Suite to drive the round-trip.
    static let sampleNegativeSizeInWords: UInt32 = 0x2
    static let samplePositiveSizeInWords: UInt32 = 0x10
    static let sampleOffset: Int = 0x100
}

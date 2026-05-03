// AUTO-GENERATED — DO NOT EDIT.
// Regenerate via: Scripts/regen-baselines.sh
// Source fixture: SymbolTestsCore.framework
//
// MetadataRequest is a value type round-tripped through its flag
// accessors. No MachO fixture is required; the Suite verifies the
// bit-packing invariants directly.

enum MetadataRequestBaseline {
    static let registeredTestMethodNames: Set<String> = ["completeAndBlocking", "init", "init(rawValue:)", "init(state:isBlocking:)", "isBlocking", "rawValue", "state"]

    /// Constants used by the companion Suite to drive bit-packing
    /// round-trips.
    static let completeAndBlockingExpectedRawValue: Int = 0x100
    static let layoutCompleteRawValue: Int = 0x3F
    static let abstractRawValue: Int = 0xFF
}

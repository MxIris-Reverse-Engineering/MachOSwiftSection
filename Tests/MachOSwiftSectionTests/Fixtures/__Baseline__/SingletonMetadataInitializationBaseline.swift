// AUTO-GENERATED — DO NOT EDIT.
// Regenerate via: Scripts/regen-baselines.sh
// Source fixture: SymbolTestsCore.framework
//
// The picker selects the first ClassDescriptor in SymbolTestsCore that
// carries the hasSingletonMetadataInitialization bit. Relative offsets
// are layout-invariant for a fixed source so the baseline stays
// stable across rebuilds.

enum SingletonMetadataInitializationBaseline {
    static let registeredTestMethodNames: Set<String> = ["layout", "offset"]

    /// `RelativeOffset` is `Int32`; we store it as `UInt64`
    /// (bitPattern) here because `BaselineEmitter.hex` sign-extends
    /// to UInt64, so negative Int32 values would not fit a signed
    /// Int64 literal. The Suite reads the field via
    /// `Int32(truncatingIfNeeded:)` to recover the signed value.
    struct Entry {
        let descriptorOffset: Int
        let initializationCacheRelativeOffsetBits: UInt64
        let incompleteMetadataRelativeOffsetBits: UInt64
        let completionFunctionRelativeOffsetBits: UInt64
    }

    static let firstSingletonInit = Entry(
    descriptorOffset: 0x337d8,
    initializationCacheRelativeOffsetBits: 0x1bd38,
    incompleteMetadataRelativeOffsetBits: 0xe3a4,
    completionFunctionRelativeOffsetBits: 0xfffffffffffd0b24
    )
}

// AUTO-GENERATED — DO NOT EDIT.
// Regenerate via: Scripts/regen-baselines.sh
// Source fixture: SymbolTestsCore.framework
//
// The shared pattern-header members, recorded for both conformers.

enum GenericMetadataPatternProtocolBaseline {
    static let registeredTestMethodNames: Set<String> = ["extraDataPattern", "hasExtraDataPattern", "hasTrailingFlags", "partialPatterns", "partialPatternsOffset", "size"]

    struct Entry {
        let offset: Int
        let patternFlagsRawValue: UInt32
        let hasExtraDataPattern: Bool
        let hasTrailingFlags: Bool
        let partialPatternsOffset: Int
        let size: Int
        let partialPatternCount: Int
    }

    static let valuePattern = Entry(
    offset: 0x3c6c0,
    patternFlagsRawValue: 0x40000000,
    hasExtraDataPattern: false,
    hasTrailingFlags: false,
    partialPatternsOffset: 0x3c6d0,
    size: 16,
    partialPatternCount: 0
    )

    static let classPattern = Entry(
    offset: 0x5a338,
    patternFlagsRawValue: 0x1,
    hasExtraDataPattern: true,
    hasTrailingFlags: false,
    partialPatternsOffset: 0x5a358,
    size: 40,
    partialPatternCount: 1
    )
}

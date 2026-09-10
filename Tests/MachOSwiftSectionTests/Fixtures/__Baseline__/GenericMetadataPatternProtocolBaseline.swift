// AUTO-GENERATED — DO NOT EDIT.
// Regenerate via: Scripts/regen-baselines.sh
// Source fixture: SymbolTestsCore.framework
//
// The shared pattern-header members, recorded for both conformers.

enum GenericMetadataPatternProtocolBaseline {
    static let registeredTestMethodNames: Set<String> = ["extraDataPattern", "hasExtraDataPattern", "hasTrailingFlags", "partialPatterns", "partialPatternsOffset", "patternFlags", "size"]

    struct Entry {
        let offset: Int
        let patternFlagsRawValue: UInt32
        let hasExtraDataPattern: Bool
        let hasTrailingFlags: Bool
        let instantiationFunctionOffset: Int?
        let completionFunctionOffset: Int?
        let partialPatternsOffset: Int
        let size: Int
        let partialPatternCount: Int
    }

    static let valuePattern = Entry(
    offset: 0x3c6c0,
    patternFlagsRawValue: 0x40000000,
    hasExtraDataPattern: false,
    hasTrailingFlags: false,
    instantiationFunctionOffset: 0xe448,
    completionFunctionOffset: 0x1d0b8,
    partialPatternsOffset: 0x3c6d0,
    size: 16,
    partialPatternCount: 0
    )

    static let classPattern = Entry(
    offset: 0x5a338,
    patternFlagsRawValue: 0x1,
    hasExtraDataPattern: true,
    hasTrailingFlags: false,
    instantiationFunctionOffset: 0x26dd0,
    completionFunctionOffset: 0x26dd4,
    partialPatternsOffset: 0x5a358,
    size: 40,
    partialPatternCount: 1
    )
}

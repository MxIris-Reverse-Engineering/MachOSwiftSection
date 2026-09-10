// AUTO-GENERATED — DO NOT EDIT.
// Regenerate via: swift package --allow-writing-to-package-directory regen-baselines
// Source: live in-process function types; no Mach-O section presence.
//
// Only flag words and counts are recorded. Metadata addresses move
// with every launch, and the trailing TYPES are checked in the Suite
// against the metadata of the types the carriers name.

enum FunctionTypeMetadataBaseline {
    static let registeredTestMethodNames: Set<String> = ["differentiabilityKind", "differentiabilityKindOffset", "extendedFlags", "extendedFlagsOffset", "flags", "globalActorOffset", "globalActorType", "layout", "numberOfParameters", "offset", "parameterFlags", "parameterFlagsOffset", "parameters", "parametersOffset", "thrownErrorType", "thrownErrorTypeOffset"]

    struct Entry {
        let kindRawValue: UInt32
        let flagsRawValue: UInt64
        let numberOfParameters: Int
        let hasParameterFlags: Bool
        let isDifferentiable: Bool
        let hasGlobalActor: Bool
        let hasExtendedFlags: Bool
        let extendedFlagsRawValue: UInt32?
        let isTypedThrows: Bool
    }

    static let stdlibFunctionIntToVoid = Entry(
    kindRawValue: 0x302,
    flagsRawValue: 0x4000001,
    numberOfParameters: 1,
    hasParameterFlags: false,
    isDifferentiable: false,
    hasGlobalActor: false,
    hasExtendedFlags: false,
    extendedFlagsRawValue: nil,
    isTypedThrows: false
    )

    static let stdlibFunctionIntStringToBool = Entry(
    kindRawValue: 0x302,
    flagsRawValue: 0x4000002,
    numberOfParameters: 2,
    hasParameterFlags: false,
    isDifferentiable: false,
    hasGlobalActor: false,
    hasExtendedFlags: false,
    extendedFlagsRawValue: nil,
    isTypedThrows: false
    )

    static let stdlibFunctionInOutIntToVoid = Entry(
    kindRawValue: 0x302,
    flagsRawValue: 0x6000001,
    numberOfParameters: 1,
    hasParameterFlags: true,
    isDifferentiable: false,
    hasGlobalActor: false,
    hasExtendedFlags: false,
    extendedFlagsRawValue: nil,
    isTypedThrows: false
    )

    /// `nil` when the baseline was generated below macOS 15, where
    /// the typed-throws carrier cannot be formed.
    static let stdlibFunctionMainActorTypedThrows: Entry? = Entry(
    kindRawValue: 0x302,
    flagsRawValue: 0xd5000000,
    numberOfParameters: 0,
    hasParameterFlags: false,
    isDifferentiable: false,
    hasGlobalActor: true,
    hasExtendedFlags: true,
    extendedFlagsRawValue: 0x1,
    isTypedThrows: true
    )
}

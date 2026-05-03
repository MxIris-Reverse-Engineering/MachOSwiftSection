// AUTO-GENERATED — DO NOT EDIT.
// Regenerate via: Scripts/regen-baselines.sh
// Source fixture: SymbolTestsCore.framework
//
// GenericEnvironmentFlags has no live SymbolTestsCore source (the
// structure is materialized by the runtime's metadata initialization
// machinery), so the baseline embeds synthetic raw values exercising
// both bit-fields (parameter levels + requirements).

enum GenericEnvironmentFlagsBaseline {
    static let registeredTestMethodNames: Set<String> = ["init(rawValue:)", "numberOfGenericParameterLevels", "numberOfGenericRequirements", "rawValue"]

    struct Entry {
        let rawValue: UInt32
        let numberOfGenericParameterLevels: UInt32
        let numberOfGenericRequirements: UInt32
    }

    static let zero = Entry(
    rawValue: 0x0,
    numberOfGenericParameterLevels: 0x0,
    numberOfGenericRequirements: 0x0
    )

    static let oneLevel = Entry(
    rawValue: 0x1,
    numberOfGenericParameterLevels: 0x1,
    numberOfGenericRequirements: 0x0
    )

    static let threeLevelsOneRequirement = Entry(
    rawValue: 0x1003,
    numberOfGenericParameterLevels: 0x3,
    numberOfGenericRequirements: 0x1
    )

    static let maxAll = Entry(
    rawValue: 0xfffff,
    numberOfGenericParameterLevels: 0xfff,
    numberOfGenericRequirements: 0xff
    )
}

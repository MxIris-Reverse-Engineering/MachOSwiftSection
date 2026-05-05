// AUTO-GENERATED — DO NOT EDIT.
// Regenerate via: Scripts/regen-baselines.sh
// Source fixture: SymbolTestsCore.framework
//
// InvertibleProtocolsRequirementCount has no live SymbolTestsCore
// source (the count is implied by the surrounding requirement
// scan), so the baseline embeds synthetic raw values.

enum InvertibleProtocolsRequirementCountBaseline {
    static let registeredTestMethodNames: Set<String> = ["init(rawValue:)", "rawValue"]

    struct Entry {
        let rawValue: UInt16
    }

    static let zero = Entry(
    rawValue: 0x0
    )

    static let small = Entry(
    rawValue: 0x3
    )
}

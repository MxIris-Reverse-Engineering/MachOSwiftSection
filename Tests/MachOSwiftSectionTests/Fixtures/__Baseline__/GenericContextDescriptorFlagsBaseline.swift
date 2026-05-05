// AUTO-GENERATED — DO NOT EDIT.
// Regenerate via: Scripts/regen-baselines.sh
// Source fixture: SymbolTestsCore.framework
//
// GenericContextDescriptorFlags is exercised against synthetic raw
// values covering each option bit (none / typePacks / conditional /
// values / all). The fixture has live carriers too — see the
// GenericContextDescriptorHeader Suite for in-binary readings.

enum GenericContextDescriptorFlagsBaseline {
    static let registeredTestMethodNames: Set<String> = ["hasConditionalInvertedProtocols", "hasTypePacks", "hasValues", "init(rawValue:)", "rawValue"]

    struct Entry {
        let rawValue: UInt16
        let hasTypePacks: Bool
        let hasConditionalInvertedProtocols: Bool
        let hasValues: Bool
    }

    static let none = Entry(
    rawValue: 0x0,
    hasTypePacks: false,
    hasConditionalInvertedProtocols: false,
    hasValues: false
    )

    static let typePacksOnly = Entry(
    rawValue: 0x1,
    hasTypePacks: true,
    hasConditionalInvertedProtocols: false,
    hasValues: false
    )

    static let conditionalOnly = Entry(
    rawValue: 0x2,
    hasTypePacks: false,
    hasConditionalInvertedProtocols: true,
    hasValues: false
    )

    static let valuesOnly = Entry(
    rawValue: 0x4,
    hasTypePacks: false,
    hasConditionalInvertedProtocols: false,
    hasValues: true
    )

    static let all = Entry(
    rawValue: 0x7,
    hasTypePacks: true,
    hasConditionalInvertedProtocols: true,
    hasValues: true
    )
}

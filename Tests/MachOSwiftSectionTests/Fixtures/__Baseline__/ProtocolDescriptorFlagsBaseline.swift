// AUTO-GENERATED — DO NOT EDIT.
// Regenerate via: Scripts/regen-baselines.sh
// Source fixture: SymbolTestsCore.framework
//
// ProtocolDescriptorFlags has no live SymbolTestsCore source, so the
// baseline embeds synthetic raw values that exercise each branch
// (Swift default, Swift+resilient, ObjC dispatch).

enum ProtocolDescriptorFlagsBaseline {
    static let registeredTestMethodNames: Set<String> = ["classConstraint", "dispatchStrategy", "init(rawValue:)", "isResilient", "isSwift", "needsProtocolWitnessTable", "rawValue", "specialProtocolKind"]

    struct Entry {
        let rawValue: UInt32
        let isSwift: Bool
        let isResilient: Bool
        let classConstraintRawValue: UInt8
        let dispatchStrategyRawValue: UInt8
        let specialProtocolKindRawValue: UInt8
        let needsProtocolWitnessTable: Bool
    }

    static let swift = Entry(
    rawValue: 0x1,
    isSwift: true,
    isResilient: false,
    classConstraintRawValue: 0x0,
    dispatchStrategyRawValue: 0x0,
    specialProtocolKindRawValue: 0x0,
    needsProtocolWitnessTable: false
    )

    static let resilient = Entry(
    rawValue: 0x401,
    isSwift: true,
    isResilient: true,
    classConstraintRawValue: 0x0,
    dispatchStrategyRawValue: 0x0,
    specialProtocolKindRawValue: 0x0,
    needsProtocolWitnessTable: false
    )

    static let objc = Entry(
    rawValue: 0x0,
    isSwift: false,
    isResilient: false,
    classConstraintRawValue: 0x0,
    dispatchStrategyRawValue: 0x0,
    specialProtocolKindRawValue: 0x0,
    needsProtocolWitnessTable: false
    )
}

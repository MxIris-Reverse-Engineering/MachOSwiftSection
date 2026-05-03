// AUTO-GENERATED — DO NOT EDIT.
// Regenerate via: Scripts/regen-baselines.sh
// Source fixture: SymbolTestsCore.framework

enum ProtocolContextDescriptorFlagsBaseline {
    static let registeredTestMethodNames: Set<String> = ["classConstraint", "init(rawValue:)", "isResilient", "rawValue", "specialProtocolKind"]

    struct Entry {
        let rawValue: UInt16
        let isResilient: Bool
        let classConstraintRawValue: UInt8
        let specialProtocolKindRawValue: UInt8
    }

    static let protocolTest = Entry(
    rawValue: 0x3,
    isResilient: true,
    classConstraintRawValue: 0x1,
    specialProtocolKindRawValue: 0x0
    )
}

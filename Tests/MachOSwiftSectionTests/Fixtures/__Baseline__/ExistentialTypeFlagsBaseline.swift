// AUTO-GENERATED — DO NOT EDIT.
// Regenerate via: Scripts/regen-baselines.sh
// Source fixture: SymbolTestsCore.framework
//
// ExistentialTypeFlags is a pure raw-value bit decoder (no MachO
// dependency). The baseline embeds canonical synthetic raw values
// exercising each documented bit field.

enum ExistentialTypeFlagsBaseline {
    static let registeredTestMethodNames: Set<String> = ["classConstraint", "hasSuperclassConstraint", "init(rawValue:)", "numberOfWitnessTables", "rawValue", "specialProtocol"]

    struct Entry {
        let rawValue: UInt32
        let numberOfWitnessTables: UInt32
        let classConstraintRawValue: UInt8
        let hasSuperclassConstraint: Bool
        let specialProtocolRawValue: UInt8
    }

    static let cases: [Entry] = [
        // empty
        Entry(
            rawValue: 0x0,
            numberOfWitnessTables: 0x0,
            classConstraintRawValue: 0x0,
            hasSuperclassConstraint: false,
            specialProtocolRawValue: 0x0
        ),
        // classBoundOneWitness
        Entry(
            rawValue: 0x1,
            numberOfWitnessTables: 0x1,
            classConstraintRawValue: 0x0,
            hasSuperclassConstraint: false,
            specialProtocolRawValue: 0x0
        ),
        // classBoundThreeWitnesses
        Entry(
            rawValue: 0x3,
            numberOfWitnessTables: 0x3,
            classConstraintRawValue: 0x0,
            hasSuperclassConstraint: false,
            specialProtocolRawValue: 0x0
        ),
        // errorSpecial
        Entry(
            rawValue: 0x1000000,
            numberOfWitnessTables: 0x0,
            classConstraintRawValue: 0x0,
            hasSuperclassConstraint: false,
            specialProtocolRawValue: 0x1
        ),
        // withSuperclass
        Entry(
            rawValue: 0x40000001,
            numberOfWitnessTables: 0x1,
            classConstraintRawValue: 0x0,
            hasSuperclassConstraint: true,
            specialProtocolRawValue: 0x0
        )
    ]
}

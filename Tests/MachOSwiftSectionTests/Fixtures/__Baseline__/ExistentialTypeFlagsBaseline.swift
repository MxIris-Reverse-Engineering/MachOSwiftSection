// AUTO-GENERATED — DO NOT EDIT.
// Regenerate via: swift package --allow-writing-to-package-directory regen-baselines
// Source: InProcess (`Any.self` + `AnyObject.self`); no Mach-O section presence.

enum ExistentialTypeFlagsBaseline {
    static let registeredTestMethodNames: Set<String> = ["classConstraint", "hasSuperclassConstraint", "init(rawValue:)", "numberOfWitnessTables", "rawValue", "specialProtocol"]

    struct AnyEntry {
        let rawValue: UInt32
        let numberOfWitnessTables: UInt32
        let hasSuperclassConstraint: Bool
        let specialProtocolRawValue: UInt8
    }

    struct AnyObjectEntry {
        let rawValue: UInt32
        let classConstraintRawValue: UInt8
    }

    static let stdlibAnyExistential = AnyEntry(
        rawValue: 0x80000000,
        numberOfWitnessTables: 0x0,
        hasSuperclassConstraint: false,
        specialProtocolRawValue: 0x0
    )

    static let stdlibAnyObjectExistential = AnyObjectEntry(
        rawValue: 0x0,
        classConstraintRawValue: 0x0
    )
}

// AUTO-GENERATED — DO NOT EDIT.
// Regenerate via: swift package --allow-writing-to-package-directory regen-baselines
// Source: InProcess (`Any.self` + `AnyObject.self`); no Mach-O section presence.

enum ExistentialTypeMetadataBaseline {
    static let registeredTestMethodNames: Set<String> = ["isClassBounded", "isObjC", "layout", "offset", "protocols", "representation", "superclassConstraint"]

    struct Entry {
        let kindRawValue: UInt32
        let flagsRawValue: UInt32
        let numberOfProtocols: UInt32
        let isClassBounded: Bool
        let isObjC: Bool
    }

    static let stdlibAnyExistential = Entry(
        kindRawValue: 0x303,
        flagsRawValue: 0x80000000,
        numberOfProtocols: 0x0,
        isClassBounded: false,
        isObjC: false
    )

    static let stdlibAnyObjectExistential = Entry(
        kindRawValue: 0x303,
        flagsRawValue: 0x0,
        numberOfProtocols: 0x0,
        isClassBounded: true,
        isObjC: true
    )
}

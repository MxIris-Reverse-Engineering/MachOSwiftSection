// AUTO-GENERATED — DO NOT EDIT.
// Regenerate via: Scripts/regen-baselines.sh
// Source fixture: SymbolTestsCore.framework
//
// GenericRequirementFlags is exercised against synthetic raw values
// covering each kind (protocol/sameType/layout) plus combinations
// with the three option bits (isPackRequirement/hasKeyArgument/
// isValueRequirement). Live carriers are also exercised by the
// GenericRequirementDescriptor Suite's per-fixture readings.

enum GenericRequirementFlagsBaseline {
    static let registeredTestMethodNames: Set<String> = ["hasKeyArgument", "init(rawValue:)", "isPackRequirement", "isValueRequirement", "kind", "rawValue"]

    struct Entry {
        let rawValue: UInt32
        let kindRawValue: UInt8
        let isPackRequirement: Bool
        let hasKeyArgument: Bool
        let isValueRequirement: Bool
    }

    static let protocolDefault = Entry(
    rawValue: 0x0,
    kindRawValue: 0x0,
    isPackRequirement: false,
    hasKeyArgument: false,
    isValueRequirement: false
    )

    static let sameType = Entry(
    rawValue: 0x1,
    kindRawValue: 0x1,
    isPackRequirement: false,
    hasKeyArgument: false,
    isValueRequirement: false
    )

    static let layoutOnly = Entry(
    rawValue: 0x1f,
    kindRawValue: 0x1f,
    isPackRequirement: false,
    hasKeyArgument: false,
    isValueRequirement: false
    )

    static let protocolWithKey = Entry(
    rawValue: 0x80,
    kindRawValue: 0x0,
    isPackRequirement: false,
    hasKeyArgument: true,
    isValueRequirement: false
    )

    static let packWithKey = Entry(
    rawValue: 0xa0,
    kindRawValue: 0x0,
    isPackRequirement: true,
    hasKeyArgument: true,
    isValueRequirement: false
    )

    static let valueRequirement = Entry(
    rawValue: 0x100,
    kindRawValue: 0x0,
    isPackRequirement: false,
    hasKeyArgument: false,
    isValueRequirement: true
    )
}

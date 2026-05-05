// AUTO-GENERATED — DO NOT EDIT.
// Regenerate via: Scripts/regen-baselines.sh
// Source fixture: SymbolTestsCore.framework

enum ProtocolRequirementFlagsBaseline {
    static let registeredTestMethodNames: Set<String> = ["init(rawValue:)", "isAsync", "isCoroutine", "isInstance", "kind", "maybeAsync", "rawValue"]

    struct Entry {
        let rawValue: UInt32
        let kindRawValue: UInt8
        let isCoroutine: Bool
        let isAsync: Bool
        let isInstance: Bool
    }

    static let witnessTableMethod = Entry(
    rawValue: 0x11,
    kindRawValue: 0x1,
    isCoroutine: false,
    isAsync: false,
    isInstance: true
    )

    static let readCoroutine = Entry(
    rawValue: 0x5,
    kindRawValue: 0x5,
    isCoroutine: true,
    isAsync: false,
    isInstance: false
    )

    static let methodAsync = Entry(
    rawValue: 0x21,
    kindRawValue: 0x1,
    isCoroutine: false,
    isAsync: true,
    isInstance: false
    )
}

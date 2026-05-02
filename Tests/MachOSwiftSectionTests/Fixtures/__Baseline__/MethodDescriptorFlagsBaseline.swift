// AUTO-GENERATED — DO NOT EDIT.
// Regenerate via: Scripts/regen-baselines.sh
// Source fixture: SymbolTestsCore.framework

enum MethodDescriptorFlagsBaseline {
    static let registeredTestMethodNames: Set<String> = ["_hasAsyncBitSet", "extraDiscriminator", "init(rawValue:)", "isAsync", "isCalleeAllocatedCoroutine", "isCoroutine", "isData", "isDynamic", "isInstance", "kind", "rawValue"]

    struct Entry {
        let rawValue: UInt32
        let kindRawValue: UInt8
        let isDynamic: Bool
        let isInstance: Bool
        let hasAsyncBitSet: Bool
        let isAsync: Bool
        let isCoroutine: Bool
        let isCalleeAllocatedCoroutine: Bool
        let isData: Bool
        let extraDiscriminator: UInt16
    }

    static let firstClassTestMethod = Entry(
    rawValue: 0x12,
    kindRawValue: 0x2,
    isDynamic: false,
    isInstance: true,
    hasAsyncBitSet: false,
    isAsync: false,
    isCoroutine: false,
    isCalleeAllocatedCoroutine: false,
    isData: false,
    extraDiscriminator: 0x0
    )
}

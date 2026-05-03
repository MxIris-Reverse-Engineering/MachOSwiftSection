// AUTO-GENERATED — DO NOT EDIT.
// Regenerate via: Scripts/regen-baselines.sh
// Source fixture: SymbolTestsCore.framework
//
// FunctionTypeFlags is a pure raw-value bit decoder (no MachO
// dependency). The baseline embeds canonical synthetic raw
// values exercising each documented bit field; convention is
// restricted to safe low-byte values (see source-file comment).

enum FunctionTypeFlagsBaseline {
    static let registeredTestMethodNames: Set<String> = ["convention", "hasExtendedFlags", "hasGlobalActor", "hasParameterFlags", "init(rawValue:)", "isAsync", "isDifferentiable", "isEscaping", "isSendable", "isThrowing", "numberOfParameters", "rawValue"]

    struct Entry {
        let rawValue: UInt64
        let numberOfParameters: UInt64
        let conventionRawValue: UInt8
        let isThrowing: Bool
        let isEscaping: Bool
        let isAsync: Bool
        let isSendable: Bool
        let hasParameterFlags: Bool
        let isDifferentiable: Bool
        let hasGlobalActor: Bool
        let hasExtendedFlags: Bool
    }

    static let cases: [Entry] = [
        // emptySwiftConvention
        Entry(
            rawValue: 0x0,
            numberOfParameters: 0x0,
            conventionRawValue: 0x0,
            isThrowing: false,
            isEscaping: false,
            isAsync: false,
            isSendable: false,
            hasParameterFlags: false,
            isDifferentiable: false,
            hasGlobalActor: false,
            hasExtendedFlags: false
        ),
        // oneParamBlock
        Entry(
            rawValue: 0x1,
            numberOfParameters: 0x1,
            conventionRawValue: 0x1,
            isThrowing: false,
            isEscaping: false,
            isAsync: false,
            isSendable: false,
            hasParameterFlags: false,
            isDifferentiable: false,
            hasGlobalActor: false,
            hasExtendedFlags: false
        ),
        // twoParamsThin
        Entry(
            rawValue: 0x2,
            numberOfParameters: 0x2,
            conventionRawValue: 0x2,
            isThrowing: false,
            isEscaping: false,
            isAsync: false,
            isSendable: false,
            hasParameterFlags: false,
            isDifferentiable: false,
            hasGlobalActor: false,
            hasExtendedFlags: false
        ),
        // threeParamsCFunctionPointer
        Entry(
            rawValue: 0x3,
            numberOfParameters: 0x3,
            conventionRawValue: 0x3,
            isThrowing: false,
            isEscaping: false,
            isAsync: false,
            isSendable: false,
            hasParameterFlags: false,
            isDifferentiable: false,
            hasGlobalActor: false,
            hasExtendedFlags: false
        )
    ]
}

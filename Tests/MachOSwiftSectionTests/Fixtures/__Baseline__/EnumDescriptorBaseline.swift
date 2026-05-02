// AUTO-GENERATED — DO NOT EDIT.
// Regenerate via: Scripts/regen-baselines.sh
// Source fixture: SymbolTestsCore.framework

enum EnumDescriptorBaseline {
    static let registeredTestMethodNames: Set<String> = ["hasPayloadCases", "hasPayloadSizeOffset", "isMultiPayload", "isSingleEmptyCaseOnly", "isSinglePayload", "isSinglePayloadCaseOnly", "layout", "numberOfCases", "numberOfEmptyCases", "numberOfPayloadCases", "offset", "payloadSizeOffset"]

    struct Entry {
        let offset: Int
        let layoutNumPayloadCasesAndPayloadSizeOffset: UInt32
        let layoutNumEmptyCases: UInt32
        let layoutFlagsRawValue: UInt32
        let numberOfCases: Int
        let numberOfEmptyCases: Int
        let numberOfPayloadCases: Int
        let payloadSizeOffset: Int
        let hasPayloadSizeOffset: Bool
        let isSingleEmptyCaseOnly: Bool
        let isSinglePayloadCaseOnly: Bool
        let isSinglePayload: Bool
        let isMultiPayload: Bool
        let hasPayloadCases: Bool
    }

    static let noPayloadEnumTest = Entry(
    offset: 0x32f10,
    layoutNumPayloadCasesAndPayloadSizeOffset: 0x0,
    layoutNumEmptyCases: 0x4,
    layoutFlagsRawValue: 0x52,
    numberOfCases: 4,
    numberOfEmptyCases: 4,
    numberOfPayloadCases: 0,
    payloadSizeOffset: 0,
    hasPayloadSizeOffset: false,
    isSingleEmptyCaseOnly: false,
    isSinglePayloadCaseOnly: false,
    isSinglePayload: false,
    isMultiPayload: false,
    hasPayloadCases: false
    )

    static let singlePayloadEnumTest = Entry(
    offset: 0x32f2c,
    layoutNumPayloadCasesAndPayloadSizeOffset: 0x1,
    layoutNumEmptyCases: 0x2,
    layoutFlagsRawValue: 0x52,
    numberOfCases: 3,
    numberOfEmptyCases: 2,
    numberOfPayloadCases: 1,
    payloadSizeOffset: 0,
    hasPayloadSizeOffset: false,
    isSingleEmptyCaseOnly: false,
    isSinglePayloadCaseOnly: false,
    isSinglePayload: true,
    isMultiPayload: false,
    hasPayloadCases: true
    )

    static let multiPayloadEnumTest = Entry(
    offset: 0x32eb0,
    layoutNumPayloadCasesAndPayloadSizeOffset: 0x3,
    layoutNumEmptyCases: 0x1,
    layoutFlagsRawValue: 0x52,
    numberOfCases: 4,
    numberOfEmptyCases: 1,
    numberOfPayloadCases: 3,
    payloadSizeOffset: 0,
    hasPayloadSizeOffset: false,
    isSingleEmptyCaseOnly: false,
    isSinglePayloadCaseOnly: false,
    isSinglePayload: false,
    isMultiPayload: true,
    hasPayloadCases: true
    )
}

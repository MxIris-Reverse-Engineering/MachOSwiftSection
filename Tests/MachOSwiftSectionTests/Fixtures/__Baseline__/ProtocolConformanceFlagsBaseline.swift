// AUTO-GENERATED — DO NOT EDIT.
// Regenerate via: Scripts/regen-baselines.sh
// Source fixture: SymbolTestsCore.framework

enum ProtocolConformanceFlagsBaseline {
    static let registeredTestMethodNames: Set<String> = ["hasGenericWitnessTable", "hasGlobalActorIsolation", "hasNonDefaultSerialExecutorIsIsolatingCurrentContext", "hasResilientWitnesses", "init(rawValue:)", "isConformanceOfProtocol", "isRetroactive", "isSynthesizedNonUnique", "numConditionalPackShapeDescriptors", "numConditionalRequirements", "rawValue", "typeReferenceKind"]

    struct Entry {
        let rawValue: UInt32
        let typeReferenceKindRawValue: UInt8
        let isRetroactive: Bool
        let isSynthesizedNonUnique: Bool
        let isConformanceOfProtocol: Bool
        let hasGlobalActorIsolation: Bool
        let hasNonDefaultSerialExecutorIsIsolatingCurrentContext: Bool
        let hasResilientWitnesses: Bool
        let hasGenericWitnessTable: Bool
        let numConditionalRequirements: UInt32
        let numConditionalPackShapeDescriptors: UInt32
    }

    static let structTestProtocolTest = Entry(
    rawValue: 0x20000,
    typeReferenceKindRawValue: 0x0,
    isRetroactive: false,
    isSynthesizedNonUnique: false,
    isConformanceOfProtocol: false,
    hasGlobalActorIsolation: false,
    hasNonDefaultSerialExecutorIsIsolatingCurrentContext: false,
    hasResilientWitnesses: false,
    hasGenericWitnessTable: true,
    numConditionalRequirements: 0x0,
    numConditionalPackShapeDescriptors: 0x0
    )

    static let conditionalFirst = Entry(
    rawValue: 0x30100,
    typeReferenceKindRawValue: 0x0,
    isRetroactive: false,
    isSynthesizedNonUnique: false,
    isConformanceOfProtocol: false,
    hasGlobalActorIsolation: false,
    hasNonDefaultSerialExecutorIsIsolatingCurrentContext: false,
    hasResilientWitnesses: true,
    hasGenericWitnessTable: true,
    numConditionalRequirements: 0x1,
    numConditionalPackShapeDescriptors: 0x0
    )

    static let globalActorFirst = Entry(
    rawValue: 0x80000,
    typeReferenceKindRawValue: 0x0,
    isRetroactive: false,
    isSynthesizedNonUnique: false,
    isConformanceOfProtocol: false,
    hasGlobalActorIsolation: true,
    hasNonDefaultSerialExecutorIsIsolatingCurrentContext: false,
    hasResilientWitnesses: false,
    hasGenericWitnessTable: false,
    numConditionalRequirements: 0x0,
    numConditionalPackShapeDescriptors: 0x0
    )

    static let resilientFirst = Entry(
    rawValue: 0x30000,
    typeReferenceKindRawValue: 0x0,
    isRetroactive: false,
    isSynthesizedNonUnique: false,
    isConformanceOfProtocol: false,
    hasGlobalActorIsolation: false,
    hasNonDefaultSerialExecutorIsIsolatingCurrentContext: false,
    hasResilientWitnesses: true,
    hasGenericWitnessTable: true,
    numConditionalRequirements: 0x0,
    numConditionalPackShapeDescriptors: 0x0
    )
}

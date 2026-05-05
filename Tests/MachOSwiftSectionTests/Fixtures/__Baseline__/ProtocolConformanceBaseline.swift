// AUTO-GENERATED — DO NOT EDIT.
// Regenerate via: Scripts/regen-baselines.sh
// Source fixture: SymbolTestsCore.framework

enum ProtocolConformanceBaseline {
    static let registeredTestMethodNames: Set<String> = ["conditionalPackShapeDescriptors", "conditionalRequirements", "descriptor", "flags", "genericWitnessTable", "globalActorReference", "init(descriptor:)", "init(descriptor:in:)", "protocol", "resilientWitnesses", "resilientWitnessesHeader", "retroactiveContextDescriptor", "typeReference", "witnessTablePattern"]

    struct Entry {
        let descriptorOffset: Int
        let flagsRawValue: UInt32
        let hasProtocol: Bool
        let hasWitnessTablePattern: Bool
        let hasRetroactiveContextDescriptor: Bool
        let conditionalRequirementsCount: Int
        let conditionalPackShapeDescriptorsCount: Int
        let hasResilientWitnessesHeader: Bool
        let resilientWitnessesCount: Int
        let hasGenericWitnessTable: Bool
        let hasGlobalActorReference: Bool
    }

    static let structTestProtocolTest = Entry(
    descriptorOffset: 0x2f490,
    flagsRawValue: 0x20000,
    hasProtocol: true,
    hasWitnessTablePattern: true,
    hasRetroactiveContextDescriptor: false,
    conditionalRequirementsCount: 0,
    conditionalPackShapeDescriptorsCount: 0,
    hasResilientWitnessesHeader: false,
    resilientWitnessesCount: 0,
    hasGenericWitnessTable: true,
    hasGlobalActorReference: false
    )

    static let conditionalFirst = Entry(
    descriptorOffset: 0x2b740,
    flagsRawValue: 0x30100,
    hasProtocol: true,
    hasWitnessTablePattern: true,
    hasRetroactiveContextDescriptor: false,
    conditionalRequirementsCount: 1,
    conditionalPackShapeDescriptorsCount: 0,
    hasResilientWitnessesHeader: true,
    resilientWitnessesCount: 1,
    hasGenericWitnessTable: true,
    hasGlobalActorReference: false
    )

    static let globalActorFirst = Entry(
    descriptorOffset: 0x297a4,
    flagsRawValue: 0x80000,
    hasProtocol: true,
    hasWitnessTablePattern: true,
    hasRetroactiveContextDescriptor: false,
    conditionalRequirementsCount: 0,
    conditionalPackShapeDescriptorsCount: 0,
    hasResilientWitnessesHeader: false,
    resilientWitnessesCount: 0,
    hasGenericWitnessTable: false,
    hasGlobalActorReference: true
    )

    static let resilientFirst = Entry(
    descriptorOffset: 0x29714,
    flagsRawValue: 0x30000,
    hasProtocol: true,
    hasWitnessTablePattern: true,
    hasRetroactiveContextDescriptor: false,
    conditionalRequirementsCount: 0,
    conditionalPackShapeDescriptorsCount: 0,
    hasResilientWitnessesHeader: true,
    resilientWitnessesCount: 1,
    hasGenericWitnessTable: true,
    hasGlobalActorReference: false
    )
}

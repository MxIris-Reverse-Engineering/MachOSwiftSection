// AUTO-GENERATED — DO NOT EDIT.
// Regenerate via: Scripts/regen-baselines.sh
// Source fixture: SymbolTestsCore.framework

enum ProtocolBaseline {
    static let registeredTestMethodNames: Set<String> = ["baseRequirement", "descriptor", "init(descriptor:)", "init(descriptor:in:)", "name", "numberOfRequirements", "numberOfRequirementsInSignature", "protocolFlags", "requirementInSignatures", "requirements"]

    struct Entry {
        let name: String
        let descriptorOffset: Int
        let protocolFlagsRawValue: UInt16
        let numberOfRequirements: Int
        let numberOfRequirementsInSignature: Int
        let hasBaseRequirement: Bool
        let requirementsCount: Int
        let requirementInSignaturesCount: Int
    }

    static let protocolTest = Entry(
    name: "ProtocolTest",
    descriptorOffset: 0x36538,
    protocolFlagsRawValue: 0x3,
    numberOfRequirements: 4,
    numberOfRequirementsInSignature: 1,
    hasBaseRequirement: true,
    requirementsCount: 4,
    requirementInSignaturesCount: 1
    )

    static let protocolWitnessTableTest = Entry(
    name: "ProtocolWitnessTableTest",
    descriptorOffset: 0x3657c,
    protocolFlagsRawValue: 0x3,
    numberOfRequirements: 5,
    numberOfRequirementsInSignature: 0,
    hasBaseRequirement: true,
    requirementsCount: 5,
    requirementInSignaturesCount: 0
    )
}

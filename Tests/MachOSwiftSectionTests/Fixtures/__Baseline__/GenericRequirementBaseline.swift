// AUTO-GENERATED — DO NOT EDIT.
// Regenerate via: Scripts/regen-baselines.sh
// Source fixture: SymbolTestsCore.framework

enum GenericRequirementBaseline {
    static let registeredTestMethodNames: Set<String> = ["content", "descriptor", "init(descriptor:)", "init(descriptor:in:)", "paramManagledName"]

    struct Entry {
        let descriptorOffset: Int
        let resolvedContentCase: String
    }

    static let layoutRequirement = Entry(
    descriptorOffset: 0x3f058,
    resolvedContentCase: "layout"
    )

    static let swiftProtocolRequirement = Entry(
    descriptorOffset: 0x3f094,
    resolvedContentCase: "protocol"
    )

    static let objcProtocolRequirement = Entry(
    descriptorOffset: 0x3f0d0,
    resolvedContentCase: "protocol"
    )

    static let baseClassRequirement = Entry(
    descriptorOffset: 0x40098,
    resolvedContentCase: "type"
    )

    static let sameTypeRequirement = Entry(
    descriptorOffset: 0x40008,
    resolvedContentCase: "type"
    )
}

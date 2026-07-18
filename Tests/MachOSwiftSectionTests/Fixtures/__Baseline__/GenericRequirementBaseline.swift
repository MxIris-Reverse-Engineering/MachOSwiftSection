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
    descriptorOffset: 0x40944,
    resolvedContentCase: "layout"
    )

    static let swiftProtocolRequirement = Entry(
    descriptorOffset: 0x40980,
    resolvedContentCase: "protocol"
    )

    static let objcProtocolRequirement = Entry(
    descriptorOffset: 0x409bc,
    resolvedContentCase: "protocol"
    )

    static let baseClassRequirement = Entry(
    descriptorOffset: 0x41984,
    resolvedContentCase: "type"
    )

    static let sameTypeRequirement = Entry(
    descriptorOffset: 0x418f4,
    resolvedContentCase: "type"
    )
}

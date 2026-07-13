// AUTO-GENERATED — DO NOT EDIT.
// Regenerate via: Scripts/regen-baselines.sh
// Source fixture: SymbolTestsCore.framework

enum GenericRequirementDescriptorBaseline {
    static let registeredTestMethodNames: Set<String> = ["content", "isContentEqual", "layout", "offset", "paramMangledName", "resolvedContent", "type"]

    struct Entry {
        let offset: Int
        let flagsRawValue: UInt32
        let kindRawValue: UInt8
        let contentKindCase: String
    }

    static let layoutRequirement = Entry(
    offset: 0x3a4d0,
    flagsRawValue: 0x1f,
    kindRawValue: 0x1f,
    contentKindCase: "layout"
    )

    static let swiftProtocolRequirement = Entry(
    offset: 0x3a50c,
    flagsRawValue: 0x80,
    kindRawValue: 0x0,
    contentKindCase: "protocol"
    )

    static let objcProtocolRequirement = Entry(
    offset: 0x3a548,
    flagsRawValue: 0x0,
    kindRawValue: 0x0,
    contentKindCase: "protocol"
    )

    static let baseClassRequirement = Entry(
    offset: 0x3acf0,
    flagsRawValue: 0x2,
    kindRawValue: 0x2,
    contentKindCase: "type"
    )

    static let sameTypeRequirement = Entry(
    offset: 0x3ac60,
    flagsRawValue: 0x1,
    kindRawValue: 0x1,
    contentKindCase: "type"
    )
}

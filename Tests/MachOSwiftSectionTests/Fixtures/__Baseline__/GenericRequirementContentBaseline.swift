// AUTO-GENERATED — DO NOT EDIT.
// Regenerate via: Scripts/regen-baselines.sh
// Source fixture: SymbolTestsCore.framework
//
// Only GenericRequirementContent.InvertedProtocols has visible public
// surface (case-iterating helpers on the parent enums are emitted
// by macros and not visited by PublicMemberScanner).

enum GenericRequirementContentBaseline {
    static let registeredTestMethodNames: Set<String> = ["genericParamIndex", "protocols"]

    struct Entry {
        let genericParamIndex: UInt16
        let protocolsRawValue: UInt16
    }

    static let invertibleProtocolRequirement = Entry(
    genericParamIndex: 0,
    protocolsRawValue: 0x1
    )
}

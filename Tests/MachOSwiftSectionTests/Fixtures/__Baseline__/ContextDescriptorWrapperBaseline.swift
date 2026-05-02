// AUTO-GENERATED — DO NOT EDIT.
// Regenerate via: Scripts/regen-baselines.sh
// Source fixture: SymbolTestsCore.framework
//
// Picker: `Structs.StructTest` — an `isStruct: true` representative.
// Other `is*` accessors are all `false` for this picker; broader
// kind coverage lives in the dedicated concrete-kind Suites.

enum ContextDescriptorWrapperBaseline {
    static let registeredTestMethodNames: Set<String> = ["anonymousContextDescriptor", "contextDescriptor", "extensionContextDescriptor", "genericContext", "isAnonymous", "isClass", "isEnum", "isExtension", "isModule", "isOpaqueType", "isProtocol", "isStruct", "isType", "moduleContextDescriptor", "namedContextDescriptor", "opaqueTypeDescriptor", "parent", "protocolDescriptor", "resolve", "typeContextDescriptor", "typeContextDescriptorWrapper"]

    struct Entry {
        let descriptorOffset: Int
        let isType: Bool
        let isStruct: Bool
        let isClass: Bool
        let isEnum: Bool
        let isProtocol: Bool
        let isAnonymous: Bool
        let isExtension: Bool
        let isModule: Bool
        let isOpaqueType: Bool
        let hasProtocolDescriptor: Bool
        let hasExtensionContextDescriptor: Bool
        let hasOpaqueTypeDescriptor: Bool
        let hasModuleContextDescriptor: Bool
        let hasAnonymousContextDescriptor: Bool
        let hasTypeContextDescriptor: Bool
        let hasTypeContextDescriptorWrapper: Bool
        let hasNamedContextDescriptor: Bool
        let hasParent: Bool
        let hasGenericContext: Bool
    }

    static let structTest = Entry(
    descriptorOffset: 0x35240,
    isType: true,
    isStruct: true,
    isClass: false,
    isEnum: false,
    isProtocol: false,
    isAnonymous: false,
    isExtension: false,
    isModule: false,
    isOpaqueType: false,
    hasProtocolDescriptor: false,
    hasExtensionContextDescriptor: false,
    hasOpaqueTypeDescriptor: false,
    hasModuleContextDescriptor: false,
    hasAnonymousContextDescriptor: false,
    hasTypeContextDescriptor: true,
    hasTypeContextDescriptorWrapper: true,
    hasNamedContextDescriptor: true,
    hasParent: true,
    hasGenericContext: false
    )
}

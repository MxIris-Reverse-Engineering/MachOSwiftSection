/// These options mimic those used in the Swift project. Check that project for details.
public struct DemangleOptions: OptionSet, Codable, Sendable {
    public let rawValue: Int

    public static let synthesizeSugarOnTypes = DemangleOptions(rawValue: 1 << 0)
    public static let displayDebuggerGeneratedModule = DemangleOptions(rawValue: 1 << 1)
    public static let qualifyEntities = DemangleOptions(rawValue: 1 << 2)
    public static let displayExtensionContexts = DemangleOptions(rawValue: 1 << 3)
    public static let displayUnmangledSuffix = DemangleOptions(rawValue: 1 << 4)
    public static let displayModuleNames = DemangleOptions(rawValue: 1 << 5)
    public static let displayGenericSpecializations = DemangleOptions(rawValue: 1 << 6)
    public static let displayProtocolConformances = DemangleOptions(rawValue: 1 << 7)
    public static let displayWhereClauses = DemangleOptions(rawValue: 1 << 8)
    public static let displayEntityTypes = DemangleOptions(rawValue: 1 << 9)
    public static let shortenPartialApply = DemangleOptions(rawValue: 1 << 10)
    public static let shortenThunk = DemangleOptions(rawValue: 1 << 11)
    public static let shortenValueWitness = DemangleOptions(rawValue: 1 << 12)
    public static let shortenArchetype = DemangleOptions(rawValue: 1 << 13)
    public static let showPrivateDiscriminators = DemangleOptions(rawValue: 1 << 14)
    public static let showFunctionArgumentTypes = DemangleOptions(rawValue: 1 << 15)
    public static let showAsyncResumePartial = DemangleOptions(rawValue: 1 << 16)
    public static let displayStdlibModule = DemangleOptions(rawValue: 1 << 17)
    public static let displayObjCModule = DemangleOptions(rawValue: 1 << 18)
    public static let printForTypeName = DemangleOptions(rawValue: 1 << 19)
    public static let showClosureSignature = DemangleOptions(rawValue: 1 << 20)
    public static let showModuleInDependentMemberType = DemangleOptions(rawValue: 1 << 21)
    
    package static let removeWeakPrefix = DemangleOptions(rawValue: 1 << 100)
    
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let `default`: DemangleOptions = [
        .displayDebuggerGeneratedModule,
        .qualifyEntities,
        .displayExtensionContexts,
        .displayUnmangledSuffix,
        .displayModuleNames,
        .displayGenericSpecializations,
        .displayProtocolConformances,
        .displayWhereClauses,
        .displayEntityTypes,
        .showPrivateDiscriminators,
        .showFunctionArgumentTypes,
        .showAsyncResumePartial,
        .displayStdlibModule,
        .displayObjCModule,
        .showClosureSignature,
        .showModuleInDependentMemberType
    ]
    
    public static let simplified: DemangleOptions = [
        .synthesizeSugarOnTypes,
        .qualifyEntities,
        .shortenPartialApply,
        .shortenThunk,
        .shortenValueWitness,
        .shortenArchetype
    ]
    
    public static let interface: DemangleOptions = {
        var options = DemangleOptions.default
        options.remove(.displayObjCModule)
        options.insert(.synthesizeSugarOnTypes)
        options.remove(.displayWhereClauses)
        options.remove(.displayExtensionContexts)
        options.remove(.showPrivateDiscriminators)
        options.remove(.showModuleInDependentMemberType)
        return options
    }()

}

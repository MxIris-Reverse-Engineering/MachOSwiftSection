/// These options mimic those used in the Swift project. Check that project for details.
public struct SymbolPrintOptions: OptionSet {
    public let rawValue: Int

    public static let synthesizeSugarOnTypes = SymbolPrintOptions(rawValue: 1 << 0)
    public static let displayDebuggerGeneratedModule = SymbolPrintOptions(rawValue: 1 << 1)
    public static let qualifyEntities = SymbolPrintOptions(rawValue: 1 << 2)
    public static let displayExtensionContexts = SymbolPrintOptions(rawValue: 1 << 3)
    public static let displayUnmangledSuffix = SymbolPrintOptions(rawValue: 1 << 4)
    public static let displayModuleNames = SymbolPrintOptions(rawValue: 1 << 5)
    public static let displayGenericSpecializations = SymbolPrintOptions(rawValue: 1 << 6)
    public static let displayProtocolConformances = SymbolPrintOptions(rawValue: 1 << 7)
    public static let displayWhereClauses = SymbolPrintOptions(rawValue: 1 << 8)
    public static let displayEntityTypes = SymbolPrintOptions(rawValue: 1 << 9)
    public static let shortenPartialApply = SymbolPrintOptions(rawValue: 1 << 10)
    public static let shortenThunk = SymbolPrintOptions(rawValue: 1 << 11)
    public static let shortenValueWitness = SymbolPrintOptions(rawValue: 1 << 12)
    public static let shortenArchetype = SymbolPrintOptions(rawValue: 1 << 13)
    public static let showPrivateDiscriminators = SymbolPrintOptions(rawValue: 1 << 14)
    public static let showFunctionArgumentTypes = SymbolPrintOptions(rawValue: 1 << 15)
    public static let showAsyncResumePartial = SymbolPrintOptions(rawValue: 1 << 16)
    public static let displayStdlibModule = SymbolPrintOptions(rawValue: 1 << 17)
    public static let displayObjCModule = SymbolPrintOptions(rawValue: 1 << 18)
    public static let printForTypeName = SymbolPrintOptions(rawValue: 1 << 19)
    public static let showClosureSignature = SymbolPrintOptions(rawValue: 1 << 20)

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let `default`: SymbolPrintOptions = [.displayDebuggerGeneratedModule, .qualifyEntities, .displayExtensionContexts, .displayUnmangledSuffix, .displayModuleNames, .displayGenericSpecializations, .displayProtocolConformances, .displayWhereClauses, .displayEntityTypes, .showPrivateDiscriminators, .showFunctionArgumentTypes, .showAsyncResumePartial, .displayStdlibModule, .displayObjCModule, .showClosureSignature]
    public static let simplified: SymbolPrintOptions = [.synthesizeSugarOnTypes, .qualifyEntities, .shortenPartialApply, .shortenThunk, .shortenValueWitness, .shortenArchetype]
}

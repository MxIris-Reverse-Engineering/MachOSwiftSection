import ArgumentParser
import SwiftDump

struct DemangleOptionGroup: ParsableArguments {
    enum PresetOptions: String, ExpressibleByArgument, CaseIterable {
        case `default`
        case simplified

        var options: DemangleOptions {
            switch self {
            case .default:
                return .default
            case .simplified:
                return .simplified
            }
        }
    }

    @Option(help: "Specify the Swift demangle options to use.")
    var demangleOptions: PresetOptions = .default

    @Flag(inversion: .prefixedEnableDisable)
    var synthesizeSugarOnTypes: Bool?
    @Flag(inversion: .prefixedEnableDisable)
    var displayDebuggerGeneratedModule: Bool?
    @Flag(inversion: .prefixedEnableDisable)
    var qualifyEntities: Bool?
    @Flag(inversion: .prefixedEnableDisable)
    var displayExtensionContexts: Bool?
    @Flag(inversion: .prefixedEnableDisable)
    var displayUnmangledSuffix: Bool?
    @Flag(inversion: .prefixedEnableDisable)
    var displayModuleNames: Bool?
    @Flag(inversion: .prefixedEnableDisable)
    var displayGenericSpecializations: Bool?
    @Flag(inversion: .prefixedEnableDisable)
    var displayProtocolConformances: Bool?
    @Flag(inversion: .prefixedEnableDisable)
    var displayWhereClauses: Bool?
    @Flag(inversion: .prefixedEnableDisable)
    var displayEntityTypes: Bool?
    @Flag(inversion: .prefixedEnableDisable)
    var shortenPartialApply: Bool?
    @Flag(inversion: .prefixedEnableDisable)
    var shortenThunk: Bool?
    @Flag(inversion: .prefixedEnableDisable)
    var shortenValueWitness: Bool?
    @Flag(inversion: .prefixedEnableDisable)
    var shortenArchetype: Bool?
    @Flag(inversion: .prefixedEnableDisable)
    var showPrivateDiscriminators: Bool?
    @Flag(inversion: .prefixedEnableDisable)
    var showFunctionArgumentTypes: Bool?
    @Flag(inversion: .prefixedEnableDisable)
    var showAsyncResumePartial: Bool?
    @Flag(inversion: .prefixedEnableDisable)
    var displayStdlibModule: Bool?
    @Flag(inversion: .prefixedEnableDisable)
    var displayObjCModule: Bool?
    @Flag(inversion: .prefixedEnableDisable)
    var printForTypeName: Bool?
    @Flag(inversion: .prefixedEnableDisable)
    var showClosureSignature: Bool?
    @Flag(inversion: .prefixedEnableDisable)
    var showModuleInDependentMemberType: Bool?
    @Flag(inversion: .prefixedEnableDisable)
    var showPrefixAndSuffix: Bool?
    
    
    func buildSwiftDumpDemangleOptions() -> SwiftDump.DemangleOptions {
        var options = demangleOptions.options
        if let synthesizeSugarOnTypes = synthesizeSugarOnTypes {
            options = options.update(.synthesizeSugarOnTypes, enabled: synthesizeSugarOnTypes)
        }
        if let displayDebuggerGeneratedModule = displayDebuggerGeneratedModule {
            options = options.update(.displayDebuggerGeneratedModule, enabled: displayDebuggerGeneratedModule)
        }
        if let qualifyEntities = qualifyEntities {
            options = options.update(.qualifyEntities, enabled: qualifyEntities)
        }
        if let displayExtensionContexts = displayExtensionContexts {
            options = options.update(.displayExtensionContexts, enabled: displayExtensionContexts)
        }
        if let displayUnmangledSuffix = displayUnmangledSuffix {
            options = options.update(.displayUnmangledSuffix, enabled: displayUnmangledSuffix)
        }
        if let displayModuleNames = displayModuleNames {
            options = options.update(.displayModuleNames, enabled: displayModuleNames)
        }
        if let displayGenericSpecializations = displayGenericSpecializations {
            options = options.update(.displayGenericSpecializations, enabled: displayGenericSpecializations)
        }
        if let displayProtocolConformances = displayProtocolConformances {
            options = options.update(.displayProtocolConformances, enabled: displayProtocolConformances)
        }
        if let displayWhereClauses = displayWhereClauses {
            options = options.update(.displayWhereClauses, enabled: displayWhereClauses)
        }
        if let displayEntityTypes = displayEntityTypes {
            options = options.update(.displayEntityTypes, enabled: displayEntityTypes)
        }
        if let shortenPartialApply = shortenPartialApply {
            options = options.update(.shortenPartialApply, enabled: shortenPartialApply)
        }
        if let shortenThunk = shortenThunk {
            options = options.update(.shortenThunk, enabled: shortenThunk)
        }
        if let shortenValueWitness = shortenValueWitness {
            options = options.update(.shortenValueWitness, enabled: shortenValueWitness)
        }
        if let shortenArchetype = shortenArchetype {
            options = options.update(.shortenArchetype, enabled: shortenArchetype)
        }
        if let showPrivateDiscriminators = showPrivateDiscriminators {
            options = options.update(.showPrivateDiscriminators, enabled: showPrivateDiscriminators)
        }
        if let showFunctionArgumentTypes = showFunctionArgumentTypes {
            options = options.update(.showFunctionArgumentTypes, enabled: showFunctionArgumentTypes)
        }
        if let showAsyncResumePartial = showAsyncResumePartial {
            options = options.update(.showAsyncResumePartial, enabled: showAsyncResumePartial)
        }
        if let displayStdlibModule = displayStdlibModule {
            options = options.update(.displayStdlibModule, enabled: displayStdlibModule)
        }
        if let displayObjCModule = displayObjCModule {
            options = options.update(.displayObjCModule, enabled: displayObjCModule)
        }
        if let printForTypeName = printForTypeName {
            options = options.update(.printForTypeName, enabled: printForTypeName)
        }
        if let showClosureSignature = showClosureSignature {
            options = options.update(.showClosureSignature, enabled: showClosureSignature)
        }
        if let showModuleInDependentMemberType {
            options = options.update(.showModuleInDependentMemberType, enabled: showModuleInDependentMemberType)
        }
        if let showPrefixAndSuffix {
            options = options.update(.showPrefixAndSuffix, enabled: showPrefixAndSuffix)
        }
        return options
    }
}

extension OptionSet {
    func update(_ option: Self, enabled: Bool) -> Self {
        if enabled {
            return union(option)
        } else {
            return subtracting(option)
        }
    }
}

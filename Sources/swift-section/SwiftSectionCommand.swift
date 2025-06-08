import Foundation
import ArgumentParser
import MachOKit
import MachOFoundation
import MachOSwiftSection
import SwiftDump

@main
struct SwiftSectionCommand: AsyncParsableCommand {
    static let configuration: CommandConfiguration = .init(
        commandName: "swift-section",
        subcommands: [
            DumpCommand.self,
        ],
        defaultSubcommand: DumpCommand.self
    )
}

struct DumpCommand: AsyncParsableCommand {
    static let configuration: CommandConfiguration = .init(commandName: "dump")

    enum Section: String, ExpressibleByArgument, CaseIterable {
        case types
        case protocols
        case protocolConformances
        case associatedTypes
    }

    enum Architecture: String, ExpressibleByArgument, CaseIterable {
        case arm64
        case arm64e
        case x86_64

        var cpu: CPUSubType {
            switch self {
            case .arm64:
                return .arm64(.arm64_all)
            case .arm64e:
                return .arm64(.arm64e)
            case .x86_64:
                return .x86(.x86_64_all)
            }
        }
    }

    @Argument(help: "The path to the Mach-O file to dump.", completion: .file())
    var filePath: String

    @Option(name: .shortAndLong, help: "Write the output to a file instead of standard output.", completion: .file())
    var outputPath: String?

    @Option(name: .shortAndLong, help: "Specify the architecture to use for the dump. Defaults to the current architecture.")
    var architecture: Architecture?

    @OptionGroup
    var demangleOptionGroup: DemangleOptionGroup

    @Option(name: .shortAndLong, parsing: .remaining, help: "Specify the sections of information to dump.")
    var sections: [Section] = Section.allCases

//    @Flag(inversion: .prefixedEnableDisable, help: "Enable searching for metadata.")
    private var searchMetadata: Bool = false

    @IgnoreCoding
    private var metadataFinder: MetadataFinder<MachOFile>?

    private var dumpedString = ""

    @MainActor
    mutating func run() async throws {
        let file = try MachOKit.loadFromFile(url: URL(fileURLWithPath: filePath))
        let machOFile: MachOFile = switch file {
        case .machO(let machOFile):
            machOFile
        case .fat(let fatFile):
            try required(fatFile.machOFiles().first { $0.header.cpu.subtype == architecture?.cpu ?? CPU.current?.subtype } ?? fatFile.machOFiles().first)
        }

        if searchMetadata {
            metadataFinder = MetadataFinder(machO: machOFile)
        }

        let demangleOptions = demangleOptionGroup.buildSwiftDumpDemangleOptions()

        for section in sections {
            switch section {
            case .types:
                try await dumpTypes(using: demangleOptions, in: machOFile)
            case .protocols:
                try await dumpProtocols(using: demangleOptions, in: machOFile)
            case .protocolConformances:
                try await dumpProtocolConformances(using: demangleOptions, in: machOFile)
            case .associatedTypes:
                try await dumpAssociatedTypes(using: demangleOptions, in: machOFile)
            }
        }

        if let outputPath {
            let outputURL = URL(fileURLWithPath: outputPath)
            try dumpedString.write(to: outputURL, atomically: true, encoding: .utf8)
        }
    }

    @MainActor
    private mutating func dumpTypes(using options: DemangleOptions, in machO: MachOFile) async throws {
        let typeContextDescriptors = try machO.swift.typeContextDescriptors

        for typeContextDescriptor in typeContextDescriptors {
            switch typeContextDescriptor {
            case .type(let typeContextDescriptorWrapper):
                switch typeContextDescriptorWrapper {
                case .enum(let enumDescriptor):
                    let enumType = try Enum(descriptor: enumDescriptor, in: machO)
                    try dumpOrPrint(enumType.dump(using: options, in: machO))
                case .struct(let structDescriptor):
                    let structType = try Struct(descriptor: structDescriptor, in: machO)
                    try dumpOrPrint(structType.dump(using: options, in: machO))
                    if let metadata = try metadataFinder?.metadata(for: structDescriptor) as StructMetadata? {
                        try dumpOrPrint(metadata.fieldOffsets(for: structDescriptor, in: machO))
                    }
                case .class(let classDescriptor):
                    let classType = try Class(descriptor: classDescriptor, in: machO)
                    try dumpOrPrint(classType.dump(using: options, in: machO))
                    if let metadata = try metadataFinder?.metadata(for: classDescriptor) as ClassMetadataObjCInterop? {
                        try dumpOrPrint(metadata.fieldOffsets(for: classDescriptor, in: machO))
                    }
                }
            default:
                break
            }
        }
    }

    @MainActor
    private mutating func dumpAssociatedTypes(using options: DemangleOptions, in machO: MachOFile) async throws {
        let associatedTypeDescriptors = try machO.swift.associatedTypeDescriptors
        for associatedTypeDescriptor in associatedTypeDescriptors {
            try dumpOrPrint(AssociatedType(descriptor: associatedTypeDescriptor, in: machO).dump(using: options, in: machO))
        }
    }

    @MainActor
    private mutating func dumpProtocols(using options: DemangleOptions, in machO: MachOFile) async throws {
        let protocolDescriptors = try machO.swift.protocolDescriptors
        for protocolDescriptor in protocolDescriptors {
            try dumpOrPrint(Protocol(descriptor: protocolDescriptor, in: machO).dump(using: options, in: machO))
        }
    }

    @MainActor
    private mutating func dumpProtocolConformances(using options: DemangleOptions, in machO: MachOFile) async throws {
        let protocolConformanceDescriptors = try machO.swift.protocolConformanceDescriptors

        for protocolConformanceDescriptor in protocolConformanceDescriptors {
            try dumpOrPrint(ProtocolConformance(descriptor: protocolConformanceDescriptor, in: machO).dump(using: options, in: machO))
        }
    }

    private mutating func dumpOrPrint<Value: CustomStringConvertible>(_ value: Value) {
        dumpOrPrint(value.description)
    }

    private mutating func dumpOrPrint(_ string: String) {
        if outputPath != nil {
            dumpedString.append(string)
            dumpedString.append("\n")
        } else {
            print(string)
        }
    }
}

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

    @Option(name: .shortAndLong, help: "Specify the Swift demangle options to use. Defaults to `.default`.")
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

@propertyWrapper
struct IgnoreCoding<Value> {
    var wrappedValue: Value

    init(wrappedValue: Value) {
        self.wrappedValue = wrappedValue
    }
}

extension IgnoreCoding: Codable where Value: OptionalProtocol {
    func encode(to encoder: Encoder) throws {
        // Skip encoding the wrapped value.
    }

    init(from decoder: Decoder) throws {
        // The wrapped value is simply initialised to nil when decoded.
        self.wrappedValue = nil
    }
}

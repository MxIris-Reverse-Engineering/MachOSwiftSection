import Foundation
import ArgumentParser
import MachOKit
import MachOFoundation
import MachOSwiftSection
import SwiftDump

enum Architecture: String, ExpressibleByArgument, CaseIterable {
    case x86_64
    case arm64
    case arm64e

    var cpu: CPUSubType {
        switch self {
        case .x86_64:
            return .x86(.x86_64_all)
        case .arm64:
            return .arm64(.arm64_all)
        case .arm64e:
            return .arm64(.arm64e)
        }
    }
}

struct MachOOptionGroup: ParsableArguments {
    @Argument(help: "The path to the Mach-O file or dyld shared cache to dump.", completion: .file())
    var filePath: String

    @Option(help: "The path to the dyld shared cache image. If filePath is a Mach-O file, this option is ignored.")
    var cacheImagePath: String?

    @Option(help: "The name of the dyld shared cache image. If filePath is a Mach-O file, this option is ignored.")
    var cacheImageName: String?

    @Flag(name: .customLong("dyld-shared-cache"), help: "The flag to indicate if the Mach-O file is a dyld shared cache.")
    var isDyldSharedCache: Bool = false

    @Flag(help: "Use the current dyld shared cache instead of the specified one. This option is ignored if filePath is a Mach-O file.")
    var usesSystemDyldSharedCache: Bool = false
    
    @Option(help: "The architecture of the Mach-O file. If not specified, the current architecture will be used.")
    var architecture: Architecture?
}

enum Section: String, ExpressibleByArgument, CaseIterable {
    case types
    case protocols
    case protocolConformances
    case associatedTypes
}

struct DumpCommand: AsyncParsableCommand {
    static let configuration: CommandConfiguration = .init(
        commandName: "dump",
        abstract: "Dump Swift information from a Mach-O file or dyld shared cache.",
    )

    @OptionGroup
    var machOOptions: MachOOptionGroup

    @OptionGroup
    var demangleOptions: DemangleOptionGroup

    @Option(name: .shortAndLong, help: "The output path for the dump. If not specified, the output will be printed to the console.", completion: .file())
    var outputPath: String?

    @Option(name: .shortAndLong, parsing: .remaining, help: "The sections to dump. If not specified, all sections will be dumped.")
    var sections: [Section] = Section.allCases

//    @Flag(inversion: .prefixedEnableDisable, help: "Enable searching for metadata.")
    private var searchMetadata: Bool = false

    @IgnoreCoding
    private var metadataFinder: MetadataFinder<MachOFile>?

    private var dumpedString = ""

    @MainActor
    mutating func run() async throws {
        let machOFile = try loadMachOFile(options: machOOptions)

        if searchMetadata {
            metadataFinder = MetadataFinder(machO: machOFile)
        }

        let demangleOptions = demangleOptions.buildSwiftDumpDemangleOptions()

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
            case let .type(typeContextDescriptorWrapper):
                switch typeContextDescriptorWrapper {
                case let .enum(enumDescriptor):
                    let enumType = try Enum(descriptor: enumDescriptor, in: machO)
                    try dumpOrPrint(enumType.dump(using: options, in: machO))
                case let .struct(structDescriptor):
                    let structType = try Struct(descriptor: structDescriptor, in: machO)
                    try dumpOrPrint(structType.dump(using: options, in: machO))
                    if let metadata = try metadataFinder?.metadata(for: structDescriptor) as StructMetadata? {
                        try dumpOrPrint(metadata.fieldOffsets(for: structDescriptor, in: machO))
                    }
                case let .class(classDescriptor):
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

enum SwiftSectionCommandError: LocalizedError {
    case ambiguousCacheImageNameAndCacheImagePath
    case missingCacheImageNameOrCacheImagePath
    case imageNotFound
    case invalidArchitecture
    case failedFetchFromSystemDyldSharedCache
    var errorDescription: String? {
        switch self {
        case .ambiguousCacheImageNameAndCacheImagePath:
            "Both cacheImageName and cacheImagePath are provided, but only one should be specified."
        case .missingCacheImageNameOrCacheImagePath:
            "Either cacheImageName or cacheImagePath must be provided when dyldSharedCache is true."
        case .imageNotFound:
            "The specified image was not found in the dyld shared cache."
        case .invalidArchitecture:
            "The specified architecture is not found or supported."
        case .failedFetchFromSystemDyldSharedCache:
            "Failed to fetch the Mach-O file from the current system dyld shared cache. Please ensure the cache is accessible."
        }
    }
}


func loadMachOFile(options: MachOOptionGroup) throws -> MachOFile {
    var url = URL(fileURLWithPath: options.filePath)
    if options.isDyldSharedCache {
        if options.usesSystemDyldSharedCache {
            guard let currentCPUType = CPUType.current else { throw SwiftSectionCommandError.failedFetchFromSystemDyldSharedCache }
            switch currentCPUType {
            case .x86_64:
                url = URL(fileURLWithPath: "/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_x86_64")
            case .arm64:
                url = URL(fileURLWithPath: "/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_arm64e")
            default:
                throw SwiftSectionCommandError.failedFetchFromSystemDyldSharedCache
            }
            
        }
        let dyldCache = try DyldCache(url: url)
        
        if let _ = options.cacheImagePath, let _ = options.cacheImageName {
            throw SwiftSectionCommandError.ambiguousCacheImageNameAndCacheImagePath
        } else if let cacheImageName = options.cacheImageName {
            return try required(dyldCache.machOFile(by: .name(cacheImageName)), error: SwiftSectionCommandError.imageNotFound)
        } else if let cacheImagePath = options.cacheImagePath {
            return try required(dyldCache.machOFile(by: .path(cacheImagePath)), error: SwiftSectionCommandError.imageNotFound)
        } else {
            throw SwiftSectionCommandError.missingCacheImageNameOrCacheImagePath
        }
    } else {
        let file = try MachOKit.loadFromFile(url: url)
        switch file {
        case let .machO(machOFile):
            return machOFile
        case let .fat(fatFile):
            return try required(fatFile.machOFiles().first { $0.header.cpu.subtype == options.architecture?.cpu ?? CPU.current?.subtype } ?? fatFile.machOFiles().first, error: SwiftSectionCommandError.invalidArchitecture)
        }
    }
    
}

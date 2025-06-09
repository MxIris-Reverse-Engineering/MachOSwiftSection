import Foundation
import ArgumentParser
import MachOKit
import MachOFoundation
import MachOSwiftSection
import SwiftDump

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
    var sections: [SwiftSection] = SwiftSection.allCases

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

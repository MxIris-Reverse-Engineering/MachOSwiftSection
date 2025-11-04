import Foundation
import ArgumentParser
import MachOKit
import MachOFoundation
import MachOSwiftSection
import SwiftDump
import Semantic

struct DumpCommand: AsyncParsableCommand {
    static let configuration: CommandConfiguration = .init(
        commandName: "dump",
        abstract: "Dump Swift information from a Mach-O file or dyld shared cache.",
    )

    private var dumpedString = ""
    
    @OptionGroup
    var machOOptions: MachOOptionGroup

    @OptionGroup
    var demangleOptions: DemangleOptionGroup

    @Option(name: .shortAndLong, help: "The output path for the dump. If not specified, the output will be printed to the console.", completion: .file())
    var outputPath: String?

    @Option(name: .shortAndLong, parsing: .upToNextOption, help: "The sections to dump. If not specified, all sections will be dumped.")
    var sections: [SwiftSection] = SwiftSection.allCases


    @Option(name: .shortAndLong, help: "The color scheme for the output.")
    var colorScheme: SemanticColorScheme = .none

    mutating func run() async throws {
        let machOFile = try MachOFile.load(options: machOOptions)

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
            case .enum(let enumDescriptor):
                await performDump {
                    try await Enum(descriptor: enumDescriptor, in: machO).dump(using: options, in: machO)
                }

            case .struct(let structDescriptor):
                await performDump {
                    try await Struct(descriptor: structDescriptor, in: machO).dump(using: options, in: machO)
                }

            case .class(let classDescriptor):
                await performDump {
                    try await Class(descriptor: classDescriptor, in: machO).dump(using: options, in: machO)
                }
            }
        }
    }

    @MainActor
    private mutating func dumpAssociatedTypes(using options: DemangleOptions, in machO: MachOFile) async throws {
        let associatedTypeDescriptors = try machO.swift.associatedTypeDescriptors
        for associatedTypeDescriptor in associatedTypeDescriptors {
            await performDump {
                try await AssociatedType(descriptor: associatedTypeDescriptor, in: machO).dump(using: options, in: machO)
            }
        }
    }

    @MainActor
    private mutating func dumpProtocols(using options: DemangleOptions, in machO: MachOFile) async throws {
        let protocolDescriptors = try machO.swift.protocolDescriptors
        for protocolDescriptor in protocolDescriptors {
            await performDump {
                try await Protocol(descriptor: protocolDescriptor, in: machO).dump(using: options, in: machO)
            }
        }
    }

    @MainActor
    private mutating func dumpProtocolConformances(using options: DemangleOptions, in machO: MachOFile) async throws {
        let protocolConformanceDescriptors = try machO.swift.protocolConformanceDescriptors

        for protocolConformanceDescriptor in protocolConformanceDescriptors {
            await performDump {
                try await ProtocolConformance(descriptor: protocolConformanceDescriptor, in: machO).dump(using: options, in: machO)
            }
        }
    }

    private mutating func performDump(@SemanticStringBuilder _ action: @Sendable () async throws -> SemanticString) async {
        do {
            try await dumpOrPrint(action())
        } catch {
            dumpError(error)
        }
    }

    private mutating func dumpError(_ error: Swift.Error) {
        dumpOrPrint(SemanticString(components: Error(error.localizedDescription)))
    }

    private mutating func dumpOrPrint(_ semanticString: SemanticString) {
        if outputPath != nil {
            dumpedString.append(semanticString.string)
            dumpedString.append("\n")
        } else {
            semanticString.printColorfully(using: colorScheme)
        }
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

extension SemanticString {
    func printColorfully(using colorScheme: SemanticColorScheme) {
        print(components.map { $0.string.withColor(for: $0.type, colorScheme: colorScheme) }.joined())
    }
}

import Foundation
import ArgumentParser
import MachOKit
import MachOFoundation
import MachOSwiftSection
import SwiftDump
import Semantic

final actor DumpCommand: AsyncParsableCommand {
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

    @Option(name: .shortAndLong, parsing: .upToNextOption, help: "The sections to dump. If not specified, all sections will be dumped.")
    var sections: [SwiftSection] = SwiftSection.allCases

//    @Flag(inversion: .prefixedEnableDisable, help: "Enable searching for metadata.")
    private var searchMetadata: Bool = false

    @IgnoreCoding
    private var metadataFinder: MetadataFinder<MachOFile>?

    private var dumpedString = ""

    @Option(name: .shortAndLong, help: "The color scheme for the output.")
    var colorScheme: SemanticColorScheme = .none

    func run() async throws {
        let machOFile = try MachOFile.load(options: machOOptions)

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
    private func dumpTypes(using options: DemangleOptions, in machO: MachOFile) async throws {
        let typeContextDescriptors = try machO.swift.typeContextDescriptors

        for typeContextDescriptor in typeContextDescriptors {
            switch typeContextDescriptor {
            case let .enum(enumDescriptor):
                await performDump {
                    try Enum(descriptor: enumDescriptor, in: machO).dump(using: options, in: machO)
                }
            case let .struct(structDescriptor):
                await performDump {
                    try Struct(descriptor: structDescriptor, in: machO).dump(using: options, in: machO)
                }

                if let metadata: StructMetadata = try await metadataFinder?.metadata(for: structDescriptor) {
                    await performDump {
                        try metadata.fieldOffsets(for: structDescriptor, in: machO)
                    }
                }
            case let .class(classDescriptor):
                await performDump {
                    try Class(descriptor: classDescriptor, in: machO).dump(using: options, in: machO)
                }

                if let metadata = try await metadataFinder?.metadata(for: classDescriptor) as ClassMetadataObjCInterop? {
                    await performDump {
                        try metadata.fieldOffsets(for: classDescriptor, in: machO)
                    }
                }
            }
        }
    }

    @MainActor
    private func dumpAssociatedTypes(using options: DemangleOptions, in machO: MachOFile) async throws {
        let associatedTypeDescriptors = try machO.swift.associatedTypeDescriptors
        for associatedTypeDescriptor in associatedTypeDescriptors {
            await performDump {
                try AssociatedType(descriptor: associatedTypeDescriptor, in: machO).dump(using: options, in: machO)
            }
        }
    }

    @MainActor
    private func dumpProtocols(using options: DemangleOptions, in machO: MachOFile) async throws {
        let protocolDescriptors = try machO.swift.protocolDescriptors
        for protocolDescriptor in protocolDescriptors {
            await performDump {
                try Protocol(descriptor: protocolDescriptor, in: machO).dump(using: options, in: machO)
            }
        }
    }

    @MainActor
    private func dumpProtocolConformances(using options: DemangleOptions, in machO: MachOFile) async throws {
        let protocolConformanceDescriptors = try machO.swift.protocolConformanceDescriptors

        for protocolConformanceDescriptor in protocolConformanceDescriptors {
            await performDump {
                try ProtocolConformance(descriptor: protocolConformanceDescriptor, in: machO).dump(using: options, in: machO)
            }
        }
    }

    private func performDump(@SemanticStringBuilder _ action: () async throws -> SemanticString) async {
        do {
            try await dumpOrPrint(action())
        } catch {
            dumpError(error)
        }
    }

    private func dumpError(_ error: Swift.Error) {
        dumpOrPrint(SemanticString(components: Error(error.localizedDescription)))
    }

    private func dumpOrPrint(_ semanticString: SemanticString) {
        if outputPath != nil {
            dumpedString.append(semanticString.string)
            dumpedString.append("\n")
        } else {
            print(semanticString.components.map { $0.string.withColor(for: $0.type, colorScheme: colorScheme) }.joined())
        }
    }

    private func dumpOrPrint(_ string: String) {
        if outputPath != nil {
            dumpedString.append(string)
            dumpedString.append("\n")
        } else {
            print(string)
        }
    }
}

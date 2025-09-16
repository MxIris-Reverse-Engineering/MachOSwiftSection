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

    @Flag(name: .customLong("emit-offsets"), help: "Enable emitting detailed offset information for data fields, virtual functions, and protocol witnesses.")
    var emitOffsets: Bool = false

//    @Flag(inversion: .prefixedEnableDisable, help: "Enable searching for metadata.")
    private var searchMetadata: Bool = false

    @IgnoreCoding
    private var metadataFinder: MetadataFinder<MachOFile>?

    private var dumpedString = ""

    @Option(name: .shortAndLong, help: "The color scheme for the output.")
    var colorScheme: SemanticColorScheme = .none

    func run() async throws {
        let machOFile = try MachOFile.load(options: machOOptions)

        if searchMetadata || emitOffsets {
            metadataFinder = MetadataFinder(machO: machOFile)
        }

        let demangleOptions = demangleOptions.buildSwiftDumpDemangleOptions()

        let shouldEmitOffsets = emitOffsets

        for section in sections {
            switch section {
            case .types:
                try await dumpTypes(using: demangleOptions, shouldEmitOffsets: shouldEmitOffsets, in: machOFile)
            case .protocols:
                try await dumpProtocols(using: demangleOptions, shouldEmitOffsets: shouldEmitOffsets, in: machOFile)
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
    private func dumpTypes(using options: DemangleOptions, shouldEmitOffsets: Bool, in machO: MachOFile) async throws {
        let typeContextDescriptors = try machO.swift.typeContextDescriptors

        for typeContextDescriptor in typeContextDescriptors {
            switch typeContextDescriptor {
            case .type(let typeContextDescriptorWrapper):
                switch typeContextDescriptorWrapper {
                case .enum(let enumDescriptor):
                    await performDump {
                        try Enum(descriptor: enumDescriptor, in: machO).dump(using: options, in: machO)
                    }
                case .struct(let structDescriptor):
                    await performDump {
                        try Struct(descriptor: structDescriptor, in: machO).dump(using: options, in: machO)
                    }

                    if shouldEmitOffsets {
                        if let metadata: StructMetadata = try await metadataFinder?.metadata(for: structDescriptor) {
                            await performDump {
                                try await dumpStructFieldOffsets(metadata: metadata, descriptor: structDescriptor, in: machO)
                            }
                        }
                    }
                case .class(let classDescriptor):
                    await performDump {
                        try Class(descriptor: classDescriptor, in: machO).dump(using: options, in: machO)
                    }

                    if shouldEmitOffsets {
                        if let metadata = try await metadataFinder?.metadata(for: classDescriptor) as ClassMetadataObjCInterop? {
                            await performDump {
                                try await dumpClassFieldOffsets(metadata: metadata, descriptor: classDescriptor, in: machO)
                            }
                            await performDump {
                                try await dumpClassVTableOffsets(metadata: metadata, classDescriptor: classDescriptor, in: machO)
                            }
                        }
                    }
                }
            default:
                break
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
    private func dumpProtocols(using options: DemangleOptions, shouldEmitOffsets: Bool, in machO: MachOFile) async throws {
        let protocolDescriptors = try machO.swift.protocolDescriptors

        for protocolDescriptor in protocolDescriptors {
            await performDump {
                try Protocol(descriptor: protocolDescriptor, in: machO).dump(using: options, in: machO)
            }
            if shouldEmitOffsets {
                await performDump {
                    try await dumpProtocolWitnessOffsets(descriptor: protocolDescriptor, in: machO)
                }
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

    // MARK: - Offset Dumping Methods

    private func dumpStructFieldOffsets<MachO: MachORepresentableWithCache & MachOReadable>(
        metadata: StructMetadata,
        descriptor: StructDescriptor,
        in machO: MachO
    ) async throws -> SemanticString {
        let offsets = try metadata.fieldOffsets(for: descriptor, in: machO)
        var components: [any SemanticStringComponent] = []

        components.append(Comment("Data Field Offsets:"))
        for (index, offset) in offsets.enumerated() {
            components.append(Comment("  Field \(index): 0x\(String(offset, radix: 16))"))
        }

        return SemanticString(components: components)
    }

    private func dumpClassFieldOffsets<MachO: MachORepresentableWithCache & MachOReadable>(
        metadata: ClassMetadataObjCInterop,
        descriptor: ClassDescriptor,
        in machO: MachO
    ) async throws -> SemanticString {
        let offsets = try metadata.fieldOffsets(for: descriptor, in: machO)
        var components: [any SemanticStringComponent] = []

        components.append(Comment("Data Field Offsets:"))
        for (index, offset) in offsets.enumerated() {
            components.append(Comment("  Field \(index): 0x\(String(offset, radix: 16))"))
        }

        return SemanticString(components: components)
    }

    private func dumpClassVTableOffsets<MachO: MachORepresentableWithCache & MachOReadable>(
        metadata: ClassMetadataObjCInterop,
        classDescriptor: ClassDescriptor,
        in machO: MachO
    ) async throws -> SemanticString {
        var components: [any SemanticStringComponent] = []

        components.append(Comment("Virtual Function Offsets:"))

        // Create Class object to access vtable information
        do {
            let classType = try Class(descriptor: classDescriptor, in: machO)
            if let vTableDescriptorHeader = classType.vTableDescriptorHeader {
                let vTableOffset = vTableDescriptorHeader.layout.vTableOffset
                let vTableSize = vTableDescriptorHeader.layout.vTableSize

                components.append(Comment("  VTable Offset: 0x\(String(vTableOffset, radix: 16))"))
                components.append(Comment("  VTable Size: \(vTableSize) entries"))

                // Calculate individual method offsets
                for i in 0..<vTableSize {
                    let methodOffset = vTableOffset + (i * UInt32(MemoryLayout<UInt64>.size))
                    components.append(Comment("  Method \(i): 0x\(String(methodOffset, radix: 16))"))
                }
            } else {
                components.append(Comment("  VTable information not available"))
            }
        } catch {
            components.append(Comment("  Error accessing class information: \(error.localizedDescription)"))
        }

        return SemanticString(components: components)
    }

    private func dumpProtocolWitnessOffsets(
        descriptor: ProtocolDescriptor,
        in machO: MachOFile
    ) async throws -> SemanticString {
        var components: [any SemanticStringComponent] = []

        components.append(Comment("Protocol Witness Offsets:"))

        // Look for protocol conformances that implement this protocol
        let protocolConformanceDescriptors = try machO.swift.protocolConformanceDescriptors
        let relatedConformances = protocolConformanceDescriptors.compactMap { conformance -> ProtocolConformanceDescriptor? in
            // Check if this conformance is for our protocol
            do {
                if let protocolSymbol = try conformance.protocolDescriptor(in: machO),
                   let conformanceProtocol = protocolSymbol.resolved {
                    return conformanceProtocol.offset == descriptor.offset ? conformance : nil
                } else {
                    return nil
                }
            } catch {
                return nil
            }
        }

        if relatedConformances.isEmpty {
            components.append(Comment("  No conformances found"))
        } else {
            for (index, conformance) in relatedConformances.enumerated() {
                components.append(Comment("  Conformance \(index): 0x\(String(conformance.offset, radix: 16))"))

                // Try to get witness table information
                if let witnessTablePattern = try? conformance.witnessTablePattern(in: machO) {
                    components.append(Comment("    Witness Table: 0x\(String(witnessTablePattern.offset, radix: 16))"))
                }
            }
        }

        return SemanticString(components: components)
    }
}

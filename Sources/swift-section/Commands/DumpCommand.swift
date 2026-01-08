import Foundation
import ArgumentParser
import MachOKit
import MachOFoundation
import MachOSwiftSection
import SwiftDump
import Semantic

struct DumpCommand: AsyncParsableCommand, Sendable {
    private enum TopLevelContext {
        case type(TypeContextWrapper)
        case `protocol`(MachOSwiftSection.`Protocol`)
        case protocolConformance(ProtocolConformance)
        case associatedType(AssociatedType)

        var offset: Int {
            switch self {
            case .type(let type):
                switch type {
                case .enum(let `enum`):
                    return `enum`.offset
                case .struct(let `struct`):
                    return `struct`.offset
                case .class(let `class`):
                    return `class`.offset
                }
            case .protocol(let `protocol`):
                return `protocol`.offset
            case .associatedType(let associatedType):
                return associatedType.offset
            case .protocolConformance(let protocolConformance):
                return protocolConformance.offset
            }
        }
    }

    static let configuration: CommandConfiguration = .init(
        commandName: "dump",
        abstract: "Dump Swift information from a Mach-O file or dyld shared cache."
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

    @Flag(help: "Generate field offset and PWT offset comments, if possible")
    var emitOffsetComments: Bool = false

    @Flag(help: "The definitions of types and protocols will be output in the order they are stored in the binary.")
    var preferredBinaryOrder: Bool = false

    mutating func run() async throws {
        let machOFile = try MachOFile.load(options: machOOptions)

        var dumpConfiguration: DumperConfiguration = .demangleOptions(demangleOptions.buildSwiftDumpDemangleOptions())

        dumpConfiguration.emitOffsetComments = emitOffsetComments

        if preferredBinaryOrder {
            var topLevelContexts: [TopLevelContext] = []
            if sections.contains(.types) {
                let types = (try? machOFile.swift.types.map { TopLevelContext.type($0) }) ?? []
                topLevelContexts.append(contentsOf: types)
            }

            if sections.contains(.protocols) {
                let protocols = (try? machOFile.swift.protocols.map { TopLevelContext.protocol($0) }) ?? []
                topLevelContexts.append(contentsOf: protocols)
            }

            topLevelContexts.sort(by: { $0.offset < $1.offset })

            if sections.contains(.protocolConformances) {
                let protocolConformances = (try? machOFile.swift.protocolConformances.map { TopLevelContext.protocolConformance($0) }) ?? []
                topLevelContexts.append(contentsOf: protocolConformances)
            }

            if sections.contains(.associatedTypes) {
                let associatedTypes = (try? machOFile.swift.associatedTypes.map { TopLevelContext.associatedType($0) }) ?? []
                topLevelContexts.append(contentsOf: associatedTypes)
            }

            for topLevelContext in topLevelContexts {
                switch topLevelContext {
                case .type(let type):
                    try? await dumpType(type, using: dumpConfiguration, in: machOFile)
                case .protocol(let `protocol`):
                    try? await dumpProtocol(`protocol`, using: dumpConfiguration, in: machOFile)
                case .protocolConformance(let protocolConformance):
                    try? await dumpProtocolConformance(protocolConformance, using: dumpConfiguration, in: machOFile)
                case .associatedType(let associatedType):
                    try? await dumpAssociatedType(associatedType, using: dumpConfiguration, in: machOFile)
                }
            }

        } else {
            for section in sections {
                switch section {
                case .types:
                    for type in (try? machOFile.swift.types) ?? [] {
                        try? await dumpType(type, using: dumpConfiguration, in: machOFile)
                    }
                case .protocols:
                    for `protocol` in (try? machOFile.swift.protocols) ?? [] {
                        try? await dumpProtocol(`protocol`, using: dumpConfiguration, in: machOFile)
                    }
                case .protocolConformances:
                    for protocolConformance in (try? machOFile.swift.protocolConformances) ?? [] {
                        try? await dumpProtocolConformance(protocolConformance, using: dumpConfiguration, in: machOFile)
                    }
                case .associatedTypes:
                    for associatedType in (try? machOFile.swift.associatedTypes) ?? [] {
                        try? await dumpAssociatedType(associatedType, using: dumpConfiguration, in: machOFile)
                    }
                }
            }
        }

        if let outputPath {
            let outputURL = URL(fileURLWithPath: outputPath)
            try dumpedString.write(to: outputURL, atomically: true, encoding: .utf8)
        }
    }

    @MainActor
    private mutating func dumpType(_ type: TypeContextWrapper, using configuration: DumperConfiguration, in machO: MachOFile) async throws {
        switch type {
        case .enum(let `enum`):
            await performDump {
                try await `enum`.dump(using: configuration, in: machO)
            }
        case .struct(let `struct`):
            await performDump {
                try await `struct`.dump(using: configuration, in: machO)
            }
        case .class(let `class`):
            await performDump {
                try await `class`.dump(using: configuration, in: machO)
            }
        }
    }

    @MainActor
    private mutating func dumpAssociatedType(_ associatedType: AssociatedType, using configuration: DumperConfiguration, in machO: MachOFile) async throws {
        await performDump {
            try await associatedType.dump(using: configuration, in: machO)
        }
    }

    @MainActor
    private mutating func dumpProtocol(_ protocol: MachOSwiftSection.`Protocol`, using configuration: DumperConfiguration, in machO: MachOFile) async throws {
        await performDump {
            try await `protocol`.dump(using: configuration, in: machO)
        }
    }

    @MainActor
    private mutating func dumpProtocolConformance(_ protocolConformance: ProtocolConformance, using configuration: DumperConfiguration, in machO: MachOFile) async throws {
        await performDump {
            try await protocolConformance.dump(using: configuration, in: machO)
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
        SemanticString(components: [Semantic.Error(error.localizedDescription)]).printColorfully(using: colorScheme)
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

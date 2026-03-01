import Foundation
import MCP
import MachOKit
import MachOSwiftSection
import SwiftDump
import SwiftInterface
import Semantic
import Demangling

/// Routes incoming MCP tool calls to the appropriate handler.
struct ToolHandler: Sendable {
    let session: BinarySession

    func handle(_ params: CallTool.Parameters) async -> CallTool.Result {
        do {
            let text = try await dispatch(params)
            return .init(content: [.text(text)])
        } catch {
            return .init(content: [.text("Error: \(error.localizedDescription)")], isError: true)
        }
    }

    private func dispatch(_ params: CallTool.Parameters) async throws -> String {
        switch params.name {
        case "open_binary":
            return try await handleOpenBinary(params.arguments)
        case "open_dyld_cache_image":
            return try await handleOpenDyldCacheImage(params.arguments)
        case "list_types":
            return try await handleListTypes(params.arguments)
        case "dump_type":
            return try await handleDumpType(params.arguments)
        case "list_protocols":
            return try await handleListProtocols(params.arguments)
        case "dump_protocol":
            return try await handleDumpProtocol(params.arguments)
        case "list_conformances":
            return try await handleListConformances(params.arguments)
        case "generate_interface":
            return try await handleGenerateInterface(params.arguments)
        case "demangle_symbol":
            return try await handleDemangleSymbol(params.arguments)
        default:
            throw ToolError.unknownTool(params.name)
        }
    }

    // MARK: - Binary Loading

    private func handleOpenBinary(_ args: [String: Value]?) async throws -> String {
        guard let path = args?["path"]?.stringValue else {
            throw ToolError.missingArgument("path")
        }
        let architecture = args?["architecture"]?.stringValue
        return try await session.load(path: path, architecture: architecture)
    }

    private func handleOpenDyldCacheImage(_ args: [String: Value]?) async throws -> String {
        let imageName = args?["imageName"]?.stringValue
        let imagePath = args?["imagePath"]?.stringValue
        let cachePath = args?["cachePath"]?.stringValue

        guard imageName != nil || imagePath != nil else {
            throw ToolError.missingArgument("imageName or imagePath")
        }

        return try await session.loadFromDyldCache(
            imageName: imageName,
            imagePath: imagePath,
            cachePath: cachePath
        )
    }

    // MARK: - Type Analysis

    private func handleListTypes(_ args: [String: Value]?) async throws -> String {
        let machO = try await session.requireMachO()
        let filterKind = args?["filter"]?.stringValue ?? "all"

        let types = try machO.swift.types
        var lines: [String] = []

        let structs = types.compactMap { if case .struct(let s) = $0 { return s } else { return nil } }
        let enums = types.compactMap { if case .enum(let e) = $0 { return e } else { return nil } }
        let classes = types.compactMap { if case .class(let c) = $0 { return c } else { return nil } }

        if filterKind == "all" || filterKind == "struct" {
            lines.append("## Structs (\(structs.count))")
            for s in structs {
                let name = (try? s.descriptor.name(in: machO)) ?? "<unknown>"
                lines.append("  - \(name)")
            }
        }

        if filterKind == "all" || filterKind == "enum" {
            lines.append("## Enums (\(enums.count))")
            for e in enums {
                let name = (try? e.descriptor.name(in: machO)) ?? "<unknown>"
                lines.append("  - \(name)")
            }
        }

        if filterKind == "all" || filterKind == "class" {
            lines.append("## Classes (\(classes.count))")
            for c in classes {
                let name = (try? c.descriptor.name(in: machO)) ?? "<unknown>"
                lines.append("  - \(name)")
            }
        }

        let total = (filterKind == "all") ? types.count :
            (filterKind == "struct" ? structs.count :
                filterKind == "enum" ? enums.count : classes.count)
        lines.insert("Total: \(total) types", at: 0)

        return lines.joined(separator: "\n")
    }

    private func handleDumpType(_ args: [String: Value]?) async throws -> String {
        let machO = try await session.requireMachO()
        guard let name = args?["name"]?.stringValue else {
            throw ToolError.missingArgument("name")
        }
        let includeFieldOffsets = args?["includeFieldOffsets"]?.boolValue ?? false

        let types = try machO.swift.types
        let matched = types.filter { typeWrapper in
            let typeName: String
            switch typeWrapper {
            case .struct(let s): typeName = (try? s.descriptor.name(in: machO)) ?? ""
            case .enum(let e): typeName = (try? e.descriptor.name(in: machO)) ?? ""
            case .class(let c): typeName = (try? c.descriptor.name(in: machO)) ?? ""
            }
            return typeName.localizedCaseInsensitiveContains(name)
        }

        guard !matched.isEmpty else {
            return "No type found matching '\(name)'. Use 'list_types' to see available types."
        }

        var configuration = DumperConfiguration.demangleOptions(.default)
        configuration.printFieldOffset = includeFieldOffsets

        var results: [String] = []
        for typeWrapper in matched {
            let dumpable: any Dumpable = switch typeWrapper {
            case .struct(let s): s
            case .enum(let e): e
            case .class(let c): c
            }
            let semanticString = try await dumpable.dump(using: configuration, in: machO)
            results.append(semanticString.string)
        }

        return results.joined(separator: "\n\n")
    }

    // MARK: - Protocol Analysis

    private func handleListProtocols(_ args: [String: Value]?) async throws -> String {
        let machO = try await session.requireMachO()
        let protocols = try machO.swift.protocols

        var lines: [String] = ["Total: \(protocols.count) protocols"]
        for proto in protocols {
            lines.append("  - \(proto.name)")
        }
        return lines.joined(separator: "\n")
    }

    private func handleDumpProtocol(_ args: [String: Value]?) async throws -> String {
        let machO = try await session.requireMachO()
        guard let name = args?["name"]?.stringValue else {
            throw ToolError.missingArgument("name")
        }

        let protocols = try machO.swift.protocols
        let matched = protocols.filter {
            $0.name.localizedCaseInsensitiveContains(name)
        }

        guard !matched.isEmpty else {
            return "No protocol found matching '\(name)'. Use 'list_protocols' to see available protocols."
        }

        let configuration = DumperConfiguration.demangleOptions(.default)

        var results: [String] = []
        for proto in matched {
            let semanticString = try await proto.dump(using: configuration, in: machO)
            results.append(semanticString.string)
        }

        return results.joined(separator: "\n\n")
    }

    // MARK: - Conformance Analysis

    private func handleListConformances(_ args: [String: Value]?) async throws -> String {
        let machO = try await session.requireMachO()
        let conformances = try machO.swift.protocolConformances

        let protocolFilter = args?["protocolName"]?.stringValue
        let typeFilter = args?["typeName"]?.stringValue

        let configuration = DumperConfiguration.demangleOptions(.default)

        var results: [String] = []
        for conformance in conformances {
            let semanticString = try await conformance.dump(using: configuration, in: machO)
            let text = semanticString.string

            let matchesProtocol = protocolFilter.map { text.localizedCaseInsensitiveContains($0) } ?? true
            let matchesType = typeFilter.map { text.localizedCaseInsensitiveContains($0) } ?? true

            if matchesProtocol && matchesType {
                results.append(text)
            }
        }

        return "Total: \(results.count) conformances\n\n" + results.joined(separator: "\n")
    }

    // MARK: - Interface Generation

    private func handleGenerateInterface(_ args: [String: Value]?) async throws -> String {
        let machO = try await session.requireMachO()
        let showCImported = args?["showCImportedTypes"]?.boolValue ?? false

        let configuration = SwiftInterfaceBuilderConfiguration(
            indexConfiguration: .init(showCImportedTypes: showCImported),
            printConfiguration: .init(printStrippedSymbolicItem: true)
        )

        let builder = try SwiftInterfaceBuilder(configuration: configuration, in: machO)
        try await builder.prepare()
        let interfaceString = try await builder.printRoot()
        return interfaceString.string
    }

    // MARK: - Symbol Demangling

    private func handleDemangleSymbol(_ args: [String: Value]?) async throws -> String {
        guard let symbol = args?["symbol"]?.stringValue else {
            throw ToolError.missingArgument("symbol")
        }
        let isType = args?["isType"]?.boolValue ?? false

        let node = try demangleAsNode(symbol, isType: isType)
        let defaultResult = node.print(using: .default)
        let simplifiedResult = node.print(using: .simplified)

        var lines: [String] = []
        lines.append("Mangled: \(symbol)")
        lines.append("Demangled (default): \(defaultResult)")
        if simplifiedResult != defaultResult {
            lines.append("Demangled (simplified): \(simplifiedResult)")
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Errors

enum ToolError: LocalizedError {
    case unknownTool(String)
    case missingArgument(String)

    var errorDescription: String? {
        switch self {
        case .unknownTool(let name):
            "Unknown tool: \(name)"
        case .missingArgument(let name):
            "Missing required argument: \(name)"
        }
    }
}

#if os(macOS)

import Csourcekitd
import Foundation
import FoundationToolbox
import SourceKitD

/// Generates whole-module Swift interfaces through sourcekitd's
/// `editor.open.interface` request — the same request Xcode's generated
/// interface uses, and the only ready-made way to obtain the *Swift view* of a
/// module including its ObjC-imported declarations (the SDK's
/// `.swiftinterface` files carry Swift declarations only).
///
/// The request is sent with `key.enablesubstructure`, and the response's
/// document-structure tree is converted into plain
/// ``InterfaceDeclarationNode`` values before it leaves this actor, so
/// downstream extraction never touches sourcekitd types.
@available(macOS 13.0, *)
package actor SourceKitManager {
    package struct GeneratedModuleInterface: Sendable {
        package let moduleName: String
        package let sourceText: String
        package let declarations: [InterfaceDeclarationNode]

        /// Module names the generated interface imports, in appearance order.
        /// Submodule detection (`Foundation.NSObject` inside `Foundation`)
        /// filters on these.
        package let importedModuleNames: [String]

        package init(moduleName: String, sourceText: String, declarations: [InterfaceDeclarationNode], importedModuleNames: [String]) {
            self.moduleName = moduleName
            self.sourceText = sourceText
            self.declarations = declarations
            self.importedModuleNames = importedModuleNames
        }
    }

    package enum Error: Swift.Error, CustomStringConvertible {
        case missingSourceText(moduleName: String)
        case missingSubstructure(moduleName: String)

        package var description: String {
            switch self {
            case .missingSourceText(let moduleName):
                return "editor.open.interface returned no source text for module \(moduleName)"
            case .missingSubstructure(let moduleName):
                return "editor.open.interface returned no substructure for module \(moduleName); the type-name extraction has no input"
            }
        }
    }

    private var cachedSourceKitD: SourceKitD?

    package init() {}

    private func sourcekitd() async throws -> SourceKitD {
        if let cachedSourceKitD {
            return cachedSourceKitD
        }
        // Derived from the active developer directory rather than hardcoding
        // /Applications/Xcode.app, so Xcode-beta and multi-Xcode setups work.
        let developerDirectory = try Subprocess.activeDeveloperDirectory()
        let sourcekitdPath = developerDirectory + "/Toolchains/XcodeDefault.xctoolchain/usr/lib/sourcekitd.framework/Versions/A/sourcekitd"
        let sourceKitD = try await SourceKitD.getOrCreate(dylibPath: URL(fileURLWithPath: sourcekitdPath), pluginPaths: nil)
        cachedSourceKitD = sourceKitD
        return sourceKitD
    }

    /// Generates `moduleName`'s interface against `sdkSettings`' SDK and
    /// converts the structured response. One sourcekitd request per call; a
    /// large module takes seconds, which is why callers index only the
    /// modules a binary actually depends on and cache the extraction.
    package func interface(
        for moduleName: String,
        platform: SDKPlatform,
        sdkSettings: SDKSettings
    ) async throws -> GeneratedModuleInterface {
        let sourcekitd = try await sourcekitd()
        let keys = sourcekitd.keys
        let request = sourcekitd.dictionary([
            keys.moduleName: moduleName,
            keys.name: UUID().uuidString,
            keys.enableStructure: 1,
            keys.compilerArgs: [
                "-sdk", sdkSettings.sdkPath,
                "-target", sdkSettings.targetTriple(for: platform),
            ] as [SKDRequestValue],
        ])
        let response = try await sourcekitd.send(
            \.editorOpenInterface,
            request,
            timeout: .seconds(120),
            restartTimeout: .seconds(120),
            documentUrl: nil,
            fileContents: nil
        )
        guard let sourceText: String = response[keys.sourceText] else {
            throw Error.missingSourceText(moduleName: moduleName)
        }
        guard let substructure: SKDResponseArray = response[keys.subStructure] else {
            throw Error.missingSubstructure(moduleName: moduleName)
        }
        return GeneratedModuleInterface(
            moduleName: moduleName,
            sourceText: sourceText,
            declarations: Self.declarationNodes(of: substructure, in: sourcekitd),
            importedModuleNames: Self.importedModuleNames(inInterfaceSourceText: sourceText)
        )
    }

    // MARK: - Response Conversion

    private static func declarationNodes(of substructure: SKDResponseArray, in sourcekitd: SourceKitD) -> [InterfaceDeclarationNode] {
        var nodes: [InterfaceDeclarationNode] = []
        substructure.forEach { _, nodeDictionary in
            let keys = sourcekitd.keys
            let kindUID: sourcekitd_api_uid_t? = nodeDictionary[keys.kind]
            let kindUIDString = kindUID.flatMap { uid in
                sourcekitd.api.uid_get_string_ptr(uid).map { String(cString: $0) }
            }
            let kind = kindUIDString.map { InterfaceDeclarationNode.kind(forUIDString: $0) } ?? .other
            let name: String? = nodeDictionary[keys.name]
            // `other` nodes are never descended into by the extractor, so
            // their subtrees are dropped here to keep the value tree small.
            let children: [InterfaceDeclarationNode]
            if kind != .other, let childSubstructure: SKDResponseArray = nodeDictionary[keys.subStructure] {
                children = declarationNodes(of: childSubstructure, in: sourcekitd)
            } else {
                children = []
            }
            nodes.append(InterfaceDeclarationNode(kind: kind, name: name, children: children))
            return true
        }
        return nodes
    }

    // MARK: - Import Scan

    /// Line-level scan for `import Module[.Submodule]` in generated interface
    /// text. Machine-generated interfaces spell imports one per line
    /// (optionally attributed, e.g. `@_exported import ObjectiveC`), so no
    /// syntax parsing is needed here.
    package static func importedModuleNames(inInterfaceSourceText sourceText: String) -> [String] {
        var importedModuleNames: [String] = []
        var seenModuleNames: Set<String> = []
        sourceText.enumerateLines { line, _ in
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            guard !trimmedLine.hasPrefix("//") else { return }
            let tokens = trimmedLine.split(separator: " ")
            guard let importTokenIndex = tokens.firstIndex(of: "import"), importTokenIndex + 1 < tokens.count else { return }
            // Reject lines where `import` is not a keyword at clause start
            // (every leading token of a real import is an attribute/modifier).
            let leadingTokens = tokens[..<importTokenIndex]
            guard leadingTokens.allSatisfy({ $0.hasPrefix("@") || $0 == "public" || $0 == "internal" }) else { return }
            let importedModuleName = String(tokens[importTokenIndex + 1])
            guard seenModuleNames.insert(importedModuleName).inserted else { return }
            importedModuleNames.append(importedModuleName)
        }
        return importedModuleNames
    }
}

#endif

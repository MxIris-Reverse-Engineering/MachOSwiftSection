import Foundation
import Testing

/// The cross-reference analysis is split into layers that will leave this
/// package: the core for MachOKitExtensions, the Objective-C layer for
/// MachOObjCSection (evolution proposal
/// `offline-cross-references-and-symbolication`). Each may import only what
/// its future home provides, and the core knows no language — so that the
/// move is a matter of moving files.
@Suite
struct CrossReferenceLayerBoundaryTests {
    /// What MachOKitExtensions holds, or will once the reading-layer and
    /// infrastructure moves land, and the modules that move with the core.
    static let coreAllowedImports: Set<String> = [
        "Foundation", "Darwin", "Dispatch",
        "MachOKit", "MachOKitExtensions",
        "MachOReading", "MachOResolving", "MachOPointers", "MachOCaches", "MachODependencies",
        "MachOBase", "MachOFoundation", "MachOSymbols",
        "ARM64InstructionDecoding", "CodeAddressResolution",
    ]

    /// The core's, plus MachOObjCSection and the core itself.
    static let objectiveCAllowedImports = coreAllowedImports.union(["MachOObjCSection", "CrossReferenceCore"])

    @Test func crossReferenceLayersImportOnlyWhatTheirFutureHomesProvide() throws {
        var offendingLines: [String] = []
        for (moduleName, allowedImports) in [("CrossReferenceCore", Self.coreAllowedImports), ("CrossReferenceObjC", Self.objectiveCAllowedImports)] {
            for fileURL in try Self.sourceFiles(ofModule: moduleName) {
                for (lineNumber, line) in try Self.lines(of: fileURL) {
                    guard let imported = Self.importedModule(in: line), !allowedImports.contains(imported) else { continue }
                    offendingLines.append("\(moduleName)/\(fileURL.lastPathComponent):\(lineNumber): \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }
        #expect(offendingLines.isEmpty, "a layer imports a module its future home will not have:\n\(offendingLines.joined(separator: "\n"))")
    }

    @Test func crossReferenceCoreSpellsNoRuntimeSymbolName() throws {
        var offendingLines: [String] = []
        for fileURL in try Self.sourceFiles(ofModule: "CrossReferenceCore") {
            for (lineNumber, line) in try Self.lines(of: fileURL) where Self.spellsARuntimeSymbolName(line) {
                offendingLines.append("\(fileURL.lastPathComponent):\(lineNumber): \(line.trimmingCharacters(in: .whitespaces))")
            }
        }
        #expect(offendingLines.isEmpty, "the runtime's names belong to the language layers:\n\(offendingLines.joined(separator: "\n"))")
    }

    /// The scans must see what they look for, and nothing else — their
    /// silence proves nothing otherwise.
    @Test func theScansDiscriminate() {
        #expect(Self.importedModule(in: "import MachOSwiftSection") == "MachOSwiftSection")
        #expect(Self.importedModule(in: "@_spi(Core) import MachOObjCSection") == "MachOObjCSection")
        #expect(Self.importedModule(in: "@_exported import CrossReferenceCore") == "CrossReferenceCore")
        #expect(Self.importedModule(in: "package import Demangling") == "Demangling")
        #expect(Self.importedModule(in: "/// import nothing, a comment") == nil)
        #expect(Self.importedModule(in: "let important = 1") == nil)

        #expect(Self.spellsARuntimeSymbolName(#"if strcmp(name, "_objc_msgSend") == 0 {"#))
        #expect(Self.spellsARuntimeSymbolName(#"strncmp(name, "_swift_getTypeByMangledNameIn", 29)"#))
        #expect(!Self.spellsARuntimeSymbolName("/// `objc_msgSend` copies in the cache"))
        #expect(!Self.spellsARuntimeSymbolName(#"sectionName == "__got""#))
    }

    private static let importPattern = try! NSRegularExpression(pattern: #"^\s*(@\w+(\([^)]*\))?\s+)*((public|package|internal|private|fileprivate)\s+)?import\s+(class\s+|struct\s+|enum\s+|func\s+)?([A-Za-z_][A-Za-z0-9_]*)"#)

    static func importedModule(in line: String) -> String? {
        guard let match = importPattern.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let range = Range(match.range(at: 6), in: line)
        else { return nil }
        return String(line[range])
    }

    private static let runtimeSymbolLiteral = try! NSRegularExpression(pattern: #""[^"]*(objc_|swift_)[^"]*""#)

    static func spellsARuntimeSymbolName(_ line: String) -> Bool {
        let code = line.trimmingCharacters(in: .whitespaces)
        guard !code.hasPrefix("//") else { return false }
        return runtimeSymbolLiteral.firstMatch(in: code, range: NSRange(code.startIndex..., in: code)) != nil
    }

    private static func lines(of fileURL: URL) throws -> [(Int, String)] {
        try String(contentsOf: fileURL, encoding: .utf8).components(separatedBy: .newlines).enumerated().map { ($0.offset + 1, $0.element) }
    }

    private static func sourceFiles(ofModule moduleName: String) throws -> [URL] {
        let moduleDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // CrossReferenceAnalysisTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // package root
            .appendingPathComponent("Sources/Analysis/\(moduleName)")
        let enumerator = try #require(FileManager.default.enumerator(at: moduleDirectory, includingPropertiesForKeys: nil))
        var files: [URL] = []
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
            files.append(fileURL)
        }
        #expect(files.count >= 5, "found only \(files.count) sources under \(moduleDirectory.path)")
        return files
    }
}

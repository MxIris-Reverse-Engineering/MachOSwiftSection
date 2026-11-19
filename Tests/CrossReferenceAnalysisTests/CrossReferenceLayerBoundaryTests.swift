import Foundation
import Testing

/// The Objective-C layer of the cross-reference analysis is bound for
/// MachOObjCSection (MachOSwiftSection proposal `move-cross-reference-layers`):
/// it may import only what its future home provides, so that the move is a
/// matter of moving files. The core already lives in MachOKitExtensions, whose
/// own scans watch it.
@Suite
struct CrossReferenceLayerBoundaryTests {
    /// What MachOObjCSection will see: MachOKit, MachOKitExtensions'
    /// modules, MachOObjCSection itself.
    static let objectiveCAllowedImports: Set<String> = [
        "Foundation", "Darwin", "Dispatch",
        "MachOKit", "MachOKitExtensions",
        "MachOReading", "MachOResolving", "MachOPointers", "MachOCaches", "MachODependencies",
        "MachOBase", "MachOFoundation", "MachOSymbols",
        "ARM64InstructionDecoding", "MachOAddressResolution", "MachOCodeReferences",
        "MachOObjCSection",
    ]

    @Test func objectiveCLayerImportsOnlyWhatItsFutureHomeProvides() throws {
        var offendingLines: [String] = []
        for fileURL in try Self.sourceFiles(ofModule: "CrossReferenceObjC") {
            for (lineNumber, line) in try Self.lines(of: fileURL) {
                guard let imported = Self.importedModule(in: line), !Self.objectiveCAllowedImports.contains(imported) else { continue }
                offendingLines.append("CrossReferenceObjC/\(fileURL.lastPathComponent):\(lineNumber): \(line.trimmingCharacters(in: .whitespaces))")
            }
        }
        #expect(offendingLines.isEmpty, "the layer imports a module its future home will not have:\n\(offendingLines.joined(separator: "\n"))")
    }

    /// The scan must see what it looks for, and nothing else — its silence
    /// proves nothing otherwise.
    @Test func theScanDiscriminates() {
        #expect(Self.importedModule(in: "import MachOSwiftSection") == "MachOSwiftSection")
        #expect(Self.importedModule(in: "@_spi(Core) import MachOObjCSection") == "MachOObjCSection")
        #expect(Self.importedModule(in: "@_spi(Internals) import MachOCodeReferences") == "MachOCodeReferences")
        #expect(Self.importedModule(in: "package import Demangling") == "Demangling")
        #expect(Self.importedModule(in: "/// import nothing, a comment") == nil)
        #expect(Self.importedModule(in: "let important = 1") == nil)
    }

    private static let importPattern = try! NSRegularExpression(pattern: #"^\s*(@\w+(\([^)]*\))?\s+)*((public|package|internal|private|fileprivate)\s+)?import\s+(class\s+|struct\s+|enum\s+|func\s+)?([A-Za-z_][A-Za-z0-9_]*)"#)

    static func importedModule(in line: String) -> String? {
        guard let match = importPattern.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let range = Range(match.range(at: 6), in: line)
        else { return nil }
        return String(line[range])
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

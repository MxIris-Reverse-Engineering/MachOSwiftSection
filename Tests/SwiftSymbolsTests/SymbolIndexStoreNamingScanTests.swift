import Foundation
import Testing

/// `SymbolIndexStore` is MachOKitExtensions' C, C++ and Objective-C symbol
/// index; this package's Swift one is `SwiftSymbolIndexStore`. The two share
/// their query names (`symbols(for:in:)`, `isExported(name:in:)`,
/// `containsSymbol(named:in:)`, `offset(ofSymbolNamed:in:)`), so code that
/// still spells the old name compiles against the wrong store and quietly
/// answers with no Swift name at all. Nothing in this package means the C
/// store, so the bare name may not appear in code.
@Suite
struct SymbolIndexStoreNamingScanTests {
    private static let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    // Spelled in two pieces so that this file does not match itself.
    private static let bareNamePattern = try! NSRegularExpression(pattern: "(?<![A-Za-z0-9_])Symbol" + "IndexStore(?![A-Za-z0-9_])")

    @Test func noUnrenamedSymbolIndexStoreInSourcesOrTests() throws {
        var scannedFileCount = 0
        var offendingLines: [String] = []
        for directoryName in ["Sources", "Tests"] {
            let directory = Self.packageRoot.appendingPathComponent(directoryName)
            let enumerator = try #require(FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil))
            for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
                scannedFileCount += 1
                let contents = try String(contentsOf: fileURL, encoding: .utf8)
                for (lineIndex, line) in contents.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                    // Comments may name MachOKitExtensions' store.
                    let code = line.range(of: "//").map { String(line[..<$0.lowerBound]) } ?? String(line)
                    let range = NSRange(code.startIndex..., in: code)
                    if Self.bareNamePattern.firstMatch(in: code, range: range) != nil {
                        offendingLines.append("\(fileURL.path.replacingOccurrences(of: Self.packageRoot.path + "/", with: "")):\(lineIndex + 1)")
                    }
                }
            }
        }
        #expect(scannedFileCount > 500)
        #expect(offendingLines.isEmpty, "\(offendingLines.prefix(10))")
    }
}

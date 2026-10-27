import Foundation
import Testing

/// Identifiers are spelled out: `instructionAddress`, not `pc`; `left` and
/// `right`, not `lhs` and `rhs`. The names here are the ones a review found
/// spread through the package; the fixture sources under `Tests/Projects`
/// are left out, since their names are what the tests read from the
/// binaries built from them.
@Suite
struct AbbreviatedIdentifierScanTests {
    private static let abbreviations = ["pc", "lhs", "rhs"]

    @Test("no source names anything with an abbreviation the package spelled out")
    func sourcesSpellNamesOut() throws {
        var offendingLines: [String] = []
        for fileURL in try Self.packageSourceFiles() {
            let contents = try String(contentsOf: fileURL, encoding: .utf8)
            for (lineNumber, line) in contents.components(separatedBy: .newlines).enumerated() where Self.namesAnAbbreviation(line) {
                offendingLines.append("\(fileURL.lastPathComponent):\(lineNumber + 1): \(line.trimmingCharacters(in: .whitespaces))")
            }
        }
        #expect(offendingLines.isEmpty, "spell these names out:\n\(offendingLines.joined(separator: "\n"))")
    }

    /// The scan must be able to see an abbreviation, and must not invent one
    /// — its silence proves nothing otherwise.
    @Test("the scan sees an abbreviated name and nothing else")
    func theScanDiscriminates() {
        #expect(Self.namesAnAbbreviation("let pc = start &+ UInt64(instructionIndex * 4)"))
        #expect(Self.namesAnAbbreviation("public static func == (lhs: Self, rhs: Self) -> Bool {"))
        #expect(Self.namesAnAbbreviation("namedAddresses.sort { lhs, rhs in"))

        #expect(!Self.namesAnAbbreviation("let instructionAddress = start &+ UInt64(instructionIndex * 4)"))
        #expect(!Self.namesAnAbbreviation("/// the instruction's own address, `pc`"))
        #expect(!Self.namesAnAbbreviation("let pcRelative = true // pc"))
        #expect(!Self.namesAnAbbreviation("print(\"lhs\")"))
    }

    private static let abbreviationExpression = try! NSRegularExpression(pattern: #"\b(\#(abbreviations.joined(separator: "|")))\b"#)
    private static let stringLiteralExpression = try! NSRegularExpression(pattern: #""(?:[^"\\]|\\.)*""#)

    /// Whether the code of `line` — its comment and string literals left out
    /// — uses one of the abbreviations as a whole word.
    private static func namesAnAbbreviation(_ line: String) -> Bool {
        var code = line.trimmingCharacters(in: .whitespaces)
        guard !code.hasPrefix("//") else { return false }
        code = stringLiteralExpression.stringByReplacingMatches(in: code, range: NSRange(code.startIndex..., in: code), withTemplate: "\"\"")
        if let commentStart = code.range(of: "//") { code = String(code[..<commentStart.lowerBound]) }
        return abbreviationExpression.firstMatch(in: code, range: NSRange(code.startIndex..., in: code)) != nil
    }

    /// Every Swift file under `Sources` and `Tests`, the fixture sources under
    /// `Tests/Projects` left out.
    private static func packageSourceFiles() throws -> [URL] {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // CrossReferenceAnalysisTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // package root
        var files: [URL] = []
        for directoryName in ["Sources", "Tests"] {
            let directory = packageRoot.appendingPathComponent(directoryName)
            let enumerator = try #require(FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil))
            for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
                let components = fileURL.pathComponents.drop(while: { $0 != directoryName })
                if components.dropFirst().first == "Projects" { continue }
                files.append(fileURL)
            }
        }
        #expect(files.count > 200, "found only \(files.count) sources under \(packageRoot.path)")
        return files
    }
}

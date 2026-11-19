import Foundation
import Testing

/// Every comment the interface prints is built as a `StructuredComment`
/// (evolution proposal `comment-structure`), never as a bare `Comment`,
/// `InlineComment`, `MultipleLineComment` or `.comment` atom.
///
/// The structured form is what lets a print mark each comment's kind and
/// segments; a comment built any other way prints fine and silently carries
/// no structure, which nothing else would notice until a host drew it as an
/// untagged line. The evolution renderer's own annotations
/// (`EvolutionMarking.swift`) are outside the proposal and stay as they are.
@Suite
struct CommentConstructionScanTests {
    @Test("the interface modules build every comment as a StructuredComment")
    func interfaceModulesBuildStructuredComments() throws {
        var offendingLines: [String] = []
        for fileURL in try Self.scannedSourceFiles() {
            let contents = try String(contentsOf: fileURL, encoding: .utf8)
            for (lineNumber, line) in contents.components(separatedBy: .newlines).enumerated() {
                let code = line.trimmingCharacters(in: .whitespaces)
                guard !code.hasPrefix("//"), Self.buildsABareComment(code) else { continue }
                offendingLines.append("\(fileURL.lastPathComponent):\(lineNumber + 1): \(code)")
            }
        }
        #expect(
            offendingLines.isEmpty,
            """
            build the comment with a `StructuredComment` factory, so a print marking comment structure can \
            tell its kind and segments:
            \(offendingLines.joined(separator: "\n"))
            """
        )
    }

    /// The scan must be able to see a bare comment, and must not invent one —
    /// its silence proves nothing otherwise.
    @Test("the scan sees a bare comment and nothing else")
    func theScanDiscriminates() {
        #expect(Self.buildsABareComment(#"Comment("not exported")"#))
        #expect(Self.buildsABareComment(#"InlineComment("Enum Layout")"#))
        #expect(Self.buildsABareComment(#"MultipleLineComment(text)"#))
        #expect(Self.buildsABareComment(#"AtomicComponent(string: block, type: .comment)"#))
        #expect(Self.buildsABareComment(#"result.append(line, type: .comment)"#))

        #expect(!Self.buildsABareComment(#"StructuredComment.note("not exported")"#))
        #expect(!Self.buildsABareComment(#"OffsetComment(prefix: offsetCommentPrefix, offset: function.offset, emit: true)"#))
        #expect(!Self.buildsABareComment(#"ExportStatusComment(isExported: verdict)"#))
        #expect(!Self.buildsABareComment(#"if atom.type == .comment {"#))
    }

    private static let bareCommentExpression = try! NSRegularExpression(
        pattern: #"\b(Comment|InlineComment|MultipleLineComment)\(|\btype:\s*\.comment\b"#
    )

    private static func buildsABareComment(_ code: String) -> Bool {
        bareCommentExpression.firstMatch(in: code, range: NSRange(code.startIndex..., in: code)) != nil
    }

    /// The modules whose comments the interface prints.
    private static let scannedModuleDirectories = [
        "Output/SwiftDeclarationRendering",
        "Output/SwiftPrinting",
        "Output/SwiftInterface",
        "Declaration/SwiftDeclaration",
    ]

    /// Renderers of their own, outside the proposal.
    private static let unscannedFileNames: Set<String> = ["EvolutionMarking.swift"]

    /// `StructuredComment` itself: the one place a comment's atoms are made.
    private static func isStructuredCommentSource(_ fileURL: URL) -> Bool {
        fileURL.lastPathComponent.hasPrefix("StructuredComment")
    }

    private static func scannedSourceFiles() throws -> [URL] {
        let sourcesDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // SwiftInterfaceTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // package root
            .appendingPathComponent("Sources")
        var files: [URL] = []
        for moduleDirectory in scannedModuleDirectories {
            let directory = sourcesDirectory.appendingPathComponent(moduleDirectory)
            let enumerator = try #require(FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil))
            for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" && !unscannedFileNames.contains(fileURL.lastPathComponent) && !isStructuredCommentSource(fileURL) {
                files.append(fileURL)
            }
        }
        #expect(files.count > 100, "the scan found \(files.count) files; a moved module would leave it scanning nothing")
        return files
    }
}

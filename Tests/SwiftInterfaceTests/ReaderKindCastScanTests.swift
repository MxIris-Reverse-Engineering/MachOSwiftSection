import Foundation
import Testing

/// The library tells readers apart through `asMachOImage` / `asMachOFile` /
/// `underlyingReader` (MachOKitExtensions), never through a cast to
/// `MachOImage` / `MachOFile`.
///
/// A cast cannot see through a host's wrapper (MachOKitUI's `MachOImageSource`
/// and `MachOFileSource`), so every one of them treated a wrapper as neither
/// reader: most quietly dropped what they work out, and the in-process opaque
/// type reference trapped. Bind / rebase resolution had already been made
/// wrapper-aware (`MachOBindRebaseResolving`) when that in-process path was
/// written as a cast, which is why this is a scan rather than a review note.
@Suite
struct ReaderKindCastScanTests {
    @Test("no library module tells readers apart with a cast")
    func libraryModulesDoNotCastReaders() throws {
        var offendingLines: [String] = []
        for fileURL in try Self.librarySourceFiles() {
            let contents = try String(contentsOf: fileURL, encoding: .utf8)
            for (lineNumber, line) in contents.components(separatedBy: .newlines).enumerated() {
                let code = line.trimmingCharacters(in: .whitespaces)
                guard !code.hasPrefix("//"), Self.castsToAConcreteReader(code) else { continue }
                offendingLines.append("\(fileURL.lastPathComponent):\(lineNumber + 1): \(code)")
            }
        }
        #expect(
            offendingLines.isEmpty,
            """
            ask `asMachOImage` / `asMachOFile` / `underlyingReader` what a reader is, so a wrapper answers \
            for the reader it wraps:
            \(offendingLines.joined(separator: "\n"))
            """
        )
    }

    /// The scan must be able to see a cast, and must not invent one — its
    /// silence proves nothing otherwise.
    @Test("the scan sees a reader cast and nothing else")
    func theScanDiscriminates() {
        #expect(Self.castsToAConcreteReader("if let machOImage = machO as? MachOImage {"))
        #expect(Self.castsToAConcreteReader("if machO is MachOFile {"))
        #expect(Self.castsToAConcreteReader("let machOFile = machO as! MachOFile"))
        #expect(Self.castsToAConcreteReader("if let machOImageContext = context as? MachOContext<MachOImage> {"))
        #expect(Self.castsToAConcreteReader("case let machOFile as MachOFile: machOFile.imagePath"))

        #expect(!Self.castsToAConcreteReader("extension ImageUniverse where MachO == MachOImage {"))
        #expect(!Self.castsToAConcreteReader("extension ReadingContext where Self == MachOContext<MachOImage> {"))
        #expect(!Self.castsToAConcreteReader("if let machOImage = machO.asMachOImage {"))
        #expect(!Self.castsToAConcreteReader("let machOFile: MachOFile = fileImage"))
        #expect(!Self.castsToAConcreteReader("if let machOImages = machO as? MachOImageCollection {"))
    }

    private static let readerCastExpression = try! NSRegularExpression(
        pattern: #"\b(as[?!]?|is)\s+(MachOImage|MachOFile|MachOContext<\s*MachO(Image|File)\s*>)(?![A-Za-z0-9_])"#
    )

    private static func castsToAConcreteReader(_ code: String) -> Bool {
        readerCastExpression.firstMatch(in: code, range: NSRange(code.startIndex..., in: code)) != nil
    }

    /// Every Swift file of a library module: `Sources/<Group>/<Module>/…`, the
    /// `TestSupport` group left out — fixtures there hold the concrete readers
    /// on purpose.
    private static func librarySourceFiles() throws -> [URL] {
        let sourcesDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // SwiftInterfaceTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // package root
            .appendingPathComponent("Sources")
        let enumerator = try #require(FileManager.default.enumerator(at: sourcesDirectory, includingPropertiesForKeys: nil))
        var files: [URL] = []
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
            let groupName = fileURL.pathComponents.drop(while: { $0 != "Sources" }).dropFirst().first
            if groupName == "TestSupport" { continue }
            files.append(fileURL)
        }
        return files
    }
}

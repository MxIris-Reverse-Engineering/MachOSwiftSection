import Foundation
import Testing
import MachOKit
import MachOFoundation
import MachOSwiftSection
import SwiftDeclarationRendering
import SwiftPrinting
import SwiftInterface
// Scoped: the module's `Error` component would shadow `Swift.Error` here.
import struct Semantic.SemanticString
import struct Semantic.FrozenSemanticString
import struct Semantic.AnnotationRegionTable
import struct Semantic.AnnotationRegion
import struct Semantic.AnnotationSegment
import MachOTestingSupport

/// The comment above an availability-conditional witness (SE-0360) — the
/// associated type's line and one line per branch — marked as one
/// `conditionalWitness` region holding a `conditionalWitnessBranch` for each
/// branch (evolution proposal `comment-structure`). SymbolTestsCore keeps no
/// such witness: a conformance whose underlying type the compiler can see is
/// written into the witness record, so the fixture here is built for it.
@Suite
struct ConditionalWitnessCommentStructureTests {
    private enum FixtureWorkingDirectoryCleanup {
        nonisolated(unsafe) static var directories: [URL] = []
        static let registration: Void = {
            atexit {
                for directory in FixtureWorkingDirectoryCleanup.directories {
                    try? FileManager.default.removeItem(at: directory)
                }
            }
        }()
    }

    private struct FixtureCompilationError: Swift.Error, CustomStringConvertible {
        let diagnostics: String
        var description: String { "conditional-witness fixture compilation failed:\n\(diagnostics)" }
    }

    private static let moduleName = "CommentStructureConditionalWitnessFixture"

    /// `FixtureAnchor` is ballast: a fixture dylib with no class has no
    /// `__DATA` segment, which older MachOKit releases mis-walked.
    ///
    /// Each branch returns a type whose metadata the thunk has to call for,
    /// so the thunk branches on the availability check. Two types it can load
    /// directly (`1` and `"one"`) compile to a `csel` between two metadata
    /// addresses, which the thunk reader does not evaluate: the witness then
    /// prints as `accessor function at …` with no comment.
    private static let fixtureSource = """
    public final class FixtureAnchor {}

    public protocol Shape {
        associatedtype Body
        var body: Body { get }
    }

    public struct ConditionalConcrete: Shape {
        public init() {}
        public var body: some Equatable {
            if #available(macOS 26, *) {
                return [1]
            } else {
                return ["one": 1]
            }
        }
    }
    """

    private static let fixtureCompilationResult: Result<URL, Swift.Error> = {
        Result {
            let workingDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(moduleName)-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
            _ = FixtureWorkingDirectoryCleanup.registration
            FixtureWorkingDirectoryCleanup.directories.append(workingDirectory)

            let sourceURL = workingDirectory.appendingPathComponent("\(moduleName).swift")
            let libraryURL = workingDirectory.appendingPathComponent("lib\(moduleName).dylib")
            try fixtureSource.write(to: sourceURL, atomically: true, encoding: .utf8)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            process.arguments = [
                "swiftc", "-swift-version", "5", "-O", "-emit-library",
                "-module-name", moduleName,
                "-target", "arm64-apple-macosx15.0",
                sourceURL.path, "-o", libraryURL.path,
            ]
            let standardErrorPipe = Pipe()
            process.standardError = standardErrorPipe
            try process.run()
            // Drain before waiting, or a long diagnostic deadlocks both sides.
            let diagnosticsData = standardErrorPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw FixtureCompilationError(diagnostics: String(decoding: diagnosticsData, as: UTF8.self))
            }
            return libraryURL
        }
    }()

    private func printInterface(marksCommentStructure: Bool) async throws -> FrozenSemanticString {
        let libraryURL = try Self.fixtureCompilationResult.get()
        let machOFile: MachOFile
        switch try MachOKit.loadFromFile(url: libraryURL) {
        case .machO(let file):
            machOFile = file
        case .fat(let fatFile):
            machOFile = try #require(try fatFile.machOFiles().first { $0.header.cpuType == .arm64 })
        }
        var configuration = SwiftInterfaceBuilderConfiguration()
        configuration.printConfiguration.marksCommentStructure = marksCommentStructure
        let builder = try SwiftInterfaceBuilder(configuration: configuration, eventHandlers: [], in: machOFile)
        // The witness is an opaque type: read through its accessor thunk.
        builder.addExtraDataProvider(SwiftInterfaceBuilderOpaqueTypeProvider(machO: machOFile))
        try await builder.prepare()
        return try await builder.printRoot().frozen()
    }

    @Test func aConditionalWitnessIsOneRegionWithARegionPerBranch() async throws {
        let marked = try await printInterface(marksCommentStructure: true)
        let plain = try await printInterface(marksCommentStructure: false)
        try #require(plain.string.contains("is picked at run time by an availability check (SE-0360):"), "no conditional witness in:\n\(plain.string)")
        let violation = CommentStructureContract.violation(marked: marked, unmarked: plain)
        #expect(violation == nil, "\(violation ?? "")")

        let (separatedText, annotations) = marked.separatingAnnotationRegions()
        let utf8 = Array(separatedText.string.utf8)
        func substring(utf8Offset: UInt32, utf8Length: UInt32) -> String {
            String(decoding: utf8[Int(utf8Offset) ..< Int(utf8Offset) + Int(utf8Length)], as: UTF8.self)
        }
        let witnessIndex = try #require(annotations.regions.firstIndex { $0.kind == .conditionalWitness })
        let witnessSegments: [(role: String, text: String)] = annotations.segments(inRegionAt: witnessIndex).map { ($0.role.rawValue, substring(utf8Offset: $0.utf8Offset, utf8Length: $0.utf8Length)) }
        #expect(witnessSegments.map(\.role) == ["marker", "name", "separator", "text", "separator"])
        #expect(witnessSegments.first { $0.role == "name" }?.text == "Body")

        let branchIndices = annotations.regions.indices.filter { annotations.regions[$0].enclosingRegionIndex == witnessIndex }
        #expect(branchIndices.map { annotations.regions[$0].kind } == [.conditionalWitnessBranch, .conditionalWitnessBranch])
        func branchSegmentText(at branchIndex: Int, role: AnnotationSegment.Role) -> String? {
            annotations.segments(inRegionAt: branchIndex).first { $0.role == role }.map { substring(utf8Offset: $0.utf8Offset, utf8Length: $0.utf8Length) }
        }
        #expect(branchIndices.map { branchSegmentText(at: $0, role: .qualifier) } == ["macOS 26.0 or later", "before macOS 26.0"])
        #expect(branchIndices.map { branchSegmentText(at: $0, role: .type) } == ["[Swift.Int]", "[Swift.String : Swift.Int]"])
    }
}

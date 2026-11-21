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
import SwiftSectionTestingSupport

/// The comment above an availability-conditional witness (SE-0360) — the
/// associated type's line and one line per branch — marked as one
/// `conditionalWitness` region holding a `conditionalWitnessBranch` for each
/// branch (evolution proposal `comment-structure`). SymbolTestsCore keeps no
/// such witness: a conformance whose underlying type the compiler can see is
/// written into the witness record, so the fixture here is built for it.
@Suite
struct ConditionalWitnessCommentStructureTests {
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

    private func printInterface(marksCommentStructure: Bool) async throws -> FrozenSemanticString {
        let libraryURL = try FixtureCompiler.shared.dynamicLibrary(
            named: Self.moduleName,
            language: .swift,
            source: Self.fixtureSource,
            arguments: ["-swift-version", "5", "-O", "-target", "arm64-apple-macosx15.0"]
        )
        let machOFile = try HostSlice.machOFile(at: libraryURL)
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

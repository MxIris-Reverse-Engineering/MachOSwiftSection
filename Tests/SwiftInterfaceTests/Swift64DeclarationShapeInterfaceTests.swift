import Foundation
import Testing
import MachOKit
import MachOFoundation
import MachOSwiftSection
import SwiftPrinting
import SwiftInterface
import Semantic
@testable import MachOTestingSupport

/// The interface of the declaration shapes Swift 6.4 introduced (evolution
/// proposal `borrow-accessors-and-suppressed-associated-types`). The expected
/// spellings are the compiler's own: a swiftinterface prints `{ borrow mutate }`
/// and `associatedtype Element: ~Copyable` for these declarations.
@Suite(.enabled(if: Swift64DeclarationShapesFixture.isAvailable, "needs a Swift 6.4 or newer toolchain"))
struct Swift64DeclarationShapeInterfaceTests {
    /// The fixture is a handful of declarations, so each test builds its own.
    private func printedInterface(printConfiguration: SwiftDeclarationPrintConfiguration = .init()) async throws -> String {
        try await semanticInterface(printConfiguration: printConfiguration).string
    }

    private func semanticInterface(printConfiguration: SwiftDeclarationPrintConfiguration) async throws -> SemanticString {
        let builder = try SwiftInterfaceBuilder(configuration: SwiftInterfaceBuilderConfiguration(printConfiguration: printConfiguration), eventHandlers: [], in: try Swift64DeclarationShapesFixture.machOFile())
        try await builder.prepare()
        return try await builder.printRoot()
    }

    /// The note in place of an element the records keep no name for is
    /// marked like every other comment (evolution proposal
    /// `comment-structure`).
    @Test func markingCommentStructureKeepsTheContract() async throws {
        var markedConfiguration = SwiftDeclarationPrintConfiguration()
        markedConfiguration.marksCommentStructure = true
        let marked = try await semanticInterface(printConfiguration: markedConfiguration).frozen()
        let plain = try await semanticInterface(printConfiguration: .init()).frozen()
        let violation = CommentStructureContract.violation(marked: marked, unmarked: plain)
        #expect(violation == nil, "\(violation ?? "")")
    }

    /// The lines of the block whose header line, trimmed, starts with
    /// `prefix` — trimmed, header and closing brace excluded.
    private func blockLines(startingWith prefix: String, in interface: String) -> [String]? {
        let lines = interface.split(separator: "\n", omittingEmptySubsequences: false)
        guard let start = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix(prefix) }) else { return nil }
        let indentation = lines[start].prefix { $0 == " " }
        guard let end = lines[(start + 1)...].firstIndex(where: { $0 == "\(indentation)}" }) else { return nil }
        return lines[(start + 1) ..< end].map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    // MARK: - SE-0507 borrow / mutate accessors

    @Test(arguments: [
        ("var borrowedOnly: Swift.Int {", ["borrow"]),
        ("var borrowedAndMutated: Swift.Int {", ["borrow", "mutate"]),
        ("var computed: Swift.Int {", ["get", "set"]),
    ])
    func propertyPrintsItsDeclaredAccessors(header: String, accessors: [String]) async throws {
        let interface = try await printedInterface()
        let storageLines = try #require(blockLines(startingWith: "struct BorrowedStorage", in: interface), "\(interface)")
        let headerIndex = try #require(storageLines.firstIndex(of: header), "\(storageLines)")
        #expect(Array(storageLines[(headerIndex + 1)...].prefix(accessors.count + 1)) == accessors + ["}"], "\(storageLines)")
    }

    @Test func subscriptPrintsBorrowAndMutate() async throws {
        let interface = try await printedInterface()
        let storageLines = try #require(blockLines(startingWith: "struct BorrowedStorage", in: interface), "\(interface)")
        let headerIndex = try #require(storageLines.firstIndex { $0.hasPrefix("subscript(") && $0.hasSuffix("-> Swift.Int {") }, "\(storageLines)")
        #expect(Array(storageLines[(headerIndex + 1)...].prefix(3)) == ["borrow", "mutate", "}"], "\(storageLines)")
    }

    /// A protocol whose requirements are all SE-0507 accessors printed as an
    /// empty `protocol BorrowRequirement {}`.
    @Test func protocolRequirementPrintsBorrowAndMutate() async throws {
        let interface = try await printedInterface()
        let protocolLines = try #require(blockLines(startingWith: "protocol BorrowRequirement", in: interface), "\(interface)")
        #expect(protocolLines == [
            "var element: Swift.Int {",
            "borrow",
            "mutate",
            "}",
            "var readOnlyElement: Swift.Int {",
            "borrow",
            "}",
        ])
    }

    // MARK: - SE-0503 suppressed associated types

    /// A primary associated type an extension suppresses prints its
    /// suppression; an ordinary one cannot carry the evidence (`Strategy`),
    /// and the Copyable control (`Index`) prints bare.
    @Test(arguments: [
        ("associatedtype Element", "associatedtype Element: ~Swift.Copyable"),
        ("associatedtype View", "associatedtype View: ~Swift.Escapable"),
        ("associatedtype Payload", "associatedtype Payload: ~Swift.Copyable & ~Swift.Escapable"),
        ("associatedtype Strategy", "associatedtype Strategy"),
        ("associatedtype Index", "associatedtype Index"),
    ])
    func associatedTypePrintsTheSuppressionItsExtensionsProve(declarationPrefix: String, expectedLine: String) async throws {
        let interface = try await printedInterface()
        let protocolLines = try #require(blockLines(startingWith: "protocol SuppressedElementContainer", in: interface), "\(interface)")
        let line = try #require(protocolLines.first { $0 == declarationPrefix || $0.hasPrefix(declarationPrefix + ":") }, "\(protocolLines)")
        #expect(line == expectedLine)
    }

    /// Without an extension the declaration is unknowable, so the reading
    /// stays the default rather than guessing.
    @Test func associatedTypeWithoutEvidencePrintsBare() async throws {
        let interface = try await printedInterface()
        let protocolLines = try #require(blockLines(startingWith: "protocol UnprovenElementContainer", in: interface), "\(interface)")
        #expect(protocolLines.contains("associatedtype Element"), "\(protocolLines)")
    }

    /// With requirements printed on the associated types (evolution proposal
    /// `protocol-requirement-placement`), a proven suppression joins the
    /// inheritance clause after the requirements, as the compiler writes
    /// `associatedtype Element: P, ~Copyable`. In the protocol's `where`
    /// clause the requirement leaves the suppression alone on the line.
    @Test(arguments: [
        (ProtocolRequirementPlacement.protocolWhereClause, "associatedtype Element: ~Swift.Copyable"),
        (ProtocolRequirementPlacement.associatedTypes, "associatedtype Element: Swift64DeclarationShapesFixture.SuppressibleMarker, ~Swift.Copyable"),
    ])
    func suppressionJoinsTheInheritanceClauseOfItsAssociatedType(placement: ProtocolRequirementPlacement, expectedLine: String) async throws {
        var printConfiguration = SwiftDeclarationPrintConfiguration()
        printConfiguration.protocolRequirementPlacement = placement
        let interface = try await printedInterface(printConfiguration: printConfiguration)
        let protocolLines = try #require(blockLines(startingWith: "protocol ConstrainedSuppressedElementContainer", in: interface), "\(interface)")
        #expect(protocolLines.contains(expectedLine), "\(protocolLines)")
    }
}

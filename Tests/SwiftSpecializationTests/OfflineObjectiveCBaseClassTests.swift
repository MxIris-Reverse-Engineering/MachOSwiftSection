@_spi(Support) @testable import SwiftSpecialization
@_spi(Support) @testable import SwiftDeclaration
@_spi(Support) @testable import SwiftIndexing
import Foundation
import Testing
import MachOKit
@testable import MachOSwiftSection
import SwiftSectionTestingSupport
import OrderedCollections
import Demangling

/// A base-class requirement on an Objective-C class, checked offline
/// (evolution proposal `offline-generic-specialization`).
///
/// The offline check reads class hierarchies from the indexed images, and
/// those hold Swift classes only: a Swift class whose superclass is an
/// Objective-C class other than the base — `FixtureOperation: Operation`
/// under an `NSObject` bound — has no indexed link up to the base. The check
/// took that for proof of a violation and rejected the selection, while the
/// runtime accepts it. A chain that leaves the indexed classes is evidence the
/// file does not carry; `staticPreflight` promises a warning for that, never
/// an error. Cocoa bounds — `NSObject`, `NSView`, `UIViewController` — are
/// the most common base-class bounds there are.
@Suite(.serialized)
struct OfflineObjectiveCBaseClassTests {
    private static let moduleName = "ObjectiveCBaseClassFixture"

    private static let fixtureSource = """
    import Foundation

    public final class FixtureOperation: Operation {}

    public final class FixtureObject: NSObject {}

    public struct ObjectBound<Subject: NSObject> {
        public var subject: Subject
    }
    """

    /// Compiled once per process by the shared compiler.
    private func loadFixtureMachOFile() throws -> MachOFile {
        let libraryURL = try FixtureCompiler.shared.dynamicLibrary(
            named: Self.moduleName,
            language: .swift,
            source: Self.fixtureSource,
            arguments: ["-swift-version", "5", "-target", "arm64-apple-macosx15.0"]
        )
        return try HostSlice.machOFile(at: libraryURL)
    }

    /// The offline specializer over the fixture file, the request for
    /// `ObjectBound`, and the candidate for the fixture class `className`.
    /// The candidate is built from the indexer's definition rather than taken
    /// from the request: the request's list is narrowed by the same indexed
    /// hierarchy, so a class below an Objective-C intermediate is not on it.
    private func offlineSelection(ofClassNamed className: String) async throws -> (specializer: GenericSpecializer<MachOFile>, request: SpecializationRequest, candidate: SpecializationRequest.Candidate) {
        let indexer = SwiftDeclarationIndexer(in: try loadFixtureMachOFile())
        try await indexer.prepare()
        let boundDefinition = try #require(indexer.allTypeDefinitions.values.first { $0.typeName.declaredNameForTesting == "ObjectBound" })
        let classDefinition = try #require(indexer.allTypeDefinitions.values.first { $0.typeName.declaredNameForTesting == className })
        let specializer = GenericSpecializer(indexer: indexer)
        let request = try specializer.makeRequest(for: boundDefinition.typeContextDescriptorWrapper)
        return (specializer, request, .init(typeName: classDefinition.typeName, source: .image(Self.moduleName)))
    }

    @Test("a Swift class below an Objective-C intermediate is not a base-class violation")
    func swiftClassBelowAnObjectiveCIntermediateIsNotAViolation() async throws {
        let (specializer, request, operation) = try await offlineSelection(ofClassNamed: "FixtureOperation")

        let validation = specializer.staticPreflight(selection: ["A": .candidate(operation)], for: request)

        #expect(validation.isValid, "\(validation.errors)")
    }

    @Test("a Swift class below an Objective-C intermediate specializes offline")
    func swiftClassBelowAnObjectiveCIntermediateSpecializes() async throws {
        let (specializer, request, operation) = try await offlineSelection(ofClassNamed: "FixtureOperation")

        let result = try specializer.specialize(request, with: ["A": .candidate(operation)])

        #expect(result.typeName.name(using: .default) == "\(Self.moduleName).ObjectBound<\(Self.moduleName).FixtureOperation>")
    }
}

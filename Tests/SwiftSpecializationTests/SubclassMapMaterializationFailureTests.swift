@_spi(Support) @testable import SwiftSpecialization
@_spi(Support) @testable import SwiftDeclaration
@_spi(Support) @testable import SwiftIndexing
import Foundation
import Testing
import MachOKit
import Dependencies
@_spi(Internals) import MachOSymbols
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// `IndexerConformanceProvider`'s subclass map must not lose a class silently.
///
/// Since evolution proposal 0002 the map build materializes each class wrapper
/// from its descriptor (the superclass reference can live in the wrapper's
/// trailing objects). That read can throw — before the proposal the wrapper was
/// a stored property and could not — and the `catch` it landed in had been
/// written for the `superclassNode` read alone. A class whose wrapper cannot be
/// materialized therefore dropped out of the map with no event, no diagnostic
/// and no error, and `subclasses(of:)` narrowed a specialization search by a
/// candidate that had quietly gone missing.
///
/// The two causes are now caught separately: an unreadable wrapper is reported,
/// an absent / unreadable superclass link stays silent (that is the ordinary
/// "this class has no usable parent" case, which most classes take).
@Suite(.serialized)
final class SubclassMapMaterializationFailureTests: MachOFileTests, @unchecked Sendable {
    override class var fileName: MachOFileName { .SymbolTestsCore }

    private func preparedIndexer() async throws -> SwiftDeclarationIndexer<MachOFile> {
        let unsafeMachOFile = machOFile
        let indexer = SwiftDeclarationIndexer(in: unsafeMachOFile)
        try await indexer.prepare()
        return indexer
    }

    private func typeName(named leafName: String, in indexer: SwiftDeclarationIndexer<MachOFile>) throws -> TypeName {
        try #require(indexer.allTypeDefinitions.keys.first { $0.currentName == leafName })
    }

    /// A class whose wrapper cannot be materialized is reported on stderr, and
    /// the classes around it keep their subclass relationships — the failure is
    /// scoped to the one entry, not to the map.
    @Test func unreadableClassWrapperIsReportedAndScopedToItsOwnEntry() async throws {
        let indexer = try await preparedIndexer()

        let baseClassName = try typeName(named: "ClassTest", in: indexer)
        let subclassName = try typeName(named: "SubclassTest", in: indexer)
        try #require(
            IndexerConformanceProvider(indexer: indexer).subclasses(of: baseClassName).contains(subclassName),
            "fixture must carry the ClassTest -> SubclassTest link for this test to be meaningful"
        )

        // A real class descriptor's layout re-wrapped far past the fixture's end
        // of file: every relative resolve the wrapper materialization performs is
        // out of bounds and throws deterministically. The entry keeps its key, so
        // the map's population is unchanged and only this class is affected.
        let donorTypeName = try typeName(named: "FinalClassTest", in: indexer)
        let donorDefinition = try #require(indexer.allTypeDefinitions[donorTypeName])
        guard case .class(let realClassDescriptor) = donorDefinition.typeContextDescriptorWrapper else {
            Issue.record("FinalClassTest is expected to be a class")
            return
        }
        let unreadableDescriptor = ClassDescriptor(layout: realClassDescriptor.layout, offset: 0x0FFF_FFF0)
        indexer.currentStorage.allTypeDefinitions[donorTypeName] = TypeDefinition(
            typeContextDescriptorWrapper: .class(unreadableDescriptor),
            typeName: donorTypeName,
            isSpecialized: false
        )
        indexer.allStorageCache = .init()

        // A fresh provider: the subclass map is memoized per provider instance.
        nonisolated(unsafe) let unsafeIndexer = indexer
        nonisolated(unsafe) var subclassesAfterInjection: [TypeName] = []
        let capturedStandardError = try await StandardStreamCapture.standardError {
            subclassesAfterInjection = IndexerConformanceProvider(indexer: unsafeIndexer).subclasses(of: baseClassName)
        }

        #expect(
            capturedStandardError.contains("subclass map skipped"),
            "an unreadable class wrapper must be reported, not dropped silently; captured: \"\(capturedStandardError)\""
        )
        #expect(
            subclassesAfterInjection.contains(subclassName),
            "one unreadable class must not cost an unrelated class its subclass link"
        )
    }
}

@_spi(Support) @testable import SwiftSpecialization
@_spi(Support) @testable import SwiftDeclaration
@_spi(Support) @testable import SwiftIndexing
import Foundation
import Testing
import MachOKit
import Demangling
@testable import MachOSwiftSection
import MachOTestingSupport

/// `specialize(...)` appends the new definition to the generic definition's
/// `specializedChildren`: an associated object, retained non-atomically, read,
/// appended to and written back with no lock. `TypeDefinition` is declared
/// `@unchecked Sendable`, and RuntimeViewer calls `specialize` from its section
/// actor into a nonisolated async method — which runs off the actor while the
/// actor goes on reading the same array. Two specializations at once lose one
/// of them, and a read that overlaps a write can retain an array the write has
/// just released.
///
/// Measured before the fix: 445 to 467 of 512 specializations kept, every run.
/// An exit test all the same: the overlap that loses an entry can also free
/// an array still being read, which would take the whole process down.
@Suite(.serialized)
struct ConcurrentSpecializationTests {
    /// Specializes one definition from many tasks at once, each reading the
    /// list meanwhile, and fails unless every specialization was kept.
    static func specializeOneDefinitionFromManyTasks() async throws {
        let machOImage = try GenericSpecializationFixture.loadedImage()
        // An indexer of its own: the appends must not reach the definitions
        // the other suites share.
        let indexer = SwiftDeclarationIndexer(in: machOImage)
        try await indexer.prepare()
        let definition = try GenericSpecializationFixtureIndexers.typeDefinition(named: "PairBox", in: indexer)
        let specializer = GenericSpecializer(indexer: indexer)
        let request = try specializer.makeRequest(for: definition.typeContextDescriptorWrapper)
        let result = try specializer.specialize(request, with: ["A": .metatype(Int.self), "B": .metatype(String.self)])
        let typeArgumentNodes = [try await demangleAsNode("Si", isType: true), try await demangleAsNode("SS", isType: true)]
        let specializationCount = 512

        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0 ..< specializationCount {
                group.addTask {
                    try await definition.specialize(with: result, typeArgumentNodes: typeArgumentNodes, in: machOImage)
                    // What RuntimeViewer's actor does while a specialization
                    // runs off it.
                    _ = definition.specializedChildren.count
                }
            }
            try await group.waitForAll()
        }

        let keptCount = definition.specializedChildren.count
        guard keptCount == specializationCount else {
            throw LostSpecializations(keptCount: keptCount, expectedCount: specializationCount)
        }
    }

    private struct LostSpecializations: Swift.Error, CustomStringConvertible {
        let keptCount: Int
        let expectedCount: Int
        var description: String { "kept \(keptCount) of \(expectedCount) specializations" }
    }

    @Test("specializations made from many tasks at once are all kept")
    func specializationsFromManyTasksAreAllKept() async {
        await #expect(processExitsWith: .success) {
            do {
                try await ConcurrentSpecializationTests.specializeOneDefinitionFromManyTasks()
            } catch {
                // An error thrown out of an exit test ends the child on a
                // trap, which reads like a crash; a lost specialization is a
                // plain failure.
                exit(EXIT_FAILURE)
            }
        }
    }
}

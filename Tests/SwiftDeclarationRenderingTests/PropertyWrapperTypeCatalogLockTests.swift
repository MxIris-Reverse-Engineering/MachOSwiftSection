import Foundation
import Testing
import Demangling
@testable import SwiftDeclarationRendering

/// `PropertyWrapperTypeCatalog.evidence(forWrapperCandidate:)` holds its lock
/// only to read or store a verdict; the export-trie searches and the
/// demangling of their hits run outside it (evolution proposal
/// `faster-lazy-definition-indexing`). Before, the whole search ran under the
/// lock, so with an image printed four ways at once a caller whose verdict
/// was already known queued behind every other caller's search — 8% of the
/// time the prints took.
///
/// The searches here are closures the test controls: one of them stays in
/// its search until released, and a caller asking about another, already
/// answered type must get its verdict meanwhile. Both sides run on threads of
/// their own, never on the cooperative pool, and the waiting side waits with
/// a deadline, so a catalog that serializes again fails instead of hanging.
@Suite
struct PropertyWrapperTypeCatalogLockTests {
    /// The `.type` node of a struct `module.name`, the shape
    /// `WrappedPropertyRecovery.nominalTypeNode(ofFieldType:)` hands over.
    private static func nominalTypeNode(module: String, name: String) throws -> Node {
        let descriptorNode = try demangleAsNode("$s\(module.count)\(module)\(name.count)\(name)VMn")
        return try #require(descriptorNode.first(of: .type))
    }

    @Test func knownVerdictIsNotQueuedBehindASearch() throws {
        let answeredNode = try Self.nominalTypeNode(module: "Test", name: "Wrapper")
        let searchedNode = try Self.nominalTypeNode(module: "Test", name: "Slow")
        let searchedPrefix = try #require(PropertyWrapperTypeCatalog.wrappedValueSymbolPrefix(of: searchedNode))
        let searchStarted = DispatchSemaphore(value: 0)
        let searchReleased = DispatchSemaphore(value: 0)
        // Every prefix answers with the getter of an `Int` `wrappedValue`;
        // the searched one only once released.
        let catalog = PropertyWrapperTypeCatalog(rootLookup: { prefix in
            if prefix == searchedPrefix {
                searchStarted.signal()
                searchReleased.wait()
            }
            return [prefix + "Sivg"]
        }, dependencyLookups: { [] })

        #expect(catalog.evidence(forWrapperCandidate: answeredNode) != nil)

        let searchFinished = DispatchSemaphore(value: 0)
        Thread {
            _ = catalog.evidence(forWrapperCandidate: searchedNode)
            searchFinished.signal()
        }.start()
        searchStarted.wait()

        let answered = DispatchSemaphore(value: 0)
        Thread {
            _ = catalog.evidence(forWrapperCandidate: answeredNode)
            answered.signal()
        }.start()
        let isAnsweredDuringTheSearch = answered.wait(timeout: .now() + 10) == .success

        searchReleased.signal()
        searchFinished.wait()
        if !isAnsweredDuringTheSearch {
            answered.wait()
        }
        #expect(isAnsweredDuringTheSearch)
        #expect(catalog.memoizedEvidenceForTesting(prefix: searchedPrefix) != nil)
    }

    /// A type the search finds nothing for is remembered as such, and asked
    /// again without searching.
    @Test func absentVerdictIsRemembered() throws {
        let node = try Self.nominalTypeNode(module: "Test", name: "NotAWrapper")
        let prefix = try #require(PropertyWrapperTypeCatalog.wrappedValueSymbolPrefix(of: node))
        let searchCount = SearchCounter()
        let catalog = PropertyWrapperTypeCatalog(rootLookup: { _ in
            searchCount.increment()
            return []
        }, dependencyLookups: { [] })

        #expect(catalog.evidence(forWrapperCandidate: node) == nil)
        #expect(catalog.evidence(forWrapperCandidate: node) == nil)
        #expect(searchCount.value == 1)
        let storedVerdict = try #require(catalog.memoizedEvidenceForTesting(prefix: prefix))
        #expect(storedVerdict == nil)
    }
}

private final class SearchCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.withLock { count }
    }

    func increment() {
        lock.withLock { count += 1 }
    }
}

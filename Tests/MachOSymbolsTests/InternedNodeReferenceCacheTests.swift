import Foundation
import Testing
@_spi(Internals) import Demangling
@_spi(Internals) @testable import MachOSymbols
@_spi(Internals) import MachOCaches
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Unit coverage for `InternedNodeReferenceCache` — the structural
/// deduplication layer over `NodeReference(interning:)`. The batching claim
/// is that equal trees interned through one scope share a single store
/// (repeat interning returns the *same* reference, store identity included),
/// while the per-image scope stays independently evictable.
@Suite(.serialized)
final class InternedNodeReferenceCacheTests: MachOFileTests, @unchecked Sendable {
    override class var fileName: MachOFileName { .SymbolTestsCore }

    /// Two structurally equal trees (distinct `Node` instances) interned in
    /// one image scope share one store: the second call returns the first
    /// call's reference under store-identity `==`, which is exactly what
    /// re-enables the `store ===` fast path for name equality.
    @Test func repeatInterningSharesOneStore() throws {
        let firstTree = try demangleAsNodeTransient("$s7SwiftUI4TextV")
        let secondTree = try demangleAsNodeTransient("$s7SwiftUI4TextV")
        #expect(firstTree !== secondTree)

        let firstReference = InternedNodeReferenceCache.shared.reference(interning: firstTree, in: machOFile)
        let secondReference = InternedNodeReferenceCache.shared.reference(interning: secondTree, in: machOFile)
        #expect(firstReference == secondReference)
        #expect(firstReference.store === secondReference.store)
        #expect(firstReference.structurallyEquals(firstTree))
    }

    /// Structurally different trees keep distinct identities and correct
    /// content — dedup must never conflate distinct names.
    @Test func distinctTreesStayDistinct() throws {
        let textTree = try demangleAsNodeTransient("$s7SwiftUI4TextV")
        let viewTree = try demangleAsNodeTransient("$s7SwiftUI4ViewP")

        let textReference = InternedNodeReferenceCache.shared.reference(interning: textTree, in: machOFile)
        let viewReference = InternedNodeReferenceCache.shared.reference(interning: viewTree, in: machOFile)
        #expect(textReference != viewReference)
        #expect(!textReference.structurallyEquals(viewReference))
        #expect(textReference.print(using: .default) == textTree.print(using: .default))
        #expect(viewReference.print(using: .default) == viewTree.print(using: .default))
    }

    /// Concurrent first-time interning of one structural name agrees on a
    /// single winner: the insert-if-absent arbitration hands every caller
    /// the same reference, mirroring the late-demangle cache's guarantee.
    @Test func concurrentInterningSharesOneWinner() async throws {
        let mangledName = "$s7SwiftUI5ImageV"
        let references = await withTaskGroup(of: NodeReference?.self) { group in
            for _ in 0 ..< 16 {
                group.addTask { [machOFile] in
                    guard let tree = try? demangleAsNodeTransient(mangledName) else { return nil }
                    return InternedNodeReferenceCache.shared.reference(interning: tree, in: machOFile)
                }
            }
            var collected: [NodeReference?] = []
            for await reference in group {
                collected.append(reference)
            }
            return collected
        }

        let winner = try #require(references.first ?? nil)
        for reference in references {
            #expect(reference == winner)
        }
    }

    /// `remove(for:)` drops the image's bucket: a later intern mints a fresh
    /// store (identity differs) while structural equality is preserved —
    /// the per-image recycling model the indexer's cleanup relies on.
    @Test func removalDropsTheImageBucket() throws {
        let tree = try demangleAsNodeTransient("$s7SwiftUI6ButtonV")
        let referenceBeforeRemoval = InternedNodeReferenceCache.shared.reference(interning: tree, in: machOFile)

        InternedNodeReferenceCache.shared.remove(for: machOFile)

        let referenceAfterRemoval = InternedNodeReferenceCache.shared.reference(interning: tree, in: machOFile)
        #expect(referenceBeforeRemoval != referenceAfterRemoval)
        #expect(referenceBeforeRemoval.structurallyEquals(referenceAfterRemoval))
    }

    /// The process-scoped variant (no Mach-O handle) dedups the same way,
    /// in its own type-keyed bucket independent of any image bucket.
    @Test func processScopedVariantDeduplicates() throws {
        let firstTree = try demangleAsNodeTransient("$s7SwiftUI5ColorV")
        let secondTree = try demangleAsNodeTransient("$s7SwiftUI5ColorV")

        let firstReference = InternedNodeReferenceCache.shared.reference(interning: firstTree)
        let secondReference = InternedNodeReferenceCache.shared.reference(interning: secondTree)
        #expect(firstReference == secondReference)

        let imageScopedReference = InternedNodeReferenceCache.shared.reference(interning: firstTree, in: machOFile)
        #expect(imageScopedReference.structurallyEquals(firstReference))
    }
}

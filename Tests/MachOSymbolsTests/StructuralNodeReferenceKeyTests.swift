import MachOSymbols
import Demangling
import Testing

/// Regression coverage for the Stage 5a override/vtable-lookup fix.
///
/// `TypeDefinition.index` keys `methodDescriptorLookup` / `vtableOffsetLookup`
/// from override descriptors' implementation symbols, which
/// `SymbolIndexStore.demangledNodeReference(for:)` can hand back from a
/// mini store, while the member side looks them up with references from the
/// shared image store. `NodeReference`'s intrinsic `Hashable` is store-identity
/// based, so a bare-`NodeReference` key silently dropped the `override` keyword
/// and the vtable-offset comment for those symbols.
/// `StructuralNodeReferenceKey` restores structural matching; the same wrapper
/// now also keys `DefinitionBuilder`'s accessor / merged-thunk dedup and every
/// `visitedNodes` set in the declaration and dump layers.
///
/// `NodeReference(interning:)` mints a fresh private store per call, so
/// interning the same tree twice is exactly the "structurally equal, different
/// store" situation the production lookup hits.
@Suite
struct StructuralNodeReferenceKeyTests {
    private func distinctStoreReferences(of mangled: String) async throws -> (NodeReference, NodeReference) {
        let node = try await demangleAsNode(mangled)
        let first = NodeReference(interning: node)
        let second = NodeReference(interning: node)
        return (first, second)
    }

    @Test func bareNodeReferenceSplitsAcrossStores() async throws {
        let (first, second) = try await distinctStoreReferences(of: "$s4Main3fooyySiF")
        // Precondition the whole fix rests on: the intrinsic Hashable keys on
        // (store, index), so two interns of the same tree land in different
        // stores and are NOT equal.
        #expect(first.store !== second.store)
        #expect(first != second)
    }

    @Test func structuralKeyCollapsesAcrossStores() async throws {
        let (first, second) = try await distinctStoreReferences(of: "$s4Main3fooyySiF")
        let firstKey = StructuralNodeReferenceKey(first)
        let secondKey = StructuralNodeReferenceKey(second)

        #expect(firstKey == secondKey)
        var firstHasher = Hasher()
        var secondHasher = Hasher()
        firstKey.hash(into: &firstHasher)
        secondKey.hash(into: &secondHasher)
        #expect(firstHasher.finalize() == secondHasher.finalize())
    }

    @Test func structuralKeyDictionaryHitsAcrossStores() async throws {
        let (insertReference, lookupReference) = try await distinctStoreReferences(of: "$s4Main3barSiyF")

        // Mirrors the production shape: insert with the "override descriptor"
        // reference (one store), look up with the "member" reference (another).
        var lookup: [StructuralNodeReferenceKey: Int] = [:]
        lookup[StructuralNodeReferenceKey(insertReference)] = 42
        #expect(lookup[StructuralNodeReferenceKey(lookupReference)] == 42)

        // A bare-NodeReference dictionary — the pre-fix behavior — would miss.
        var bareLookup: [NodeReference: Int] = [:]
        bareLookup[insertReference] = 42
        #expect(bareLookup[lookupReference] == nil)
    }

    @Test func structuralKeySeparatesDistinctNodes() async throws {
        let fooReference = NodeReference(interning: try await demangleAsNode("$s4Main3fooyySiF"))
        let barReference = NodeReference(interning: try await demangleAsNode("$s4Main3barSiyF"))
        #expect(StructuralNodeReferenceKey(fooReference) != StructuralNodeReferenceKey(barReference))
    }
}

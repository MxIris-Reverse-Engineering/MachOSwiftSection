import Foundation
import Testing
@_spi(Internals) import Demangling
@_spi(Internals) @testable import MachOSymbols
@_spi(Internals) import MachOCaches
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based coverage for the export facts (evolution proposal 0008):
/// `isExported(name:in:)` answering the export-trie membership FACT, and
/// `isExportedIncludingDerivedSymbols(name:in:)` extending it over the
/// `Tj`/`Tq`/`Tu` derived entry-point forms — the query the `not exported`
/// annotation rides on.
///
/// The fixture (`SymbolTestsCore`, a library-evolution Release build) has
/// exactly the shape that motivated the derived-form query: public members'
/// implementation symbols are trie-absent while their dispatch thunks are
/// exported, so the bare query alone would flag every public member.
///
/// Serialized: several tests share the cached per-file storage.
@Suite(.serialized)
final class ExportedSymbolFactsTests: MachOFileTests, @unchecked Sendable {
    override class var fileName: MachOFileName { .SymbolTestsCore }

    private var storage: SymbolIndexStore.Storage {
        get throws {
            try #require(SymbolIndexStore.shared.storage(in: machOFile))
        }
    }

    /// Every Swift name enumerated from the export trie answers `true` —
    /// the sweeping check that the bitmap and the row plumbing agree with
    /// the trie on the entire population, not a sampled corner.
    @Test func everySwiftTrieNameAnswersExported() throws {
        let unsafeMachOFile = machOFile
        var checkedCount = 0
        for exportedSymbol in unsafeMachOFile.exportedSymbols where exportedSymbol.name.isSwiftSymbol {
            if SymbolIndexStore.shared.isExported(name: exportedSymbol.name, in: unsafeMachOFile) != true {
                Issue.record("exported trie name answered not-exported: \(exportedSymbol.name)")
            }
            checkedCount += 1
        }
        #expect(checkedCount > 100, "the fixture should export a substantial Swift surface")
    }

    /// A local (non-external) symtab symbol that the trie does not carry
    /// answers `false` — the negative half of the fact.
    @Test func localSymbolAbsentFromTrieAnswersNotExported() throws {
        let unsafeMachOFile = machOFile
        let exportedNames = Set(unsafeMachOFile.exportedSymbols.map(\.name))
        let localSwiftName = try #require(
            unsafeMachOFile.symbols.first {
                $0.name.isSwiftSymbol && !$0.nlist.isExternal && !exportedNames.contains($0.name)
            }?.name
        )
        #expect(SymbolIndexStore.shared.isExported(name: localSwiftName, in: unsafeMachOFile) == false)
    }

    /// The motivating case for the derived-form query: `ActorTest.mutateState`
    /// is `public` in a library-evolution build, so its implementation symbol
    /// is trie-absent (external callers dispatch through the exported `Tj`
    /// thunk). The bare query honestly answers `false`; the derived-form
    /// query recognizes the exported thunk and answers `true`.
    @Test func derivedFormQueryRecognizesThunkOnlyExportedMember() throws {
        let unsafeMachOFile = machOFile
        let implementationName = "_$s15SymbolTestsCore6ActorsO9ActorTestC11mutateStateyyF"
        #expect(SymbolIndexStore.shared.isExported(name: implementationName, in: unsafeMachOFile) == false)
        #expect(SymbolIndexStore.shared.isExported(name: implementationName + "Tj", in: unsafeMachOFile) == true)
        #expect(SymbolIndexStore.shared.isExportedIncludingDerivedSymbols(name: implementationName, in: unsafeMachOFile) == true)
    }

    /// `GenericAsyncSequenceTest.AsyncIterator` declares no initializer, so
    /// its implicit `init()` is `internal` (Swift never synthesizes a
    /// public default init): none of its forms — implementation, `Tj`,
    /// `Tq` — reach the trie, and the derived-form query stays `false`.
    /// The implementation symbol is verified present as a LOCAL (`t`)
    /// entry in the fixture's symtab, so this pins a member the interface
    /// actually renders (unlike `Classes.ClassTest`, whose unreferenced
    /// implicit init emits no implementation symbol at all).
    @Test func internalSynthesizedInitStaysNotExportedUnderDerivedFormQuery() throws {
        let unsafeMachOFile = machOFile
        let implementationName = "_$s15SymbolTestsCore013AsyncSequenceB0O07GenericdE4TestV0D8IteratorVAGy_x_GycfC"
        #expect(SymbolIndexStore.shared.isExported(name: implementationName, in: unsafeMachOFile) == false)
        #expect(SymbolIndexStore.shared.isExportedIncludingDerivedSymbols(name: implementationName, in: unsafeMachOFile) == false)
    }

    /// The fixture carries export information, so the verdict is never `nil`
    /// — pinning the tri-state contract's non-nil side (the `nil` side needs
    /// an input with no export trie, which no current fixture provides).
    @Test func imageWithExportTrieNeverAnswersNil() throws {
        let unsafeMachOFile = machOFile
        #expect(SymbolIndexStore.shared.isExported(name: "_$s_definitely_not_a_symbol", in: unsafeMachOFile) != nil)
    }
}

import Foundation
import Testing
import MachOKit
@_spi(Internals) import Demangling
@_spi(Internals) @testable import MachOSymbols
@_spi(Internals) import MachOCaches
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Equivalence pins for the offset-ized symbol table (evolution proposal
/// 0001), run against a real in-process image so the mapped-string-table
/// leg — the one the fixture-file suite cannot exercise — is covered end
/// to end:
///
/// 1. the byte-level Swift-symbol test agrees with `String.isSwiftSymbol`
///    on every entry of a real symbol table (the byte version re-states the
///    demangler's prefix list and would silently diverge if that list ever
///    grew);
/// 2. the collection sweep retains exactly the rows the former
///    `String`-keyed collection pass retained, with the same last-wins
///    canonical offsets;
/// 3. binary search over the name-order permutation answers every row's own
///    materialized name with that row (the dictionary it replaced was
///    keyed on those exact strings).
final class SymbolTableImageEquivalenceTests: MachOImageTests, @unchecked Sendable {
    @Test func byteLevelSwiftSymbolCheckMatchesStringCheck() throws {
        var checkedCount = 0
        var mismatchCount = 0
        func check(nameC: UnsafePointer<CChar>, name: String) {
            if nameBytesHaveSwiftManglingPrefix(nameC) != name.isSwiftSymbol {
                mismatchCount += 1
                if mismatchCount <= 3 {
                    Issue.record("byte-level Swift-symbol check mismatch for \(name)")
                }
            }
            checkedCount += 1
        }
        if let symbols64 = machOImage.symbols64 {
            for symbol in symbols64 {
                check(nameC: symbol.nameC, name: symbol.name)
            }
        } else if let symbols32 = machOImage.symbols32 {
            for symbol in symbols32 {
                check(nameC: symbol.nameC, name: symbol.name)
            }
        }
        #expect(mismatchCount == 0)
        #expect(checkedCount > 0)
    }

    @Test func mappedCollectionMatchesStringBasedCollection() throws {
        let storage = try #require(SymbolIndexStore.shared.storage(in: machOImage))
        let symbolTable = storage.symbolTable

        // The pre-0001 collection pass, re-run through the reader-generic
        // `String` surface: last-wins offset per unique Swift name, then
        // export-trie names for rows the symbol table did not produce.
        var expectedOffsetByName: [String: Int] = [:]
        for symbol in machOImage.symbols where symbol.name.isSwiftSymbol && !symbol.nlist.isExternal {
            expectedOffsetByName[symbol.name] = symbol.offset
        }
        for exportedSymbol in machOImage.exportedSymbols where exportedSymbol.name.isSwiftSymbol {
            if let rawOffset = exportedSymbol.offset, expectedOffsetByName[exportedSymbol.name] == nil {
                expectedOffsetByName[exportedSymbol.name] = rawOffset
            }
        }

        #expect(symbolTable.rowCount == expectedOffsetByName.count)
        var mismatchCount = 0
        for row in 0 ..< symbolTable.rowCount {
            let materializedName = symbolTable.materializedName(atRow: UInt32(row))
            if expectedOffsetByName[materializedName] != symbolTable.canonicalOffset(atRow: UInt32(row)) {
                mismatchCount += 1
                if mismatchCount <= 3 {
                    Issue.record("row \(row) (\(materializedName)) diverges from the String-based collection pass")
                }
            }
        }
        #expect(mismatchCount == 0)
    }

    @Test func binarySearchAnswersEveryRowByItsOwnName() throws {
        let storage = try #require(SymbolIndexStore.shared.storage(in: machOImage))
        let symbolTable = storage.symbolTable
        try #require(symbolTable.rowCount > 0)

        var mismatchCount = 0
        for row in 0 ..< symbolTable.rowCount {
            let materializedName = symbolTable.materializedName(atRow: UInt32(row))
            if symbolTable.row(forName: materializedName) != UInt32(row) {
                mismatchCount += 1
                if mismatchCount <= 3 {
                    Issue.record("binary search failed to find row \(row) (\(materializedName))")
                }
            }
        }
        #expect(mismatchCount == 0)
        #expect(symbolTable.row(forName: "$sNotARealSymbolName999AtAll") == nil)
        #expect(symbolTable.row(forName: "") == nil)
    }
}

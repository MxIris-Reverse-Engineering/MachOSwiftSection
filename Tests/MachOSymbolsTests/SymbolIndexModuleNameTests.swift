import Testing
@_spi(Internals) import Demangling
@_spi(Internals) @testable import MachOSymbols
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Pins `SymbolIndexStore.moduleNamesInAllSymbols(in:)`, which the interface
/// builder reads the modules it imports from (evolution proposal
/// `machofile-performance`). It walks the node store once and enters each
/// shared subtree once; what it returns must be what walking every symbol's
/// whole tree returns — the same names, met first in the same order, and the
/// same number of symbols.
@Suite
final class SymbolIndexModuleNameTests: MachOFileTests, @unchecked Sendable {
    override class var fileName: MachOFileName { .SymbolTestsCore }

    @Test func moduleNamesMatchAWalkOfEveryTree() throws {
        let (symbolCount, moduleNames) = SymbolIndexStore.shared.moduleNamesInAllSymbols(in: machOFile)

        let allSymbols = SymbolIndexStore.shared.allSymbols(in: machOFile)
        var expectedModuleNames: [String] = []
        var seenModuleNames: Set<String> = []
        for symbol in allSymbols {
            for moduleNode in symbol.demangledNode.all(of: .module) {
                if let moduleName = moduleNode.text, seenModuleNames.insert(moduleName).inserted {
                    expectedModuleNames.append(moduleName)
                }
            }
        }

        #expect(symbolCount == allSymbols.count)
        #expect(Array(moduleNames) == expectedModuleNames)
        #expect(expectedModuleNames.count > 2)
    }
}

@_spi(Support) @testable import SwiftDeclaration
@_spi(Support) @testable import SwiftIndexing
import Foundation
import Testing
import MachOKit
@_spi(Internals) @testable import MachOSymbols
@_spi(Internals) import MachOCaches
@_spi(Support) @testable import SwiftInterface
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// A `DemangledSymbol` stored in the declaration model must not keep the
/// shared per-image symbol table alive.
///
/// `SymbolIndexStore` vends values that share one `[Symbol]` buffer, which
/// keeps each of the hundreds of thousands it produces at 32 bytes. Those
/// values are meant to be dropped when the query result is; a few thousand of
/// them are instead stored in the model (accessors, functions, deallocators)
/// and outlive it, and because `[Symbol]` is a reference to its buffer, **one**
/// survivor pins the whole table and every mangled name in it. That directly
/// defeats `SwiftDeclarationIndexer.removeSubIndexer(_:)`, whose reason for
/// existing is releasing per-image memory. Measured on SwiftUI (iOS 18.5)
/// before the fix: 9,872 stored values, 9,506 distinct rows referenced out of
/// 185,988 — about 19.9 MB held for 5.1% of the data.
///
/// Members are only populated when the printer calls `index(in:)` per type, so
/// the export below is what creates the population under test.
@Suite(.serialized)
final class SymbolTableRetentionTests: MachOFileTests, @unchecked Sendable {
    override class var fileName: MachOFileName { .SymbolTestsCore }

    @Test func storedDeclarationSymbolsDoNotRetainTheSharedTable() async throws {
        let builder = try SwiftInterfaceBuilder(
            configuration: .init(indexConfiguration: .init(showCImportedTypes: false)),
            eventHandlers: [],
            in: machOFile
        )
        try await builder.prepare()
        _ = try await builder.printRoot()

        let storage = try #require(SymbolIndexStore.shared.storage(in: machOFile))
        let sharedTableRowCount = storage.symbolTable.rowCount
        // Otherwise the assertion below cannot distinguish a detached value
        // from a shared one.
        try #require(sharedTableRowCount > 1)

        var inspectedSymbolCount = 0
        var symbolsStillHoldingSharedTable: [String] = []

        func inspect(_ demangledSymbol: DemangledSymbol, describedAs description: String) {
            inspectedSymbolCount += 1
            guard demangledSymbol.retainedSymbolTableRowCount != 1 else { return }
            guard symbolsStillHoldingSharedTable.count < 10 else { return }
            symbolsStillHoldingSharedTable.append(description)
        }

        for (typeName, typeDefinition) in builder.indexer.allTypeDefinitions {
            for variable in typeDefinition.variables + typeDefinition.staticVariables {
                for accessor in variable.accessors {
                    inspect(accessor.symbol, describedAs: "\(typeName.name).\(variable.name) accessor")
                }
            }
            for subscriptDefinition in typeDefinition.subscripts + typeDefinition.staticSubscripts {
                for accessor in subscriptDefinition.accessors {
                    inspect(accessor.symbol, describedAs: "\(typeName.name) subscript accessor")
                }
            }
            let functions = typeDefinition.functions
                + typeDefinition.staticFunctions
                + typeDefinition.allocators
                + typeDefinition.constructors
            for function in functions {
                inspect(function.symbol, describedAs: "\(typeName.name).\(function.name)")
            }
            if let deallocatorSymbol = typeDefinition.deallocatorSymbol {
                inspect(deallocatorSymbol, describedAs: "\(typeName.name) deallocator")
            }
            if let destructorSymbol = typeDefinition.destructorSymbol {
                inspect(destructorSymbol, describedAs: "\(typeName.name) destructor")
            }
        }

        // A model with no stored symbols would pass vacuously.
        #expect(inspectedSymbolCount > 0)
        #expect(
            symbolsStillHoldingSharedTable.isEmpty,
            """
            \(symbolsStillHoldingSharedTable.count)+ of \(inspectedSymbolCount) stored symbols still \
            reference the \(sharedTableRowCount)-row shared table; each pins the whole buffer and every \
            name in it. First offenders: \(symbolsStillHoldingSharedTable.joined(separator: ", "))
            """
        )
    }

    /// The detach contract's SECOND layer (PR #103 review, finding M5,
    /// adjudicated): `detachedFromSharedTable()` deliberately does NOT copy
    /// `demangledNode` out of the per-image node store — the owning
    /// definition's `node` field is the same reference into the same store
    /// (the intended per-image recycling model), so a copy would reclaim
    /// nothing while the model lives and would only add an allocation per
    /// stored symbol. This test pins the sharing; changing it to a copy
    /// must be a deliberate, measured decision.
    @Test func storedDeclarationSymbolsShareTheDefinitionsNodeStore() async throws {
        let builder = try SwiftInterfaceBuilder(
            configuration: .init(indexConfiguration: .init(showCImportedTypes: false)),
            eventHandlers: [],
            in: machOFile
        )
        try await builder.prepare()
        _ = try await builder.printRoot()

        var inspectedFunctionCount = 0
        for (_, typeDefinition) in builder.indexer.allTypeDefinitions {
            let functions = typeDefinition.functions
                + typeDefinition.staticFunctions
                + typeDefinition.allocators
                + typeDefinition.constructors
            for function in functions {
                inspectedFunctionCount += 1
                #expect(
                    function.symbol.demangledNode.store === function.node.store,
                    "\(function.name): the detached symbol's node was copied out of the definition's own store — zero reclamation, pure allocation overhead"
                )
            }
        }
        #expect(inspectedFunctionCount > 0)
    }
}

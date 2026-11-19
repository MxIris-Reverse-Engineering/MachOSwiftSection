import Foundation
import MachOResolving
import Testing
import Demangling
@_spi(Internals) @testable import SwiftSymbols
@_spi(Internals) import MachOSymbols

/// The packed name-reference budgets (22-bit byte length / 40-bit byte
/// offset) are enforced against binary-supplied values: a name that cannot
/// pack must degrade — the build sweep skips its row, the standalone public
/// initializer clamps — never trap. `precondition` here is fatal in release
/// builds, so a malformed or hostile binary's symbol-table geometry would
/// decide whether the host process lives (PR #103 review, finding M3).
@Suite
struct PackedNameReferenceBudgetTests {
    private static let oversizedName = "$s" + String(repeating: "A", count: PackedNameReference.maximumByteLength + 64)

    private static func makeNodeReference() -> NodeReference {
        var nodeStoreBuilder = NodeStoreBuilder()
        let nodeIndex = nodeStoreBuilder.intern(Node.create(kind: .identifier, text: "PackedNameReferenceBudgetTests"))
        return nodeStoreBuilder.freeze().reference(at: nodeIndex)
    }

    /// The public `DemangledSymbol(symbol:demangledNode:)` initializer packs
    /// the caller's name into a one-row table; a name beyond the budget
    /// clamps to the representable prefix instead of trapping (a legitimate
    /// mangled name never approaches the 4 MB budget, so the clamp is
    /// unreachable for honest input).
    @Test func standalonePublicInitializerClampsInsteadOfTrapping() {
        let demangledSymbol = DemangledSymbol(
            symbol: Symbol(offset: 0, name: Self.oversizedName),
            demangledNode: Self.makeNodeReference()
        )
        #expect(demangledSymbol.name.utf8.count == PackedNameReference.maximumByteLength)
        #expect(Self.oversizedName.hasPrefix(demangledSymbol.name))
        #expect(demangledSymbol.retainedSymbolTableRowCount == 1)
    }
}

import Foundation
import Testing
import MachOKit
import MachOResolving
@_spi(Internals) import Demangling
@_spi(Internals) @testable import MachOSymbols
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Pins `SymbolIndexStore.symbols(for:ownedBy:ownerKind:printedWith:in:)` —
/// the per-address grouping that tells which of the names identical code
/// folding put on one address belongs to a given conformance or protocol
/// (evolution proposal `faster-lazy-definition-indexing`) — to the
/// one-symbol-at-a-time rule it replaced in `ExtensionDefinition`,
/// `ProtocolDefinition`, `ProtocolConformanceDumper` and `ProtocolDumper`:
/// list the address's symbols, demangle each by its name, take the owner
/// node, print it, compare.
///
/// SwiftUI in-process, because that is where the folding is heavy: single
/// addresses there carry over a thousand names, so a grouping that dropped a
/// name, kept a rejected one, reordered a group or stamped the wrong offset
/// would show. Every address with more than one name is compared, under both
/// owner rules and both print presets the callers use.
final class SymbolOwnerGroupingSwiftUITests: MachOImageTests, @unchecked Sendable {
    override class var imageName: MachOImageName { .SwiftUI }

    @Test(arguments: [
        (SymbolIndexStore.SymbolOwnerKind.conformingType, DemangleOptions.interfaceTypeBuilderOnly),
        (SymbolIndexStore.SymbolOwnerKind.conformingType, DemangleOptions.interfaceType),
        (SymbolIndexStore.SymbolOwnerKind.protocol, DemangleOptions.interfaceTypeBuilderOnly),
        (SymbolIndexStore.SymbolOwnerKind.protocol, DemangleOptions.interfaceType),
    ])
    func groupingAnswersLikeTheOneByOneRule(ownerKind: SymbolIndexStore.SymbolOwnerKind, options: DemangleOptions) throws {
        let storage = try #require(SymbolIndexStore.shared.storage(in: machOImage))
        let sharedOffsets = storage.symbolRowsByOffset.filter { $0.value.count > 1 }.keys.sorted()
        // Not vacuous: the image really folds, at the scale that made the
        // one-by-one rule quadratic.
        #expect(sharedOffsets.count > 100)
        #expect((storage.symbolRowsByOffset.values.map(\.count).max() ?? 0) > 100)

        var comparedOwnerCount = 0
        var mismatchCount = 0
        for offset in sharedOffsets {
            let expectedMatchesByOwnerName = OneByOneOwnerRule.matchesByOwnerName(at: offset, ownerKind: ownerKind, options: options, in: machOImage)
            for (ownerName, expectedMatches) in expectedMatchesByOwnerName {
                let answer = SymbolIndexStore.shared.symbols(for: offset, ownedBy: ownerName, ownerKind: ownerKind, printedWith: options, in: machOImage).map(OneByOneOwnerRule.Match.init)
                comparedOwnerCount += 1
                if answer != expectedMatches {
                    mismatchCount += 1
                    if mismatchCount <= 3 {
                        Issue.record("offset \(offset), owner \(ownerName): grouping answered \(answer.map(\.name)), one by one \(expectedMatches.map(\.name))")
                    }
                }
            }
            // A name no symbol there is owned by gets nothing.
            if !SymbolIndexStore.shared.symbols(for: offset, ownedBy: "No.Such.Owner", ownerKind: ownerKind, printedWith: options, in: machOImage).isEmpty {
                mismatchCount += 1
                Issue.record("offset \(offset) answered symbols for an owner none of them has")
            }
        }
        #expect(comparedOwnerCount > 0)
        #expect(mismatchCount == 0)
    }

    /// Several tasks asking about one address for the first time all build
    /// the grouping outside the lock; one is kept, and every task answers
    /// with exactly the rows the one-by-one rule finds. Run on a storage
    /// built for this test alone, so no other test has grouped the address
    /// yet.
    @Test func concurrentFirstQuestionsAgree() async throws {
        let storage = try #require(SymbolIndexStore.shared.buildStorage(for: machOImage))
        let (offset, rows) = try #require(storage.symbolRowsByOffset.max { $0.value.count < $1.value.count })
        let expectedMatchesByOwnerName = OneByOneOwnerRule.matchesByOwnerName(at: offset, ownerKind: .conformingType, options: .interfaceTypeBuilderOnly, in: machOImage)
        let ownerName = try #require(expectedMatchesByOwnerName.max { $0.value.count < $1.value.count }?.key)
        let expectedNames = try #require(expectedMatchesByOwnerName[ownerName]).map(\.name)
        #expect(storage.rowsByOwnerNameForTesting(at: offset, ownerKind: .conformingType, options: .interfaceTypeBuilderOnly) == nil)
        #expect(rows.count > 1)

        let answers = await withTaskGroup(of: [String].self) { group in
            for _ in 0 ..< 8 {
                group.addTask {
                    storage.rows(at: offset, ownedBy: ownerName, ownerKind: .conformingType, options: .interfaceTypeBuilderOnly)
                        .map { storage.symbolTable.materializedName(atRow: $0) }
                }
            }
            var answers: [[String]] = []
            for await answer in group {
                answers.append(answer)
            }
            return answers
        }
        #expect(answers.count == 8)
        #expect(answers.allSatisfy { $0 == expectedNames })
        #expect(storage.rowsByOwnerNameForTesting(at: offset, ownerKind: .conformingType, options: .interfaceTypeBuilderOnly)?[ownerName]?.count == expectedNames.count)
    }
}

/// The rule the grouping replaced, kept here as the reference: every symbol
/// the index lists at the address, demangled by name the way
/// `SymbolicDemangler.demangleSymbolReference` does, its owner taken and
/// printed, in listing order.
enum OneByOneOwnerRule {
    struct Match: Equatable {
        let name: String
        let offset: Int
        let node: StructuralNodeReferenceKey

        init(name: String, offset: Int, node: StructuralNodeReferenceKey) {
            self.name = name
            self.offset = offset
            self.node = node
        }

        init(_ demangledSymbol: DemangledSymbol) {
            self.init(name: demangledSymbol.name, offset: demangledSymbol.offset, node: StructuralNodeReferenceKey(demangledSymbol.demangledNode))
        }
    }

    static func matchesByOwnerName(at offset: Int, ownerKind: SymbolIndexStore.SymbolOwnerKind, options: DemangleOptions, in machO: MachOImage) -> [String: [Match]] {
        guard let symbols = SymbolIndexStore.shared.symbols(for: offset, in: machO) else { return [:] }
        var matchesByOwnerName: [String: [Match]] = [:]
        for symbol in symbols {
            guard let node = SymbolIndexStore.shared.demangledNodeReference(for: symbol, in: machO) else { continue }
            let ownerNode: NodeReference? = switch ownerKind {
            case .conformingType:
                node.first(of: .protocolConformance)?.children.first
            case .protocol:
                node.first(of: .protocol)
            }
            guard let ownerNode else { continue }
            matchesByOwnerName[ownerNode.print(using: options), default: []].append(Match(name: symbol.name, offset: symbol.offset, node: StructuralNodeReferenceKey(node)))
        }
        return matchesByOwnerName
    }
}

import Foundation
import Testing
import MachOKit
import MachOFoundation
import OrderedCollections
@testable import MachOSwiftSection
@testable import SwiftDeclarationRendering
import Demangling
@testable import MachOTestingSupport
import MachOFixtureSupport

/// A stand-in for `SwiftThunkAnalysis`: answers from a table keyed by the
/// thunk offset the kind-9 node carries, so the rewriter's contract can be
/// pinned without a disassembler or a binary that happens to contain an
/// availability-conditional opaque type (the fixture does not).
private struct TabledAccessorThunkResolver: AccessorThunkResolving {
    let candidatesByThunkOffset: [Int: [ConditionalUnderlyingType]]

    func underlyingTypes(forAccessorThunkAt offset: Int, in machO: MachOFile) -> [ConditionalUnderlyingType] {
        candidatesByThunkOffset[offset] ?? []
    }
}

/// The kind-9 rewriter's substitution contract (evolution proposal
/// `offline-opaque-accessor-thunk-resolution`): the current platform's branch
/// by default, any other branch on request, every branch recorded, and a
/// thunk the resolver cannot read left in place — where it prints as
/// `accessor function at N` inside its type rather than erasing the type.
@Suite(.serialized)
final class AccessorFunctionReferenceRewriterTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {
    private static let thunkOffset = 4096

    private func standardLibraryTypeNode(named name: String) -> Node {
        let moduleNode = Node.create(kind: .module, contents: .text("Swift"))
        let identifierNode = Node.create(kind: .identifier, contents: .text(name))
        return Node.create(kind: .type, children: [Node.create(kind: .structure, children: [moduleNode, identifierNode])])
    }

    /// `M.Box<accessor function at 4096>` — the shape a resolved opaque
    /// underlying type has when its argument is a kind-9 reference.
    private func boxTypeNodeAroundAccessorReference() -> Node {
        let moduleNode = Node.create(kind: .module, contents: .text("M"))
        let identifierNode = Node.create(kind: .identifier, contents: .text("Box"))
        let boxNode = Node.create(kind: .type, children: [Node.create(kind: .structure, children: [moduleNode, identifierNode])])
        let accessorReferenceNode = Node.create(kind: .accessorFunctionReference, index: UInt64(Self.thunkOffset))
        let argumentListNode = Node.create(kind: .typeList, children: [Node.create(kind: .type, children: [accessorReferenceNode])])
        return Node.create(kind: .type, children: [Node.create(kind: .boundGenericStructure, children: [boxNode, argumentListNode])])
    }

    private func twoBranchResolver() -> TabledAccessorThunkResolver {
        let satisfied = PlatformAvailabilityCondition(platform: 1, major: 26, minor: 0, patch: 0, isSatisfiedBranch: true)
        let notSatisfied = PlatformAvailabilityCondition(platform: 1, major: 26, minor: 0, patch: 0, isSatisfiedBranch: false)
        return TabledAccessorThunkResolver(candidatesByThunkOffset: [
            Self.thunkOffset: [
                ConditionalUnderlyingType(availability: satisfied, typeNode: standardLibraryTypeNode(named: "Int")),
                ConditionalUnderlyingType(availability: notSatisfied, typeNode: standardLibraryTypeNode(named: "String")),
            ],
        ])
    }

    @MainActor
    @Test func substitutesTheCurrentBranchByDefault() throws {
        let rewriter = Node.AccessorFunctionReferenceRewriter(resolver: twoBranchResolver(), machO: machOFile)
        let rewritten = rewriter.rewrite(boxTypeNodeAroundAccessorReference())
        #expect(rewritten.print(using: .default) == "M.Box<Swift.Int>")
        #expect(rewriter.didResolveAnyReference)
    }

    @MainActor
    @Test func honorsABranchSelection() throws {
        let rewriter = Node.AccessorFunctionReferenceRewriter(
            resolver: twoBranchResolver(),
            machO: machOFile,
            branchSelection: [Self.thunkOffset: 1]
        )
        let rewritten = rewriter.rewrite(boxTypeNodeAroundAccessorReference())
        #expect(rewritten.print(using: .default) == "M.Box<Swift.String>")
    }

    @MainActor
    @Test func recordsEveryBranchInTheLedger() throws {
        let ledger = Node.AccessorThunkCandidateLedger()
        let rewriter = Node.AccessorFunctionReferenceRewriter(resolver: twoBranchResolver(), machO: machOFile, candidateLedger: ledger)
        _ = rewriter.rewrite(boxTypeNodeAroundAccessorReference())
        let recorded = try #require(ledger.candidatesByThunkOffset[Self.thunkOffset])
        #expect(recorded.map { $0.typeNode.print(using: .default) } == ["Swift.Int", "Swift.String"])
        #expect(recorded.map { $0.availability?.isSatisfiedBranch } == [true, false])
    }

    /// An unreadable thunk is not a reason to lose the type around it: the
    /// reference stays and prints with the same wording a kind-9 field record
    /// gets, inside an otherwise complete type.
    @MainActor
    @Test func leavesAnUnreadableThunkInPlace() throws {
        let resolver = TabledAccessorThunkResolver(candidatesByThunkOffset: [:])
        let rewriter = Node.AccessorFunctionReferenceRewriter(resolver: resolver, machO: machOFile)
        let rewritten = rewriter.rewrite(boxTypeNodeAroundAccessorReference())
        #expect(rewritten.print(using: .default) == "M.Box<accessor function at \(Self.thunkOffset)>")
        #expect(!rewriter.didResolveAnyReference)
    }

    @MainActor
    @Test func aSelectionBeyondTheBranchesLeavesTheReferenceInPlace() throws {
        let rewriter = Node.AccessorFunctionReferenceRewriter(
            resolver: twoBranchResolver(),
            machO: machOFile,
            branchSelection: [Self.thunkOffset: 5]
        )
        let rewritten = rewriter.rewrite(boxTypeNodeAroundAccessorReference())
        #expect(rewritten.print(using: .default) == "M.Box<accessor function at \(Self.thunkOffset)>")
        #expect(!rewriter.didResolveAnyReference)
    }
}

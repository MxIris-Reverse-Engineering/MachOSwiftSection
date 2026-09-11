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

/// The opaque-type rewriter's substitution contract: a
/// `dependentGenericParamType` that resolves against the opaque type's type
/// list must be replaced by the **concrete argument**, never by the parameter's
/// own depth index literal.
///
/// The regression this pins produced visibly wrong Swift in real frameworks —
/// `SwiftUI.StaticIf<A1, 1, C1>` and
/// `SwiftUI.ContainerBackground.CustomSpecifiedPreferenceModifier<A1, 1>` in a
/// `swift-section dump`, where the `1` sits in generic-argument position and is
/// the parameter's *depth*, not a type. A `dependentGenericParamType`'s children
/// are its depth and index literals, so returning `node.firstChild` hands back
/// the depth node; the substituted `type` was looked up, validated with
/// `isKind(of: .type)`, and then discarded.
///
/// Driven against the rewriter directly rather than through
/// `resolveOpaqueType(in:)`: reaching this branch end-to-end needs a binary that
/// happens to carry an opaque type whose underlying type argument references a
/// generic parameter *and* whose node carries a matching type list (SwiftUI and
/// WidgetKit do; the fixture does not).
@Suite(.serialized)
final class OpaqueTypeGenericParameterSubstitutionTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {
    /// Builds the `Swift.Int` stand-in an opaque type's type list would carry.
    private func concreteArgumentTypeNode(named name: String) -> Node {
        let moduleNode = Node.create(kind: .module, contents: .text("Swift"))
        let identifierNode = Node.create(kind: .identifier, contents: .text(name))
        let structureNode = Node.create(kind: .structure, children: [moduleNode, identifierNode])
        return Node.create(kind: .type, children: [structureNode])
    }

    /// A `.dependentGenericParamType` exactly as the demangler builds it:
    /// two `.index` children carrying depth and index.
    private func genericParameterNode(depth: UInt64, index: UInt64) -> Node {
        Node.create(
            kind: .dependentGenericParamType,
            children: [
                Node.create(kind: .index, index: depth),
                Node.create(kind: .index, index: index),
            ]
        )
    }

    @MainActor
    @Test func substitutesTheConcreteArgumentNotTheDepthLiteral() throws {
        let argumentTypeNode = concreteArgumentTypeNode(named: "Int")
        let typeList: OrderedDictionary<Int, [Node]> = [0: [argumentTypeNode]]

        let rewriter = Node.OpaqueTypeGenericParameterRewriter(machO: machOImage, typeList: typeList)
        let rewritten = rewriter.rewrite(genericParameterNode(depth: 0, index: 0))

        #expect(
            rewritten.kind == .structure,
            "the parameter must be replaced by the substituted type, got a \(rewritten.kind) node printing as \"\(rewritten.print(using: .default))\""
        )
        #expect(rewritten.print(using: .default) == "Swift.Int")
    }

    /// The shape seen in the field: a depth-1 parameter whose substitution
    /// exists. Pre-fix this returned the depth literal, which renders as the
    /// bare number `1` in generic-argument position.
    @MainActor
    @Test func depthOneParameterDoesNotDegradeToItsDepthNumber() throws {
        let argumentTypeNode = concreteArgumentTypeNode(named: "String")
        let typeList: OrderedDictionary<Int, [Node]> = [
            1: [concreteArgumentTypeNode(named: "Bool"), argumentTypeNode],
        ]

        let rewriter = Node.OpaqueTypeGenericParameterRewriter(machO: machOImage, typeList: typeList)
        let rewritten = rewriter.rewrite(genericParameterNode(depth: 1, index: 1))

        #expect(rewritten.kind != .index, "substituting a depth-1 parameter must not yield its depth literal")
        #expect(rewritten.print(using: .default) == "Swift.String")
    }

    /// A parameter with no entry in the type list is left alone — the
    /// unsubstituted-parameter path must keep printing as `A`/`B1`, not as a
    /// number and not as some other argument.
    @MainActor
    @Test func parameterWithoutASubstitutionIsLeftUntouched() throws {
        let typeList: OrderedDictionary<Int, [Node]> = [0: [concreteArgumentTypeNode(named: "Int")]]

        let rewriter = Node.OpaqueTypeGenericParameterRewriter(machO: machOImage, typeList: typeList)
        let parameterNode = genericParameterNode(depth: 0, index: 4)
        let rewritten = rewriter.rewrite(parameterNode)

        #expect(rewritten.kind == .dependentGenericParamType)
    }

    // MARK: - Argument collection

    /// An `opaqueType` node exactly as the demangler builds it: descriptor
    /// reference, ordinal, then one `typeList` per substitution level.
    private func opaqueTypeNode(levels: [[Node]]) -> Node {
        Node.create(
            kind: .opaqueType,
            children: [
                Node.create(kind: .opaqueTypeDescriptorSymbolicReference, index: 0x1000),
                Node.create(kind: .index, index: 0),
                Node.create(
                    kind: .typeList,
                    children: levels.map { Node.create(kind: .typeList, children: $0) }
                ),
            ]
        )
    }

    /// The collection contract the substitution above depends on: each level's
    /// entry must be that level's *elements*, positionally.
    ///
    /// `Node` conforms to `Sequence` with a PREORDER iterator that yields the
    /// root itself first, so the pre-fix `for type in typeList` collected the
    /// `typeList` node, then each element, then each element's descendants.
    /// Both consequences are silent in rendered output: index 0 held a
    /// `.typeList` node, which the rewriter's `isKind(of: .type)` guard
    /// rejects — parameter 0 was never substituted and printed as `A` — while
    /// every later parameter read the element to its left or a fragment of
    /// that element's subtree, printing a real type belonging to a *different*
    /// parameter. Measured on SwiftUI (macOS 26 shared cache), 178 of 4698
    /// associated-type records carried a visibly unsubstituted parameter, and
    /// `NavigationSplitCore.ColumnView.Body` rendered
    /// `AndOperationViewInputPredicate<A1, StyleContextAcceptsPredicate<…>>`
    /// where both arguments were known and neither was the one printed.
    @MainActor
    @Test func collectsEachLevelsElementsPositionally() throws {
        let first = concreteArgumentTypeNode(named: "Int")
        let second = concreteArgumentTypeNode(named: "String")
        let third = concreteArgumentTypeNode(named: "Bool")

        let collected = Node.opaqueTypeGenericArgumentsByDepth(of: opaqueTypeNode(levels: [[first, second], [third]]))

        #expect(collected.keys.elements == [0, 1])
        #expect(collected[0]?.count == 2, "level 0 must hold exactly its two elements, got \(collected[0]?.count ?? -1)")
        #expect(collected[0]?[0].print(using: .default) == "Swift.Int")
        #expect(collected[0]?[1].print(using: .default) == "Swift.String")
        #expect(collected[1]?.count == 1, "level 1 must hold exactly its one element, got \(collected[1]?.count ?? -1)")
        #expect(collected[1]?[0].print(using: .default) == "Swift.Bool")
        for (depth, arguments) in collected {
            for (index, argument) in arguments.enumerated() {
                #expect(
                    argument.isKind(of: .type),
                    "argument \(index) of level \(depth) must be the element's own `.type` envelope, got a \(argument.kind) node"
                )
            }
        }
    }

    /// An opaque type with no generic arguments collects nothing rather than
    /// producing a level whose single entry is the empty `typeList` node.
    @MainActor
    @Test func opaqueTypeWithoutArgumentsCollectsNothing() throws {
        #expect(Node.opaqueTypeGenericArgumentsByDepth(of: opaqueTypeNode(levels: [])).isEmpty)
    }

    /// End to end over the two halves: the parameters of a two-level opaque
    /// type all substitute, and each gets *its own* argument.
    @MainActor
    @Test func everyParameterOfATwoLevelOpaqueTypeSubstitutesToItsOwnArgument() throws {
        let opaqueNode = opaqueTypeNode(levels: [
            [concreteArgumentTypeNode(named: "Int"), concreteArgumentTypeNode(named: "String")],
            [concreteArgumentTypeNode(named: "Bool")],
        ])
        let rewriter = Node.OpaqueTypeGenericParameterRewriter(
            machO: machOImage,
            typeList: Node.opaqueTypeGenericArgumentsByDepth(of: opaqueNode)
        )

        #expect(rewriter.rewrite(genericParameterNode(depth: 0, index: 0)).print(using: .default) == "Swift.Int")
        #expect(rewriter.rewrite(genericParameterNode(depth: 0, index: 1)).print(using: .default) == "Swift.String")
        #expect(rewriter.rewrite(genericParameterNode(depth: 1, index: 0)).print(using: .default) == "Swift.Bool")
    }
}

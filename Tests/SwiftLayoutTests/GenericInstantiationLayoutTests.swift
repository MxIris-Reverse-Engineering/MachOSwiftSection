import Foundation
import Testing
import MachOKit
import MachOFoundation
@testable import MachOSwiftSection
@_spi(Internals) import SwiftInspection
@testable import SwiftLayout
@testable import MachOTestingSupport
import MachOFixtureSupport
import Demangling

/// Validates concrete bound-generic field substitution: a non-generic holder
/// whose stored fields are concrete instantiations of a user generic type
/// (`GenericStructNonRequirement<Int>`, `Box<Int>?`, `Pair<Box<Int>, Int>`, …)
/// must now resolve *fully* (no field degrades to `unknown`) and match the
/// runtime field-offset vector. The broad `StaticLayoutVsRuntimeTests` only
/// asserts the computed prefix; this suite asserts complete resolution of each
/// substitution path.
@Suite
final class GenericInstantiationLayoutTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {

    /// Holders whose every field the static engine must now fully compute,
    /// keyed by short name under `SymbolTestsCore.GenericFieldLayout`.
    private static let fullyResolvingHolders = [
        "ConcreteGenericStructFieldHolder",
        "NestedGenericFieldHolder",
        "OptionalGenericFieldHolder",
        "TupleGenericFieldHolder",
        "SinglePayloadGenericEnumFieldHolder",
        "MultiPayloadGenericEnumFieldHolder",
        "ClassReferenceGenericFieldHolder",
        "FrozenGenericFieldHolder",
        "ConcreteGenericSuperclassSubclass",
    ]

    @MainActor
    @Test func concreteBoundGenericFieldHoldersFullyResolveAndMatchRuntime() async throws {
        let machO = machOImage
        let calculator = try StaticLayoutCalculator(machO: machO)

        for shortName in Self.fullyResolvingHolders {
            let qualifiedTypeName = "SymbolTestsCore.GenericFieldLayout.\(shortName)"
            let aggregate = try fieldLayout(ofQualifiedTypeName: qualifiedTypeName, with: calculator, in: machO)
            let runtimeOffsets = try #require(
                try runtimeFieldOffsets(ofQualifiedTypeName: qualifiedTypeName, in: machO),
                "no runtime field-offset vector for \(qualifiedTypeName)"
            )
            assertFullyComputed(aggregate, equals: runtimeOffsets, typeName: qualifiedTypeName)
        }
    }
}

/// Unit tests for the syntactic substitution engine itself — no fixture, no
/// runtime: hand-built `Node` trees exercise the substitution and the
/// degradation guard directly.
@Suite
struct GenericArgumentEnvironmentTests {

    private func indexNode(_ value: UInt64) -> Node {
        Node.create(kind: .index, index: value)
    }

    private func dependentParameter(depth: UInt64, index: UInt64) -> Node {
        Node.create(kind: .dependentGenericParamType, children: [indexNode(depth), indexNode(index)])
    }

    private func intStructure() -> Node {
        Node.create(kind: .structure, children: [
            Node.create(kind: .module, text: "Swift"),
            Node.create(kind: .identifier, text: "Int"),
        ])
    }

    @Test func substitutesBoundDepthZeroParameter() {
        let replacement = intStructure()
        let environment = GenericArgumentEnvironment(
            substitutions: [GenericParameterKey(depth: 0, index: 0): replacement]
        )
        let fieldNode = Node.create(kind: .type, child: dependentParameter(depth: 0, index: 0))
        let result = environment.substituting(in: fieldNode)
        #expect(result.kind == .type)
        #expect(result.firstChild?.kind == .structure)
    }

    @Test func leavesDeeperParameterIntact() {
        let environment = GenericArgumentEnvironment(
            substitutions: [GenericParameterKey(depth: 0, index: 0): intStructure()]
        )
        // Depth 1 is not in the depth-0 map: the parameter must survive untouched
        // so it later degrades to `.unknown` (nested generic contexts are out of
        // scope).
        let fieldNode = Node.create(kind: .type, child: dependentParameter(depth: 1, index: 0))
        let result = environment.substituting(in: fieldNode)
        #expect(result.firstChild?.kind == .dependentGenericParamType)
    }

    @Test func emptyEnvironmentIsIdentity() {
        let fieldNode = Node.create(kind: .type, child: dependentParameter(depth: 0, index: 0))
        let result = GenericArgumentEnvironment.empty.substituting(in: fieldNode)
        #expect(result.firstChild?.kind == .dependentGenericParamType)
    }

    @Test func makeBuildsMapForPlainTypeArguments() {
        let unboundType = Node.create(kind: .type, child: Node.create(kind: .structure, children: [
            Node.create(kind: .module, text: "Test"),
            Node.create(kind: .identifier, text: "Box"),
        ]))
        let typeList = Node.create(kind: .typeList, children: [Node.create(kind: .type, child: intStructure())])
        let boundGeneric = Node.create(kind: .boundGenericStructure, children: [unboundType, typeList])
        #expect(!GenericArgumentEnvironment.make(forBoundGenericNode: boundGeneric).isEmpty)
    }

    @Test func makeBindsValueArgument() {
        // A value (integer) generic argument occupies a parameter ordinal and
        // binds positionally like a type argument; the bound `.integer` node
        // feeds the resolver's fixed-array formulas.
        let unboundType = Node.create(kind: .type, child: Node.create(kind: .structure, children: [
            Node.create(kind: .module, text: "Test"),
            Node.create(kind: .identifier, text: "FixedArray"),
        ]))
        let valueArgument = Node.create(kind: .type, child: Node.create(kind: .integer, index: 4))
        let typeList = Node.create(kind: .typeList, children: [valueArgument])
        let boundGeneric = Node.create(kind: .boundGenericStructure, children: [unboundType, typeList])
        let environment = GenericArgumentEnvironment.make(forBoundGenericNode: boundGeneric)
        #expect(!environment.isEmpty)
        let fieldNode = Node.create(kind: .type, child: dependentParameter(depth: 0, index: 0))
        let result = environment.substituting(in: fieldNode)
        #expect(result.firstChild?.kind == .integer)
        #expect(result.firstChild?.index == 4)
    }

    @Test func makeBindsFlatPackArgument() {
        let boundGeneric = boundGenericPair(argument: Node.create(kind: .type, child: packNode([intStructure(), boolStructure()])))
        let environment = GenericArgumentEnvironment.make(forBoundGenericNode: boundGeneric)
        #expect(!environment.isEmpty)
    }

    @Test func makeBailsToEmptyOnUnexpandedPackArgument() {
        // A pack argument still containing an expansion (an unresolved
        // `Foo<repeat each T>` forwarding) is not concretely bound: the whole
        // environment degrades rather than misindex parameter ordinals.
        let parameter = dependentParameter(depth: 0, index: 0)
        let unexpandedPack = Node.create(kind: .pack, children: [
            Node.create(kind: .type, child: packExpansionNode(pattern: parameter, count: parameter)),
        ])
        let boundGeneric = boundGenericPair(argument: Node.create(kind: .type, child: unexpandedPack))
        #expect(GenericArgumentEnvironment.make(forBoundGenericNode: boundGeneric).isEmpty)
    }

    @Test func makeReturnsEmptyForNonGenericNode() {
        #expect(GenericArgumentEnvironment.make(forBoundGenericNode: intStructure()).isEmpty)
    }

    // MARK: - Pack expansion substitution

    @Test func substitutionExpandsConcretePackExpansionInTuple() {
        let environment = GenericArgumentEnvironment(substitutions: [
            GenericParameterKey(depth: 0, index: 0): packNode([intStructure(), boolStructure()]),
        ])
        let result = environment.substituting(in: expansionTupleField(over: dependentParameter(depth: 0, index: 0)))
        let tuple = result.firstChild
        #expect(tuple?.kind == .tuple)
        #expect(tuple?.children.count == 2)
        let elementNames = tuple?.children.compactMap { $0.firstChild?.firstChild?.children.at(1)?.text }
        #expect(elementNames == ["Int", "Bool"])
    }

    @Test func substitutionSubstitutesPatternPerPackElement() {
        // `(repeat Box<each T>)` — the pattern wraps the parameter; instance i
        // must substitute the *i-th element* inside the wrapper, not the whole
        // pack.
        let parameter = dependentParameter(depth: 0, index: 0)
        let pattern = Node.create(kind: .boundGenericStructure, children: [
            Node.create(kind: .type, child: Node.create(kind: .structure, children: [
                Node.create(kind: .module, text: "Test"),
                Node.create(kind: .identifier, text: "Box"),
            ])),
            Node.create(kind: .typeList, children: [Node.create(kind: .type, child: parameter)]),
        ])
        let fieldNode = Node.create(kind: .type, child: Node.create(kind: .tuple, children: [
            Node.create(kind: .tupleElement, child: Node.create(kind: .type, child: packExpansionNode(pattern: pattern, count: parameter))),
        ]))
        let environment = GenericArgumentEnvironment(substitutions: [
            GenericParameterKey(depth: 0, index: 0): packNode([intStructure(), boolStructure()]),
        ])
        let result = environment.substituting(in: fieldNode)
        let tuple = result.firstChild
        #expect(tuple?.children.count == 2)
        let firstInstance = tuple?.firstChild?.firstChild?.firstChild
        #expect(firstInstance?.kind == .boundGenericStructure)
        let firstInstanceArgument = firstInstance?.children.at(1)?.firstChild?.firstChild
        #expect(firstInstanceArgument?.children.at(1)?.text == "Int")
    }

    @Test func substitutionCollapsesSingleElementExpandedTuple() {
        // `(repeat each T)` with a one-element pack is not a one-element tuple —
        // it collapses to the element itself (the runtime returns the element's
        // metadata for unlabeled one-element tuples).
        let environment = GenericArgumentEnvironment(substitutions: [
            GenericParameterKey(depth: 0, index: 0): packNode([intStructure()]),
        ])
        let result = environment.substituting(in: expansionTupleField(over: dependentParameter(depth: 0, index: 0)))
        #expect(result.firstChild?.kind == .structure)
    }

    @Test func substitutionExpandsEmptyPackToEmptyTuple() {
        let environment = GenericArgumentEnvironment(substitutions: [
            GenericParameterKey(depth: 0, index: 0): packNode([]),
        ])
        let result = environment.substituting(in: expansionTupleField(over: dependentParameter(depth: 0, index: 0)))
        #expect(result.firstChild?.kind == .tuple)
        #expect(result.firstChild?.children.isEmpty == true)
    }

    @Test func substitutionFlattensForwardedPackArgument() {
        // `Pair<repeat each T>` as a field: the argument pack is
        // `Pack{PackExpansion(…)}` and must flatten into the concrete elements
        // before it can bind `Pair`'s own pack parameter.
        let parameter = dependentParameter(depth: 0, index: 0)
        let forwardedPack = Node.create(kind: .pack, children: [
            Node.create(kind: .type, child: packExpansionNode(pattern: parameter, count: parameter)),
        ])
        let fieldNode = Node.create(kind: .type, child: boundGenericPair(argument: Node.create(kind: .type, child: forwardedPack)))
        let environment = GenericArgumentEnvironment(substitutions: [
            GenericParameterKey(depth: 0, index: 0): packNode([intStructure(), boolStructure()]),
        ])
        let result = environment.substituting(in: fieldNode)
        let flattenedPack = result.firstChild?.children.at(1)?.firstChild?.firstChild
        #expect(flattenedPack?.kind == .pack)
        #expect(flattenedPack?.children.count == 2)
    }

    @Test func substitutionLeavesUnboundPackExpansionIntact() {
        // An expansion whose count parameter is not in the map survives
        // substitution, so the resolver later degrades that field.
        let environment = GenericArgumentEnvironment(substitutions: [
            GenericParameterKey(depth: 0, index: 1): intStructure(),
        ])
        let result = environment.substituting(in: expansionTupleField(over: dependentParameter(depth: 0, index: 0)))
        let elementInner = result.firstChild?.firstChild?.firstChild?.firstChild
        #expect(elementInner?.kind == .packExpansion)
    }

    // MARK: - Node builders

    private func boolStructure() -> Node {
        Node.create(kind: .structure, children: [
            Node.create(kind: .module, text: "Swift"),
            Node.create(kind: .identifier, text: "Bool"),
        ])
    }

    private func packNode(_ elements: [Node]) -> Node {
        Node.create(kind: .pack, children: elements.map { Node.create(kind: .type, child: $0) })
    }

    /// Children are the bare (unwrapped) pattern and count types, matching the
    /// demangler's `packExpansion` shape.
    private func packExpansionNode(pattern: Node, count: Node) -> Node {
        Node.create(kind: .packExpansion, children: [pattern, count])
    }

    /// A `.type`-wrapped `(repeat each parameter)` tuple field node.
    private func expansionTupleField(over parameter: Node) -> Node {
        Node.create(kind: .type, child: Node.create(kind: .tuple, children: [
            Node.create(kind: .tupleElement, child: Node.create(kind: .type, child: packExpansionNode(pattern: parameter, count: parameter))),
        ]))
    }

    private func boundGenericPair(argument: Node) -> Node {
        let unboundType = Node.create(kind: .type, child: Node.create(kind: .structure, children: [
            Node.create(kind: .module, text: "Test"),
            Node.create(kind: .identifier, text: "Pair"),
        ]))
        return Node.create(kind: .boundGenericStructure, children: [unboundType, Node.create(kind: .typeList, children: [argument])])
    }
}

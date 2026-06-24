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

    @Test func makeBailsToEmptyOnValueArgument() {
        // A value (integer) generic argument occupies a parameter ordinal but is
        // not a substitutable type — the whole environment degrades to empty
        // rather than risk a positional misalignment of the type parameters.
        let unboundType = Node.create(kind: .type, child: Node.create(kind: .structure, children: [
            Node.create(kind: .module, text: "Test"),
            Node.create(kind: .identifier, text: "FixedArray"),
        ]))
        let valueArgument = Node.create(kind: .type, child: Node.create(kind: .integer, index: 4))
        let typeList = Node.create(kind: .typeList, children: [valueArgument])
        let boundGeneric = Node.create(kind: .boundGenericStructure, children: [unboundType, typeList])
        #expect(GenericArgumentEnvironment.make(forBoundGenericNode: boundGeneric).isEmpty)
    }

    @Test func makeReturnsEmptyForNonGenericNode() {
        #expect(GenericArgumentEnvironment.make(forBoundGenericNode: intStructure()).isEmpty)
    }
}

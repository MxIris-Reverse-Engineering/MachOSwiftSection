import Foundation
import Testing
import MachOKit
import Demangling
@_spi(Internals) import MachOSymbols
@_spi(Support) @testable import SwiftInterface
@testable import MachOSwiftSection
@testable import MachOTestingSupport
@_spi(Internals) import SwiftInspection

// MARK: - Pure helper unit tests (no fixture)

/// Shape-only unit tests for `TypeDefinition.boundGenericTypeName`. Don't use
/// the production specialize() path so they're fast and don't depend on the
/// indexer / shared MachO image. End-to-end behavior — including
/// mangle/demangle round-trip on real Swift types — lives in the second suite
/// below.
@Suite("TypeDefinition.boundGenericTypeName (helper shape)")
struct GenericTypeNameSubstitutionHelperTests {
    private func makeStructureTypeNode(module: String = "TestModule", name: String) -> Node {
        let moduleNode = Node.create(kind: .module, contents: .text(module))
        let identifierNode = Node.create(kind: .identifier, contents: .text(name))
        let structureNode = Node.create(kind: .structure, children: [moduleNode, identifierNode])
        return Node.create(kind: .type, children: [structureNode])
    }

    private func makeBareStructureNode(module: String = "TestModule", name: String) -> Node {
        let moduleNode = Node.create(kind: .module, contents: .text(module))
        let identifierNode = Node.create(kind: .identifier, contents: .text(name))
        return Node.create(kind: .structure, children: [moduleNode, identifierNode])
    }

    @Test("struct kind produces boundGenericStructure node")
    func structKindWraps() throws {
        let unbound = TypeName(node: makeStructureTypeNode(name: "Box"), kind: .struct)
        let argument = makeStructureTypeNode(name: "Int")

        let result = TypeDefinition.boundGenericTypeName(
            unboundTypeName: unbound,
            typeArgumentNodes: [argument]
        )

        #expect(result.kind == .struct)
        #expect(result.node.kind == .type)

        let firstChild = try #require(result.node.firstChild)
        #expect(firstChild.kind == .boundGenericStructure)
        #expect(firstChild.children.count == 2)
        #expect(firstChild.children[0].kind == .type)
        #expect(firstChild.children[1].kind == .typeList)
    }

    @Test("class kind produces boundGenericClass node")
    func classKindWraps() throws {
        let moduleNode = Node.create(kind: .module, contents: .text("TestModule"))
        let identifierNode = Node.create(kind: .identifier, contents: .text("Container"))
        let classNode = Node.create(kind: .class, children: [moduleNode, identifierNode])
        let unbound = TypeName(
            node: Node.create(kind: .type, children: [classNode]),
            kind: .class
        )

        let result = TypeDefinition.boundGenericTypeName(
            unboundTypeName: unbound,
            typeArgumentNodes: [makeStructureTypeNode(name: "String")]
        )

        let firstChild = try #require(result.node.firstChild)
        #expect(firstChild.kind == .boundGenericClass)
        #expect(result.kind == .class)
    }

    @Test("enum kind produces boundGenericEnum node")
    func enumKindWraps() throws {
        let moduleNode = Node.create(kind: .module, contents: .text("TestModule"))
        let identifierNode = Node.create(kind: .identifier, contents: .text("Either"))
        let enumNode = Node.create(kind: .enum, children: [moduleNode, identifierNode])
        let unbound = TypeName(
            node: Node.create(kind: .type, children: [enumNode]),
            kind: .enum
        )

        let result = TypeDefinition.boundGenericTypeName(
            unboundTypeName: unbound,
            typeArgumentNodes: [
                makeStructureTypeNode(name: "Int"),
                makeStructureTypeNode(name: "String"),
            ]
        )

        let firstChild = try #require(result.node.firstChild)
        #expect(firstChild.kind == .boundGenericEnum)
        #expect(result.kind == .enum)
    }

    @Test("typeList contains every argument in order")
    func typeListPositionalOrder() throws {
        let unbound = TypeName(node: makeStructureTypeNode(name: "Triple"), kind: .struct)
        let argA = makeStructureTypeNode(name: "Int")
        let argB = makeStructureTypeNode(name: "String")
        let argC = makeStructureTypeNode(name: "Bool")

        let result = TypeDefinition.boundGenericTypeName(
            unboundTypeName: unbound,
            typeArgumentNodes: [argA, argB, argC]
        )

        let typeList = try #require(result.node.firstChild?.children[1])
        #expect(typeList.kind == .typeList)
        #expect(typeList.children.count == 3)
        for child in typeList.children {
            #expect(child.kind == .type)
        }
    }

    @Test("bare structure unbound (no .type wrap) is auto-wrapped")
    func unboundAutoWrap() throws {
        let bareUnbound = makeBareStructureNode(name: "Box")
        let unbound = TypeName(node: bareUnbound, kind: .struct)

        let result = TypeDefinition.boundGenericTypeName(
            unboundTypeName: unbound,
            typeArgumentNodes: [makeStructureTypeNode(name: "Int")]
        )

        let firstChild = try #require(result.node.firstChild)
        let unboundChild = firstChild.children[0]
        #expect(unboundChild.kind == .type)
        let inner = try #require(unboundChild.firstChild)
        #expect(inner.kind == .structure)
    }

    @Test("bare structure argument (no .type wrap) is auto-wrapped")
    func argumentAutoWrap() throws {
        let unbound = TypeName(node: makeStructureTypeNode(name: "Box"), kind: .struct)
        let bareArgument = makeBareStructureNode(name: "Int")

        let result = TypeDefinition.boundGenericTypeName(
            unboundTypeName: unbound,
            typeArgumentNodes: [bareArgument]
        )

        let typeList = try #require(result.node.firstChild?.children[1])
        let firstArgument = typeList.children[0]
        #expect(firstArgument.kind == .type)
        let inner = try #require(firstArgument.firstChild)
        #expect(inner.kind == .structure)
    }

    @Test(".type-wrapped input is not double-wrapped")
    func noDoubleWrap() throws {
        let unboundTypeNode = makeStructureTypeNode(name: "Box")
        let unbound = TypeName(node: unboundTypeNode, kind: .struct)
        let argumentTypeNode = makeStructureTypeNode(name: "Int")

        let result = TypeDefinition.boundGenericTypeName(
            unboundTypeName: unbound,
            typeArgumentNodes: [argumentTypeNode]
        )

        let firstChild = try #require(result.node.firstChild)
        // Identity check: helper reuses the original `.type`-wrapped node
        // rather than wrapping it again into `Type → Type → Structure`.
        #expect(firstChild.children[0] === unboundTypeNode)
        let typeList = firstChild.children[1]
        #expect(typeList.children[0] === argumentTypeNode)
    }

    @Test("empty argument list still produces a structurally valid tree")
    func emptyArgumentList() throws {
        let unbound = TypeName(node: makeStructureTypeNode(name: "Box"), kind: .struct)
        let result = TypeDefinition.boundGenericTypeName(
            unboundTypeName: unbound,
            typeArgumentNodes: []
        )

        let firstChild = try #require(result.node.firstChild)
        #expect(firstChild.kind == .boundGenericStructure)
        let typeList = firstChild.children[1]
        #expect(typeList.kind == .typeList)
        #expect(typeList.children.isEmpty)
    }
}

// MARK: - End-to-end fixture-driven tests
//
// Drives the full path: real fixture descriptor → GenericSpecializer →
// TypeDefinition.specialize(with:typeArgumentNodes:in:) → mangle/demangle
// round-trip on the substituted typeName.
//
// Reuses fixtures already declared inside `GenericSpecializationTests` —
// `TestUnconstrainedStruct<A>`, `TestRefClass`, `TestClassConstraintStruct`,
// `TestDualAssociatedStruct`. Those types are guaranteed to be present in the
// test binary (the `GenericSpecializationTests.Specialize` suite already
// drives them through `specializer.specialize(...)` end-to-end), so
// `structDescriptor(named:)` reliably resolves them.
@Suite(.serialized)
struct GenericTypeNameSubstitutionEndToEndTests: GenericSpecializationTestingEnvironment {

    /// Builds a `Type → Structure(Module(Swift), Identifier(name))` node
    /// without going through the demangler — keeps the test independent of
    /// `demangleAsNode` symbol-mangling conventions.
    private func makeSwiftStdLibTypeNode(name: String) -> Node {
        let moduleNode = Node.create(kind: .module, contents: .text("Swift"))
        let identifierNode = Node.create(kind: .identifier, contents: .text(name))
        let structureNode = Node.create(kind: .structure, children: [moduleNode, identifierNode])
        return Node.create(kind: .type, children: [structureNode])
    }

    /// Resolve a base `TypeDefinition` for the named fixture by walking the
    /// indexer's already-prepared dictionary.
    ///
    /// Production flow (`RuntimeSwiftSection.specialize(for:with:)`) goes
    /// through this same path: the engine never re-instantiates a
    /// `TypeDefinition` from a raw descriptor — it always finds the one the
    /// indexer already produced. Constructing a fresh `TypeDefinition` from a
    /// raw descriptor here was crashing inside `MetadataReader.demangleContext`
    /// because the file-form descriptors from `machO.swift.typeContextDescriptors`
    /// require additional in-process context the test wasn't supplying.
    private func resolveTypeDefinition(named substring: String) async throws -> TypeDefinition {
        let resolvedIndexer = try await indexer
        return try #require(
            resolvedIndexer.allTypeDefinitions.first(where: { entry in
                entry.key.name.contains(substring)
            })?.value,
            "expected indexer to have a TypeDefinition whose typeName contains \"\(substring)\""
        )
    }

    @Test("specialize substitutes the typeName into a BoundGenericStructure")
    func substitutesStructTypeName() async throws {
        let baseDefinition = try await resolveTypeDefinition(named: "TestUnconstrainedStruct")
        let specializer = GenericSpecializer(indexer: try await indexer)
        let request = try specializer.makeRequest(for: baseDefinition.type.typeContextDescriptorWrapper)
        let result = try specializer.specialize(request, with: ["A": .metatype(Int.self)])

        let intTypeNode = makeSwiftStdLibTypeNode(name: "Int")

        let specialized = try await baseDefinition.specialize(
            with: result,
            typeArgumentNodes: [intTypeNode],
            in: machO
        )

        // Top-level shape: `Type → BoundGenericStructure(...)`.
        #expect(specialized.typeName.kind == .struct)
        #expect(specialized.typeName.node.kind == .type)
        let firstChild = try #require(specialized.typeName.node.firstChild)
        #expect(firstChild.kind == .boundGenericStructure)
        #expect(firstChild.children.count == 2)
        #expect(firstChild.children[1].kind == .typeList)
        #expect(firstChild.children[1].children.count == 1)
    }

    @Test("specialized typeName mangles successfully and demangles back to BoundGenericStructure")
    func mangleDemangleRoundTrip() async throws {
        let baseDefinition = try await resolveTypeDefinition(named: "TestDualAssociatedStruct")
        let specializer = GenericSpecializer(indexer: try await indexer)
        let request = try specializer.makeRequest(for: baseDefinition.type.typeContextDescriptorWrapper)
        let result = try specializer.specialize(request, with: [
            "A": .metatype([Int].self),
            "B": .metatype([String].self),
        ])

        let intTypeNode = makeSwiftStdLibTypeNode(name: "Int")
        let stringTypeNode = makeSwiftStdLibTypeNode(name: "String")

        let specialized = try await baseDefinition.specialize(
            with: result,
            typeArgumentNodes: [intTypeNode, stringTypeNode],
            in: machO
        )

        // `RuntimeSwiftSection.makeRuntimeObject` calls `mangleAsString` on
        // every specialized child to derive a unique `RuntimeObject.name`.
        // If the substituted typeName produced an invalid Node tree, this
        // call would throw and the sidebar would silently lose the
        // specialization.
        let mangled = try await mangleAsString(specialized.typeName.node)
        #expect(!mangled.isEmpty)

        // Round-trip: the demangler must accept the mangler's output and
        // recover a `boundGenericStructure` shape with two type arguments
        // in the original positional order.
        //
        // `mangleAsString` produces a *type-mangled* body with no global
        // symbol prefix (`$s…` / `_T…`). Pass `isType: true` so the demangler
        // skips the symbol-prefix check and parses the body directly as a
        // type — mirrors what `MetadataReader.demangleType(for:)` does
        // internally when handed a `MangledName`.
        let reconstructed = try await demangleAsNode(mangled, isType: true)
        let reconstructedBound = try #require(reconstructed.first(of: .boundGenericStructure))
        #expect(reconstructedBound.children.count == 2)
        let reconstructedTypeList = reconstructedBound.children[1]
        #expect(reconstructedTypeList.kind == .typeList)
        #expect(reconstructedTypeList.children.count == 2)
    }

    @Test("nil typeArgumentNodes leaves typeName at the unbound form")
    func nilSubstitutionPreservesUnboundTypeName() async throws {
        let baseDefinition = try await resolveTypeDefinition(named: "TestUnconstrainedStruct")
        let specializer = GenericSpecializer(indexer: try await indexer)
        let request = try specializer.makeRequest(for: baseDefinition.type.typeContextDescriptorWrapper)
        let result = try specializer.specialize(request, with: ["A": .metatype(Int.self)])

        // Default parameter: typeArgumentNodes is nil — preserves backward
        // compatibility with the pre-substitution behavior.
        let specialized = try await baseDefinition.specialize(
            with: result,
            in: machO
        )

        let firstChild = try #require(specialized.typeName.node.firstChild)
        #expect(firstChild.kind != .boundGenericStructure)
        #expect(firstChild.kind == .structure)
    }

    @Test("two specializations of the same generic produce distinct mangled names")
    func uniqueMangledNamesPerSpecialization() async throws {
        let baseDefinition = try await resolveTypeDefinition(named: "TestUnconstrainedStruct")
        let specializer = GenericSpecializer(indexer: try await indexer)
        let request = try specializer.makeRequest(for: baseDefinition.type.typeContextDescriptorWrapper)

        let intResult = try specializer.specialize(request, with: ["A": .metatype(Int.self)])
        let stringResult = try specializer.specialize(request, with: ["A": .metatype(String.self)])

        let intTypeNode = makeSwiftStdLibTypeNode(name: "Int")
        let stringTypeNode = makeSwiftStdLibTypeNode(name: "String")

        let specializedInt = try await baseDefinition.specialize(
            with: intResult,
            typeArgumentNodes: [intTypeNode],
            in: machO
        )
        let specializedString = try await baseDefinition.specialize(
            with: stringResult,
            typeArgumentNodes: [stringTypeNode],
            in: machO
        )

        let mangledInt = try await mangleAsString(specializedInt.typeName.node)
        let mangledString = try await mangleAsString(specializedString.typeName.node)

        // The whole point of the typeName substitution is that every
        // specialization gets a unique mangled name — that is what makes
        // `RuntimeObject.name` (built from this string) distinguish
        // `Box<Int>` from `Box<String>` in the sidebar.
        #expect(mangledInt != mangledString)
        #expect(!mangledInt.isEmpty)
        #expect(!mangledString.isEmpty)
    }

    @Test("outer specialization derives nested child specializations without moving existing child specializations")
    func outerSpecializationDerivesNestedChildSpecializationsWithoutMovingExistingChildSpecializations() async throws {
        _ = GenericSpecializationTests.NestedGenericInheritedOnlyOuter<Int>.self
        _ = GenericSpecializationTests.NestedGenericInheritedOnlyOuter<String>.self

        let resolvedIndexer = try await indexer
        let baseDefinition = try #require(
            resolvedIndexer.allTypeDefinitions.first(where: { entry in
                entry.value.typeName.currentName == "NestedGenericInheritedOnlyOuter"
            })?.value,
            "expected indexer to have the root outer fixture definition"
        )
        let valueChild = try #require(
            baseDefinition.typeChildren.first { $0.typeName.name.contains("Value") },
            "expected outer generic fixture to have its nested Value type before specialization"
        )
        let specializer = GenericSpecializer(indexer: try await indexer)

        let valueRequest = try specializer.makeRequest(for: valueChild.type.typeContextDescriptorWrapper)
        let valueStringResult = try specializer.specialize(valueRequest, with: ["A": .metatype(String.self)])
        let stringNode = makeSwiftStdLibTypeNode(name: "String")
        let manuallySpecializedValue = try await valueChild.specialize(
            with: valueStringResult,
            typeArgumentNodes: [stringNode],
            in: machO
        )
        #expect(valueChild.specializedChildren.contains { $0 === manuallySpecializedValue })

        let outerRequest = try specializer.makeRequest(for: baseDefinition.type.typeContextDescriptorWrapper)
        let outerSelection = SpecializationSelection(arguments: ["A": .metatype(Int.self)])
        let outerResult = try specializer.specialize(outerRequest, with: outerSelection)
        let intNode = makeSwiftStdLibTypeNode(name: "Int")

        let specialized = try await baseDefinition.specialize(
            with: outerResult,
            typeArgumentNodes: [intNode],
            derivingNestedSpecializationsWith: specializer,
            selection: outerSelection,
            typeArgumentNodesByParameter: ["A": intNode],
            in: machO
        )

        #expect(valueChild.specializedChildren.count == 1)
        #expect(valueChild.specializedChildren.contains { $0 === manuallySpecializedValue },
                "outer specialization must not move or duplicate existing manual nested specializations")

        let specializedChildNames = specialized.typeChildren.map(\.typeName.name)
        let specializedFailureReason = try #require(
            specialized.typeChildren.first {
                $0.isSpecialized
                    && $0.typeName.name.contains("FailureReason")
            },
            "expected specialized outer to derive FailureReason; got \(specializedChildNames)"
        )
        let specializedValue = try #require(
            specialized.typeChildren.first {
                $0.isSpecialized
                    && $0.typeName.name.contains("Value")
            },
            "expected specialized outer to derive Value; got \(specializedChildNames)"
        )
        #expect(specializedFailureReason.parent === specialized)
        #expect(specializedValue.parent === specialized)
        #expect(specializedFailureReason.metadata != nil)
        #expect(specializedValue.metadata != nil)
        #expect(!specializedChildNames.contains { $0.contains("NeedsOwnParameter") },
                "nested child requiring its own B parameter should be ignored when only the outer A binding is available")
        #expect(!specialized.typeChildren.contains { $0 === valueChild },
                "specialized outer must contain detached child specializations, not the canonical generic child")
    }

    @Test("outer specialization skips children whose own specialization throws and keeps deriving the rest")
    func outerSpecializationSkipsFailingChildAndKeepsDerivingSiblings() async throws {
        // `NestedGenericInheritedOnlyOuter.LayoutConstrainedInner` carries
        // `where A: AnyObject`. With `A = Int` (value type) the inner
        // specialization preflight rejects the binding and throws — the
        // exact failure shape the best-effort `catch { continue }` in
        // `deriveNestedSpecializedTypeChildren` is meant to absorb.
        //
        // Pre-fix, that throw bubbled up through the whole derivation,
        // so calling `specialize(...)` on the outer would abort and the
        // caller would lose the rest of the (perfectly valid) siblings.
        // Post-fix, the outer specialization still returns; failing
        // sibling silently drops out, the rest of the tree is preserved.
        _ = GenericSpecializationTests.NestedGenericInheritedOnlyOuter<Int>.self

        let resolvedIndexer = try await indexer
        let baseDefinition = try #require(
            resolvedIndexer.allTypeDefinitions.first(where: { entry in
                entry.value.typeName.currentName == "NestedGenericInheritedOnlyOuter"
            })?.value,
            "expected indexer to surface the root outer fixture definition"
        )
        // Sanity #1: indexer must actually surface
        // `LayoutConstrainedInner` as a canonical child of the outer
        // fixture. Without this, the catch-coverage assertion below
        // would be vacuously true (an unindexed child can never appear
        // in derivedChildren, regardless of whether the catch fires).
        let canonicalChildNames = baseDefinition.typeChildren.map(\.typeName.name)
        #expect(canonicalChildNames.contains { $0.contains("LayoutConstrainedInner") },
                "indexer must surface LayoutConstrainedInner as a child of the outer fixture for this test to exercise the catch; got \(canonicalChildNames)")

        let specializer = GenericSpecializer(indexer: try await indexer)

        // Sanity #2: specializing LayoutConstrainedInner directly with
        // `A = Int` must throw — otherwise the outer derivation has
        // nothing to catch and the test would still pass for the wrong
        // reason (silent skip via `hasCompleteBinding`, not via the
        // catch).
        let layoutConstrainedChild = try #require(
            baseDefinition.typeChildren.first { $0.typeName.name.contains("LayoutConstrainedInner") },
            "expected LayoutConstrainedInner among outer's typeChildren"
        )
        let layoutRequest = try specializer.makeRequest(for: layoutConstrainedChild.type.typeContextDescriptorWrapper)
        #expect(throws: (any Error).self,
                "LayoutConstrainedInner must reject A = Int so the outer catch actually fires") {
            _ = try specializer.specialize(layoutRequest, with: ["A": .metatype(Int.self)])
        }

        let outerRequest = try specializer.makeRequest(for: baseDefinition.type.typeContextDescriptorWrapper)
        let outerSelection = SpecializationSelection(arguments: ["A": .metatype(Int.self)])
        let outerResult = try specializer.specialize(outerRequest, with: outerSelection)
        let intNode = makeSwiftStdLibTypeNode(name: "Int")

        // Must not throw — the LayoutConstrainedInner failure has to be
        // absorbed inside `deriveNestedSpecializedTypeChildren`.
        let specialized = try await baseDefinition.specialize(
            with: outerResult,
            typeArgumentNodes: [intNode],
            derivingNestedSpecializationsWith: specializer,
            selection: outerSelection,
            typeArgumentNodesByParameter: ["A": intNode],
            in: machO
        )

        let specializedChildNames = specialized.typeChildren.map(\.typeName.name)
        // Valid siblings still derive.
        #expect(specialized.typeChildren.contains {
            $0.isSpecialized && $0.typeName.name.contains("FailureReason")
        }, "expected FailureReason<Int> to derive despite a failing sibling; got \(specializedChildNames)")
        #expect(specialized.typeChildren.contains {
            $0.isSpecialized && $0.typeName.name.contains("Value")
        }, "expected Value<Int> to derive despite a failing sibling; got \(specializedChildNames)")
        // Failing sibling is dropped — not appended in any partial form.
        #expect(!specializedChildNames.contains { $0.contains("LayoutConstrainedInner") },
                "LayoutConstrainedInner specialization throws under A = Int and must be silently skipped; got \(specializedChildNames)")
    }
}

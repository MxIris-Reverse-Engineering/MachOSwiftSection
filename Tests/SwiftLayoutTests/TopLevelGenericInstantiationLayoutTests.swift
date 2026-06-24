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

/// Validates the *top-level* concrete generic instantiation entry points
/// (`fieldLayout(of:genericArguments:)` and
/// `fieldLayout(forInstantiationMangledName:)`): asked to lay out `Foo<Int>`
/// directly (rather than only when it is reached as a field), the engine must
/// fully resolve every field and match the runtime *specialized* metadata's
/// field-offset vector. This is the top-level counterpart to
/// `GenericInstantiationLayoutTests`, which only exercises bound-generic types
/// as fields of a non-generic holder.
@Suite
final class TopLevelGenericInstantiationLayoutTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {

    /// A concrete instantiation to check: the generic type's short name under
    /// `SymbolTestsCore.GenericFieldLayout`, the static substitution argument
    /// (a `.type`-wrapped type node), and the matching runtime metatype passed
    /// to the metadata accessor for the ground truth.
    private struct Instantiation {
        let shortName: String
        let staticArgument: Node
        let runtimeArgument: Any.Type
    }

    /// A `.type`-wrapped `Swift.<identifier>` structure node, the static
    /// substitution argument form the depth-0 environment expects.
    private func swiftStructTypeNode(_ identifier: String) -> Node {
        Node.create(kind: .type, child: Node.create(kind: .structure, children: [
            Node.create(kind: .module, text: "Swift"),
            Node.create(kind: .identifier, text: identifier),
        ]))
    }

    @MainActor
    @Test func topLevelGenericInstantiationsFullyResolveAndMatchRuntime() async throws {
        let machO = machOImage
        let calculator = try StaticLayoutCalculator(machO: machO)

        // Requirement-free generic struct and class instantiations: the runtime
        // accessor needs only the concrete argument metatype (no witness
        // tables) to materialize the specialized metadata.
        let instantiations = [
            Instantiation(shortName: "GenericStructNonRequirement", staticArgument: swiftStructTypeNode("Int"), runtimeArgument: Int.self),
            Instantiation(shortName: "GenericStructNonRequirement", staticArgument: swiftStructTypeNode("String"), runtimeArgument: String.self),
            Instantiation(shortName: "GenericClassNonRequirement", staticArgument: swiftStructTypeNode("Int"), runtimeArgument: Int.self),
        ]

        for instantiation in instantiations {
            let qualifiedTypeName = "SymbolTestsCore.GenericFieldLayout.\(instantiation.shortName)"
            let label = "\(qualifiedTypeName)<\(instantiation.runtimeArgument)>"
            let aggregate = try fieldLayout(
                ofGenericQualifiedTypeName: qualifiedTypeName,
                genericArguments: [instantiation.staticArgument],
                with: calculator,
                in: machO
            )
            let runtimeOffsets = try #require(
                try runtimeFieldOffsets(ofGenericQualifiedTypeName: qualifiedTypeName, argumentMetatype: instantiation.runtimeArgument, in: machO),
                "no runtime field-offset vector for \(label)"
            )
            assertFullyComputed(aggregate, equals: runtimeOffsets, typeName: label)
        }
    }

    /// The `forInstantiationMangledName:` entry, fed a *real* bound-generic
    /// reference read from the binary (the `intInstance` field of a holder, a
    /// mangled `GenericStructNonRequirement<Int>`), must resolve identically to
    /// the runtime specialized metadata.
    @MainActor
    @Test func instantiationMangledNameEntryResolvesAgainstBinaryReference() async throws {
        let machO = machOImage
        let calculator = try StaticLayoutCalculator(machO: machO)

        let mangledName = try #require(
            try fieldMangledTypeName(ofHolder: "ConcreteGenericStructFieldHolder", fieldName: "intInstance", in: machO),
            "could not read the intInstance field's mangled type name"
        )
        let aggregate = try calculator.fieldLayout(forInstantiationMangledName: mangledName)
        let runtimeOffsets = try #require(
            try runtimeFieldOffsets(
                ofGenericQualifiedTypeName: "SymbolTestsCore.GenericFieldLayout.GenericStructNonRequirement",
                argumentMetatype: Int.self,
                in: machO
            ),
            "no runtime field-offset vector for GenericStructNonRequirement<Int>"
        )
        assertFullyComputed(aggregate, equals: runtimeOffsets, typeName: "GenericStructNonRequirement<Int> (via binary mangled name)")
    }

    /// A value (integer) generic argument is not a substitutable type, so the
    /// environment degrades to empty: the parameter-dependent field (`field2: A`)
    /// and everything after it must report `.unknown`, while the leading
    /// argument-independent field (`field1: Double`) is still computed.
    @MainActor
    @Test func valueArgumentDegradesParameterDependentFields() async throws {
        let machO = machOImage
        let calculator = try StaticLayoutCalculator(machO: machO)

        let valueArgument = Node.create(kind: .type, child: Node.create(kind: .integer, index: 4))
        let aggregate = try fieldLayout(
            ofGenericQualifiedTypeName: "SymbolTestsCore.GenericFieldLayout.GenericStructNonRequirement",
            genericArguments: [valueArgument],
            with: calculator,
            in: machO
        )

        // Only the leading argument-independent field resolves; the running
        // offset stops at the first unresolved (parameter-dependent) field.
        #expect(aggregate.computedFieldOffsets == [0])
        let unresolved = aggregate.fields.contains { if case .unknown = $0.resolution { return true }; return false }
        #expect(unresolved, "a value argument must leave the parameter-dependent fields unknown")
    }

    // MARK: - Helpers

    /// The mangled type name of a stored field on a holder type, read straight
    /// from the field descriptor — a genuine bound-generic reference as the
    /// compiler emitted it.
    private func fieldMangledTypeName(
        ofHolder holderShortName: String,
        fieldName: String,
        in machO: MachOImage
    ) throws -> MangledName? {
        let qualifiedTypeName = "SymbolTestsCore.GenericFieldLayout.\(holderShortName)"
        for contextDescriptor in try machO.swift.contextDescriptors {
            guard let descriptor = contextDescriptor.typeContextDescriptorWrapper, descriptor.isStruct || descriptor.isClass else { continue }
            guard
                let name = (try? MetadataReader.demangleContext(for: contextDescriptor, in: machO))
                    .flatMap(NodeTypeNaming.nominalQualifiedName(of:)),
                name == qualifiedTypeName
            else { continue }
            let records = try descriptor.typeContextDescriptor.fieldDescriptor(in: machO).records(in: machO)
            for record in records where (try? record.fieldName(in: machO)) == fieldName {
                return try record.mangledTypeName(in: machO)
            }
        }
        return nil
    }
}

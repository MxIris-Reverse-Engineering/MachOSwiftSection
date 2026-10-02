import Foundation
import Testing
import MachOKit
import MachOFoundation
@testable import MachOSwiftSection
@_spi(Internals) import SwiftInspection
@testable import SwiftLayout
import MachOTestingSupport
import Demangling

/// Layouts of instantiations a `GenericArgumentBinding` describes — an
/// offline specialization's (evolution proposal
/// `offline-generic-specialization`) — checked against the runtime's
/// metadata for the same instantiation, and the expanded field-offset tree's
/// naming of a member of a concrete type.
@Suite
struct BoundInstantiationLayoutTests {
    private func typeNode(_ type: Any.Type) throws -> Node {
        try demangleAsNode(try #require(_mangledTypeName(type)), isType: true)
    }

    /// The runtime's field-offset vector of the instantiation the fixture's
    /// accessor builds for `arguments` (key arguments only, no witness
    /// tables needed by these shapes).
    private func runtimeFieldOffsets(ofTypeNamed typeName: String, arguments: [Any.Type]) throws -> [Int] {
        let machOImage = try GenericSpecializationFixture.loadedImage()
        let descriptor = try GenericSpecializationFixture.typeContextDescriptor(named: typeName, in: machOImage)
        let accessor = try #require(try descriptor.typeContextDescriptor.metadataAccessorFunction(in: machOImage.context))
        let response = try accessor(request: .init(), metadatas: arguments.map { try Metadata.createInProcess($0) }, witnessTables: [])
        switch try response.value.resolve(in: .inProcess) {
        case .struct(let structMetadata):
            return try structMetadata.fieldOffsets(in: .inProcess).map { Int($0) }
        case .class(let classMetadata):
            return try classMetadata.fieldOffsets(in: .inProcess).map { Int($0) }
        default:
            Issue.record("\(typeName) has no field-offset vector")
            return []
        }
    }

    private func staticFieldOffsets(ofTypeNamed typeName: String, binding: GenericArgumentBinding) throws -> AggregateFieldLayout {
        let machOFile = try GenericSpecializationFixture.machOFile()
        let descriptor = try GenericSpecializationFixture.typeContextDescriptor(named: typeName, in: machOFile)
        let calculator = StaticLayoutCalculator(imageUniverse: try ImageUniverse.dependencyClosure(root: machOFile, searchPaths: [.systemDyldSharedCache]))
        return try calculator.fieldLayout(of: descriptor, genericArgumentBinding: binding)
    }

    @Test("a nested type behind a level that declares no parameter lays out like the runtime's")
    func nestedTypeBehindNonDeclaringLevel() throws {
        let binding = GenericArgumentBinding(argumentsByDepth: [[try typeNode(Int.self)], [try typeNode(String.self)]])

        let aggregate = try staticFieldOffsets(ofTypeNamed: "PlainInner", binding: binding)

        assertFullyComputed(aggregate, equals: try runtimeFieldOffsets(ofTypeNamed: "PlainInner", arguments: [Int.self, String.self]), typeName: "DepthOuter<Int>.Middle.PlainInner<String>")
    }

    @Test("a class over a generic superclass lays out like the runtime's")
    func classOverGenericSuperclass() throws {
        let binding = GenericArgumentBinding(argumentsByDepth: [[try typeNode(Int16.self)]])

        let aggregate = try staticFieldOffsets(ofTypeNamed: "DerivedBox", binding: binding)

        assertFullyComputed(aggregate, equals: try runtimeFieldOffsets(ofTypeNamed: "DerivedBox", arguments: [Int16.self]), typeName: "DerivedBox<Int16>")
    }

    @Test("a fixed parameter's argument lays out the field it types")
    func fixedParameter() throws {
        // `OuterElement` is pinned to `Int` and takes no key argument; the
        // binding still carries it, as `GenericInstantiation` fills it in.
        let binding = GenericArgumentBinding(argumentsByDepth: [[try typeNode(Int.self)], [try typeNode(Int8.self)]])

        let aggregate = try staticFieldOffsets(ofTypeNamed: "ConstrainedInner", binding: binding)

        assertFullyComputed(aggregate, equals: try runtimeFieldOffsets(ofTypeNamed: "ConstrainedInner", arguments: [Int8.self]), typeName: "DepthOuter<Int>.ConstrainedInner<Int8>")
    }

    /// The tree used to name the member as the substitution left it,
    /// `Swift.Optional<Swift.Array<Swift.Int>.Element>`, and to stop there;
    /// the runtime's walk names — and expands — the type it is.
    @Test("a member of a concrete type is named and expanded as the type its record names")
    func concreteMemberIsProjectedInTheTree() throws {
        let machOFile = try GenericSpecializationFixture.machOFile()
        let holderDescriptor = try #require(try GenericSpecializationFixture.typeContextDescriptor(named: "ElementsHolderHolder", in: machOFile).struct)
        let holderRecord = try #require(try holderDescriptor.fieldDescriptor(in: machOFile.context).records(in: machOFile.context).first)
        let calculator = StaticLayoutCalculator(imageUniverse: try ImageUniverse.dependencyClosure(root: machOFile, searchPaths: [.systemDyldSharedCache]))

        let tree = calculator.nestedFieldOffsetTree(forMangledTypeName: try holderRecord.mangledTypeName(in: machOFile.context), baseOffset: 0, depthLimit: 8)

        let first = try #require(tree.first { $0.fieldName == "first" }, "\(tree.map(\.fieldName))")
        #expect(first.typeName == "Swift.Optional<Swift.Int>")
        // The payload is `Swift.Int` itself, which expands into its
        // `_value`, as the runtime's walk does.
        let payload = try #require(first.children.first)
        #expect(payload.typeName == "Swift.Int")
        #expect(payload.children.map(\.fieldName) == ["_value"])
    }
}

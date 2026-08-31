import Foundation
import Testing
import Demangling
@testable import MachOSwiftSection
@testable import SwiftInspection

// MARK: - Fixtures (internal on purpose: plain identifiers keep the test
// resolver's name matching trivial)

struct HashableConstrainedBox<Element: Hashable> {
    var element: Element
}

struct UnconstrainedBox<Element> {
    var element: Element
}

struct ElementEquatableBox<Elements: Sequence> where Elements.Element: Equatable {
    var elements: Elements
}

final class OuterGenericFixture<First> {
    struct Inner {
        var value: Int
    }

    struct InnerPair<Second> {
        var first: First?
        var second: Second?
    }
}

// MARK: - Tests

@Suite
struct RuntimeMetadataTypeBuilderTests {
    /// The oracle loop: a live type's own mangled name, decoded through the
    /// builder, must come back as the identical runtime metadata (metadata is
    /// process-unique, so `==` on `Any.Type` is semantic equality).
    private func expectRoundTrip(
        _ expectedType: Any.Type,
        builder: RuntimeMetadataTypeBuilder = RuntimeMetadataTypeBuilder(),
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let mangledTypeName = try #require(_mangledTypeName(expectedType), sourceLocation: sourceLocation)
        let typeNode = try demangleAsNode(mangledTypeName, isType: true)
        let rebuiltType = try builder.metadataType(for: typeNode)
        #expect(
            ObjectIdentifier(rebuiltType) == ObjectIdentifier(expectedType),
            "mangling \(mangledTypeName): rebuilt \(rebuiltType), expected \(expectedType)",
            sourceLocation: sourceLocation
        )
    }

    // MARK: Concrete structural types (no descriptor resolver needed)

    @Test(arguments: [
        [Int].self,
        ContiguousArray<String>.self,
        [String: Int].self,
        Set<Int>.self,
        Int?.self,
        String??.self,
        Range<Int>.self,
        ClosedRange<Double>.self,
        Result<String, any Error>.self,
        UnsafePointer<Int>.self,
        UnsafeMutableBufferPointer<UInt8>.self,
    ] as [Any.Type])
    func standardLibraryGenericRoundTrips(expectedType: Any.Type) throws {
        try expectRoundTrip(expectedType)
    }

    @Test(arguments: [
        Int.self,
        String.self,
        Double.self,
        StaticString.self,
        (Int, String).self,
        (first: Int, second: String).self,
        ((Int) -> String).self,
        ((Int, String) throws -> Void).self,
        (@Sendable (Int) async -> String).self,
        Int.Type.self,
        [Int].Type.self,
        Any.self,
        AnyObject.self,
        Any.Type.self,
        (any Error).self,
        (any CustomStringConvertible).self,
        (any CustomStringConvertible & AnyObject).self,
    ] as [Any.Type])
    func concreteTypeRoundTrips(expectedType: Any.Type) throws {
        try expectRoundTrip(expectedType)
    }

    @Test func objectiveCClassRoundTrips() throws {
        try expectRoundTrip(NSObject.self)
    }

    @Test func bridgedObjectiveCClassRoundTrips() throws {
        try expectRoundTrip(NSString.self)
    }

    @Test func objectiveCProtocolExistentialRoundTrips() throws {
        try expectRoundTrip((any NSCopying).self)
    }

    // MARK: Generic fixtures through the descriptor-resolver seam

    /// Resolves the fixture declarations above by their plain identifier,
    /// handing back the descriptor read from a known instantiation's
    /// metadata — the seam a host with a real index would fill.
    private static let fixtureDescriptorResolver: @Sendable (Node) -> UnsafeRawPointer? = { declarationNode in
        let knownInstantiations: [String: Any.Type] = [
            "HashableConstrainedBox": HashableConstrainedBox<Int>.self,
            "UnconstrainedBox": UnconstrainedBox<Int>.self,
            "ElementEquatableBox": ElementEquatableBox<[Int]>.self,
            "OuterGenericFixture": OuterGenericFixture<Int>.self,
            "Inner": OuterGenericFixture<Int>.Inner.self,
            "InnerPair": OuterGenericFixture<Int>.InnerPair<Int>.self,
        ]
        var declarationName: String?
        for child in declarationNode.children.reversed() where child.kind == .identifier {
            declarationName = child.text
            break
        }
        guard let declarationName, let instantiation = knownInstantiations[declarationName] else { return nil }
        guard let wrapper = try? Metadata.createInProcess(instantiation).typeContextDescriptorWrapper() else { return nil }
        return try? wrapper.typeContextDescriptor.asPointer
    }

    private var fixtureBuilder: RuntimeMetadataTypeBuilder {
        RuntimeMetadataTypeBuilder(nominalTypeDescriptorResolver: Self.fixtureDescriptorResolver)
    }

    @Test func unconstrainedGenericInstantiates() throws {
        try expectRoundTrip(UnconstrainedBox<String>.self, builder: fixtureBuilder)
    }

    @Test func conformanceConstrainedGenericResolvesItsWitnessTable() throws {
        try expectRoundTrip(HashableConstrainedBox<String>.self, builder: fixtureBuilder)
    }

    @Test func dependentMemberRequirementSubjectResolvesThroughAssociatedTypeWitness() throws {
        try expectRoundTrip(ElementEquatableBox<[Int]>.self, builder: fixtureBuilder)
    }

    @Test func nestedTypeInheritsParentGenericArguments() throws {
        try expectRoundTrip(OuterGenericFixture<Int8>.Inner.self, builder: fixtureBuilder)
    }

    @Test func nestedGenericCombinesParentAndOwnArguments() throws {
        try expectRoundTrip(OuterGenericFixture<Int8>.InnerPair<Int64>.self, builder: fixtureBuilder)
    }

    @Test func genericArgumentsComposeStructurally() throws {
        try expectRoundTrip(HashableConstrainedBox<[Int?]>.self, builder: fixtureBuilder)
    }

    // MARK: Generic parameter bindings

    @Test func boundGenericParameterSubstitutes() throws {
        let parameterNode = try demangleAsNode("x", isType: true)
        let builder = RuntimeMetadataTypeBuilder(
            genericParameterMetadataTypes: [.init(depth: 0, index: 0): Int.self]
        )
        #expect(try ObjectIdentifier(builder.metadataType(for: parameterNode)) == ObjectIdentifier(Int.self))
    }

    @Test func boundGenericParameterComposesIntoStructuralTypes() throws {
        let arrayOfParameterNode = try demangleAsNode("SayxG", isType: true)
        let builder = RuntimeMetadataTypeBuilder(
            genericParameterMetadataTypes: [.init(depth: 0, index: 0): String.self]
        )
        #expect(try ObjectIdentifier(builder.metadataType(for: arrayOfParameterNode)) == ObjectIdentifier([String].self))
    }

    // MARK: Honest rejections

    @Test func unboundGenericParameterFailsWithTypedError() throws {
        let parameterNode = try demangleAsNode("x", isType: true)
        let builder = RuntimeMetadataTypeBuilder()
        #expect(throws: TypeLookupError.self) {
            try builder.metadataType(for: parameterNode)
        }
    }

    @Test func namedGenericWithoutResolverFailsWithTypedError() throws {
        let mangledTypeName = try #require(_mangledTypeName(UnconstrainedBox<Int>.self))
        let typeNode = try demangleAsNode(mangledTypeName, isType: true)
        let builder = RuntimeMetadataTypeBuilder()
        #expect(throws: TypeLookupError.self) {
            try builder.metadataType(for: typeNode)
        }
    }
}

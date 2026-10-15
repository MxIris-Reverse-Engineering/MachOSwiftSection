@_spi(Support) @testable import SwiftSpecialization
@_spi(Support) @testable import SwiftDeclaration
@_spi(Support) @testable import SwiftIndexing
import Foundation
import Testing
import MachOKit
import Demangling
@testable import MachOSwiftSection
import MachOTestingSupport

/// `GenericSpecializer` names each parameter by its `(depth, index)` — `A`,
/// `B`, `A1`, … — and collects the parameter's requirements by matching that
/// name against the requirement's subject, which the demangler names from the
/// depth the mangling carries. A depth counts only the contexts that declare
/// parameters.
///
/// The specializer used to count every generic ancestor as a depth.
/// `InnerElement` in
/// `DepthOuter<OuterElement>.Middle.Inner<InnerElement: Hashable>` became `A2`
/// while its requirement reads `A1: Hashable`, so the requirement was never
/// collected: the request offered `InnerElement` every type instead of the
/// Hashable ones, and `specialize` built one witness table too few and failed
/// its key-argument count check.
@Suite(.serialized)
struct CanonicalParameterDepthTests {
    private func runtimeRequest(forTypeNamed name: String) async throws -> (specializer: GenericSpecializer<MachOImage>, request: SpecializationRequest) {
        let indexer = try await GenericSpecializationFixtureIndexers.shared.runtime()
        let descriptor = try GenericSpecializationFixture.typeContextDescriptor(named: name, in: indexer.machO)
        let specializer = GenericSpecializer(indexer: indexer)
        return (specializer, try specializer.makeRequest(for: descriptor))
    }

    private func protocolRequirementNames(of parameter: SpecializationRequest.Parameter) -> [String] {
        parameter.requirements.compactMap { requirement in
            guard case .protocol(let info) = requirement else { return nil }
            return info.protocolName.name
        }
    }

    @Test("a parameter behind a level that declares none takes the next depth")
    func parameterBehindNonDeclaringLevel() async throws {
        let (_, request) = try await runtimeRequest(forTypeNamed: "Inner")

        #expect(request.parameters.map(\.name) == ["A", "A1"])
        #expect(request.parameters.map(\.depth) == [0, 1])
        let innerParameter = try #require(request.parameters.last)
        #expect(protocolRequirementNames(of: innerParameter) == ["Swift.Hashable"])
    }

    @Test("a constrained extension of a nested generic type spans both of its depths")
    func constrainedExtensionOfNestedGeneric() async throws {
        let (_, request) = try await runtimeRequest(forTypeNamed: "DeepConstrainedInner")

        // `OuterElement` is pinned to `Int`, so it takes no key argument and
        // is not offered; `MiddleElement` is `SecondMiddle`'s parameter at
        // depth 1, `InnerElement` the type's own at depth 2.
        #expect(request.parameters.map(\.name) == ["A1", "A2"])
        let innerParameter = try #require(request.parameters.last)
        #expect(protocolRequirementNames(of: innerParameter) == ["Swift.Hashable"])
    }

    @Test("the runtime specializes a type behind a level that declares no parameter")
    func runtimeSpecializesTypeBehindNonDeclaringLevel() async throws {
        let (specializer, request) = try await runtimeRequest(forTypeNamed: "Inner")
        let selection = SpecializationSelection(arguments: Dictionary(uniqueKeysWithValues: zip(
            request.parameters.map(\.name),
            [SpecializationSelection.Argument.metatype(Int.self), .metatype(String.self)]
        )))

        let result = try specializer.specialize(request, with: selection)

        let metatype = unsafeBitCast(try result.metadata().asPointer, to: Any.Type.self)
        let runtimeName = try #require(_mangledTypeName(metatype))
        let printedName = try await demangleAsNode(runtimeName, isType: true).print(using: .default)
        #expect(printedName == "GenericSpecializationFixture.DepthOuter<Swift.Int>.Middle.Inner<Swift.String>")
    }
}

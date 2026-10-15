@_spi(Support) @testable import SwiftSpecialization
@_spi(Support) @testable import SwiftDeclaration
@_spi(Support) @testable import SwiftIndexing
import Foundation
import Testing
import MachOKit
@testable import MachOSwiftSection
import MachOTestingSupport

/// A conformance the indexed images record under a generic type's unbound
/// name may hold only under conditions — `Array: Hashable where Element:
/// Hashable` — and the offline check (evolution proposal
/// `offline-generic-specialization`) took the record for proof whatever the
/// arguments: an `Array` of a type that is not `Hashable` passed a `Hashable`
/// requirement with no warning, and `specialize` named an instantiation that
/// cannot exist. The runtime path rejects the same selection.
/// `staticPreflight` promises a warning for a conformance offline evidence
/// cannot settle, and a conditional one is such a conformance.
@Suite(.serialized)
struct OfflineConditionalConformanceTests {
    @Test("a conditional conformance is not taken for proof whatever the arguments")
    func conditionalConformanceIsNotTakenForProof() async throws {
        let indexer = try await GenericSpecializationFixtureIndexers.shared.offline()
        let definition = try GenericSpecializationFixtureIndexers.typeDefinition(named: "Inner", in: indexer)
        let specializer = GenericSpecializer(indexer: indexer)
        let request = try specializer.makeRequest(for: definition.typeContextDescriptorWrapper)
        let hashableParameter = try #require(request.parameters.first { $0.name == "A1" })
        let array = try #require(
            hashableParameter.candidates.first { $0.typeName.declaredNameForTesting == "Array" },
            "A1 offers no Array candidate"
        )
        let unconstrainedParameter = try #require(request.parameters.first { $0.name == "A" })
        let unmarked = try #require(
            unconstrainedParameter.candidates.first { $0.typeName.declaredNameForTesting == "FixtureUnmarked" },
            "A offers no FixtureUnmarked candidate"
        )

        let validation = specializer.staticPreflight(
            selection: [
                "A": .metatype(Int.self),
                "A1": .boundGeneric(baseCandidate: array, innerArguments: ["A": .candidate(unmarked)]),
            ],
            for: request
        )

        #expect(
            validation.warnings.contains {
                guard case .conformanceCheckFailed(let parameterName, let protocolName, _) = $0 else { return false }
                return parameterName == "A1" && protocolName == "Swift.Hashable"
            } || !validation.isValid,
            "errors \(validation.errors) warnings \(validation.warnings)"
        )
    }
}

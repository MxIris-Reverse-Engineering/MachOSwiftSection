@_spi(Support) @testable import SwiftSpecialization
@_spi(Support) @testable import SwiftDeclaration
@_spi(Support) @testable import SwiftIndexing
import Foundation
import Testing
import MachOKit
import Demangling
@testable import MachOSwiftSection
@_spi(Internals) import SwiftInspection
import SwiftDeclarationRendering
import MachOTestingSupport

/// A same-type requirement between two parameters — `TiedParameterPair<First,
/// Second> where First == Second` — leaves the second without a key argument:
/// the request offers `A` alone, and the instantiation binds `B` to the same
/// type. The compiler writes the requirement with the parameter that keeps
/// its key argument on the LEFT, so the argument has to be copied from left
/// to right, as the runtime's `_gatherWrittenGenericParameters` does when the
/// left-hand parameter is already filled in.
///
/// `GenericInstantiation` read such a requirement only right to left (a
/// parameter fixed by the type on the right): the offline specialization
/// threw `unresolvedFixedParameter`, and the runtime path's `typeName` fell
/// back, silently, to `TiedParameterPair<Swift.Int>` while its header reads
/// the runtime's `TiedParameterPair<Swift.Int, Swift.Int>`.
@Suite(.serialized)
struct TiedParameterInstantiationTests {
    private static let moduleName = GenericSpecializationFixture.moduleName

    @Test("an offline specialization binds a parameter tied to another by a same-type requirement")
    func offlineSpecializationBindsTheTiedParameter() async throws {
        let indexer = try await GenericSpecializationFixtureIndexers.shared.offline()
        let definition = try GenericSpecializationFixtureIndexers.typeDefinition(named: "TiedParameterPair", in: indexer)
        let specializer = GenericSpecializer(indexer: indexer)
        let request = try specializer.makeRequest(for: definition.typeContextDescriptorWrapper)

        let result = try specializer.specialize(request, with: ["A": .metatype(Int.self)])

        #expect(result.typeName.name(using: .default) == "\(Self.moduleName).TiedParameterPair<Swift.Int, Swift.Int>")
    }

    @Test("a runtime specialization's name binds a parameter tied to another as the runtime does")
    func runtimeSpecializationNameBindsTheTiedParameter() async throws {
        let indexer = try await GenericSpecializationFixtureIndexers.shared.runtime()
        let definition = try GenericSpecializationFixtureIndexers.typeDefinition(named: "TiedParameterPair", in: indexer)
        let specializer = GenericSpecializer(indexer: indexer)
        let request = try specializer.makeRequest(for: definition.typeContextDescriptorWrapper)
        let result = try specializer.specialize(request, with: ["A": .metatype(Int.self)])
        let runtimeMetatype = unsafeBitCast(try result.metadata().asPointer, to: Any.Type.self)
        let runtimeName = try #require(RuntimeTypeNameDemangling.node(forMetatype: runtimeMetatype))

        let specialized = try await definition.specialize(
            with: result,
            typeArgumentNodes: [try await demangleAsNode("Si", isType: true)],
            in: indexer.machO
        )

        let printedName = await specialized.typeName.node.materialize().print(using: .default)
        let printedRuntimeName = await runtimeName.print(using: .default)
        #expect(specialized.typeName.node.materialize() == runtimeName, "specialized \(printedName) runtime \(printedRuntimeName)")
    }
}

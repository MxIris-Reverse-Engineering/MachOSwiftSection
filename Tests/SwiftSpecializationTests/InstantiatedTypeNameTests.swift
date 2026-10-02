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

/// A specialization's name hangs each argument on the level that declares
/// its parameter — `Outer<Swift.Int>.Inner<Swift.String>`, the shape the
/// runtime gives the instantiation (`_buildDemanglingForContext`) — whether
/// the specialization was made in-process or offline (evolution proposal
/// `offline-generic-specialization`).
/// A host type a test hands over as an argument; a `Sendable` stand-in for
/// the metatype, which a parameterized test's arguments must be.
enum HostTypeArgument: String, Sendable {
    case int
    case string
    case bool

    var type: Any.Type {
        switch self {
        case .int: Int.self
        case .string: String.self
        case .bool: Bool.self
        }
    }
}

@Suite(.serialized)
struct InstantiatedTypeNameTests {
    private static let moduleName = GenericSpecializationFixture.moduleName

    // MARK: - The runtime path's name

    /// The runtime path used to put every argument on the innermost level:
    /// `Outer.Middle.Inner<Swift.Int, Swift.String>`, a name of no type.
    /// RuntimeViewer shows `typeName` in its sidebar and keys the
    /// specialization on it.
    @Test("a runtime specialization's name puts each argument on its own level")
    func runtimeSpecializationNameIsNested() async throws {
        let indexer = try await GenericSpecializationFixtureIndexers.shared.runtime()
        let definition = try GenericSpecializationFixtureIndexers.typeDefinition(named: "Inner", in: indexer)
        let specializer = GenericSpecializer(indexer: indexer)
        let request = try specializer.makeRequest(for: definition.typeContextDescriptorWrapper)
        let result = try specializer.specialize(request, with: ["A": .metatype(Int.self), "A1": .metatype(String.self)])

        let specialized = try await definition.specialize(
            with: result,
            typeArgumentNodes: [try await demangleAsNode("Si", isType: true), try await demangleAsNode("SS", isType: true)],
            in: indexer.machO
        )

        #expect(specialized.typeName.name(using: .default) == "\(Self.moduleName).DepthOuter<Swift.Int>.Middle.Inner<Swift.String>")
    }

    /// A nested type that declares no parameter of its own is derived from
    /// its parent's binding; its name used to read `NestedHost.Plain<Swift.Int>`.
    @Test("a derived nested type's name keeps the argument on its parent")
    func derivedNestedTypeNameKeepsTheArgumentOnItsParent() async throws {
        let indexer = try await GenericSpecializationFixtureIndexers.shared.runtime()
        let definition = try GenericSpecializationFixtureIndexers.typeDefinition(named: "NestedHost", in: indexer)
        let specializer = GenericSpecializer(indexer: indexer)
        let request = try specializer.makeRequest(for: definition.typeContextDescriptorWrapper)
        let selection: SpecializationSelection = ["A": .metatype(Int.self)]
        let result = try specializer.specialize(request, with: selection)
        let intNode = try await demangleAsNode("Si", isType: true)

        let specialized = try await definition.specialize(
            with: result,
            typeArgumentNodes: [intNode],
            derivingNestedSpecializationsWith: specializer,
            selection: selection,
            typeArgumentNodesByParameter: ["A": intNode],
            in: indexer.machO
        )

        #expect(specialized.typeChildren.map { $0.typeName.name(using: .default) } == ["\(Self.moduleName).NestedHost<Swift.Int>.Plain"])
    }

    // MARK: - The offline name against the runtime's

    /// Specializes the fixture type `typeName` both ways with the same host
    /// types, and returns the runtime's name for the instantiation and the
    /// offline result's.
    private func names(
        ofTypeNamed typeName: String,
        arguments hostArguments: [String: HostTypeArgument]
    ) async throws -> (runtime: Node, offline: Node) {
        let arguments = hostArguments.mapValues(\.type)
        let runtimeIndexer = try await GenericSpecializationFixtureIndexers.shared.runtime()
        let runtimeDefinition = try GenericSpecializationFixtureIndexers.typeDefinition(named: typeName, in: runtimeIndexer)
        let runtimeSpecializer = GenericSpecializer(indexer: runtimeIndexer)
        let runtimeRequest = try runtimeSpecializer.makeRequest(for: runtimeDefinition.typeContextDescriptorWrapper)
        let runtimeResult = try runtimeSpecializer.specialize(runtimeRequest, with: SpecializationSelection(arguments: arguments.mapValues { .metatype($0) }))
        // The runtime's name as the library reads it: through the one entry
        // that rewrites the anonymous context the runtime spells a private
        // type's by address.
        let runtimeMetatype = unsafeBitCast(try runtimeResult.metadata().asPointer, to: Any.Type.self)
        let runtimeName = try #require(RuntimeTypeNameDemangling.node(forMetatype: runtimeMetatype))

        let offlineIndexer = try await GenericSpecializationFixtureIndexers.shared.offline()
        let offlineDefinition = try GenericSpecializationFixtureIndexers.typeDefinition(named: typeName, in: offlineIndexer)
        let offlineSpecializer = GenericSpecializer(indexer: offlineIndexer)
        let offlineRequest = try offlineSpecializer.makeRequest(for: offlineDefinition.typeContextDescriptorWrapper)
        let offlineResult = try offlineSpecializer.specialize(offlineRequest, with: SpecializationSelection(arguments: arguments.mapValues { .metatype($0) }))

        return (runtimeName, offlineResult.typeName.node.materialize())
    }

    @Test(
        "an offline instantiation is named like the runtime names it",
        arguments: [
            ("PairBox", ["A": .int, "B": .string] as [String: HostTypeArgument]),
            ("Inner", ["A": .int, "A1": .string]),
            ("Pair", ["A": .int, "A1": .bool]),
            ("Plain", ["A": .int]),
            ("ReferenceBox", ["A": .int]),
            ("MultiChoice", ["A": .int, "B": .string]),
            ("PrivateBox", ["A": .int]),
        ]
    )
    func offlineNameMatchesTheRuntime(typeName: String, arguments: [String: HostTypeArgument]) async throws {
        let (runtimeName, offlineName) = try await names(ofTypeNamed: typeName, arguments: arguments)

        let printedOfflineName = await offlineName.print(using: .default)
        let printedRuntimeName = await runtimeName.print(using: .default)
        #expect(offlineName == runtimeName, "offline \(printedOfflineName) runtime \(printedRuntimeName)")
    }

    /// A parameter a same-type requirement fixes takes no argument, yet its
    /// level still binds it: `A == Int` in the extension declaring
    /// `ConstrainedInner`. The runtime recovers it from the requirement, and
    /// so does the offline path.
    @Test("a fixed parameter is named by the type its same-type requirement fixes it to")
    func fixedParameterIsNamedLikeTheRuntime() async throws {
        let (runtimeName, offlineName) = try await names(ofTypeNamed: "ConstrainedInner", arguments: ["A1": .string])

        let printedOfflineName = await offlineName.print(using: .default)
        let printedRuntimeName = await runtimeName.print(using: .default)
        #expect(offlineName == runtimeName, "offline \(printedOfflineName) runtime \(printedRuntimeName)")
        #expect(printedOfflineName == "(extension in \(Self.moduleName)):\(Self.moduleName).DepthOuter<Swift.Int>.ConstrainedInner<Swift.String>")
    }

    /// A type in another module's extension: the extension context stays,
    /// carrying the extended type.
    @Test("a type nested in another module's extension is named like the runtime names it")
    func typeInCrossModuleExtensionIsNamedLikeTheRuntime() async throws {
        let (runtimeName, offlineName) = try await names(ofTypeNamed: "IntExtensionBox", arguments: ["A": .string])

        let printedOfflineName = await offlineName.print(using: .default)
        let printedRuntimeName = await runtimeName.print(using: .default)
        #expect(offlineName == runtimeName, "offline \(printedOfflineName) runtime \(printedRuntimeName)")
    }

    /// For a constrained extension of a nested generic type the runtime puts
    /// every extension argument into the innermost list of the extended type
    /// and leaves its outer level unbound —
    /// `DepthOuter<A>.SecondMiddle<Int, Bool>`, a name of no type. The offline name binds each level; the difference
    /// is deliberate and documented on `SymbolicDemangler.instantiatedTypeNode`.
    @Test("a constrained extension of a nested generic type binds each extended level")
    func constrainedExtensionOfNestedGenericBindsEachLevel() async throws {
        let offlineIndexer = try await GenericSpecializationFixtureIndexers.shared.offline()
        let definition = try GenericSpecializationFixtureIndexers.typeDefinition(named: "DeepConstrainedInner", in: offlineIndexer)
        let specializer = GenericSpecializer(indexer: offlineIndexer)
        let request = try specializer.makeRequest(for: definition.typeContextDescriptorWrapper)

        let result = try specializer.specialize(request, with: ["A1": .metatype(Bool.self), "A2": .metatype(String.self)])

        #expect(result.typeName.name(using: .default) == "(extension in \(Self.moduleName)):\(Self.moduleName).DepthOuter<Swift.Int>.SecondMiddle<Swift.Bool>.DeepConstrainedInner<Swift.String>")
        #expect(result.binding.argumentsByDepth.map { $0.map { $0.print(using: .default) } } == [["Swift.Int"], ["Swift.Bool"], ["Swift.String"]])
    }
}

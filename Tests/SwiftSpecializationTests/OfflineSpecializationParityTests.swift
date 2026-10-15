@_spi(Support) @testable import SwiftSpecialization
@_spi(Support) @testable import SwiftDeclaration
@_spi(Support) @testable import SwiftIndexing
@_spi(Support) @testable import SwiftPrinting
import Foundation
import Testing
import MachOKit
import Demangling
@testable import MachOSwiftSection
import MachOTestingSupport
import SwiftDeclarationRendering

/// One instantiation, specialized and printed both ways, must read the same
/// byte for byte (evolution proposal `offline-generic-specialization`): the
/// runtime path from the loaded image and its metadata, the offline path
/// from the same binary read as a file, with every layout comment on. The
/// offline path never asks the runtime, so agreement is the evidence that the
/// instantiation's name, its field types and its layout were all derived
/// right.
///
/// The shapes avoid three places the two paths differ by design, for
/// unspecialized types too: a single-payload enum whose empty cases ride the
/// payload's extra inhabitants (only the runtime can project their bytes); a
/// tuple-typed field (the runtime breaks its type layout down per element);
/// and a field of a generic standard-library struct such as `Array`, whose
/// expanded offsets the runtime's walk stops at the first nested field typed
/// by the struct's own parameter (`_buffer: _ArrayBuffer<Element>`) while the
/// static walk descends through it.
@Suite(.serialized)
struct OfflineSpecializationParityTests {
    private static var configuration: SwiftDeclarationPrintConfiguration {
        var configuration = SwiftDeclarationPrintConfiguration()
        configuration.printFieldOffset = true
        configuration.printTypeLayout = true
        configuration.printEnumLayout = true
        configuration.printExpandedFieldOffsets = true
        return configuration
    }

    /// A host-supplied argument, which both paths accept.
    enum ParityArgument {
        case host(Any.Type)
        /// A fixture type bound to arguments of its own: `.boundGeneric`.
        case bound(typeName: String, arguments: [String: Any.Type])
    }

    private func selection<MachO>(
        _ arguments: [String: ParityArgument],
        for request: SpecializationRequest,
        indexer: SwiftDeclarationIndexer<MachO>
    ) throws -> SpecializationSelection {
        var selectionArguments: [String: SpecializationSelection.Argument] = [:]
        for (parameterName, argument) in arguments {
            switch argument {
            case .host(let type):
                selectionArguments[parameterName] = .metatype(type)
            case .bound(let typeName, let innerArguments):
                let parameter = try #require(request.parameters.first { $0.name == parameterName })
                let baseCandidate = try #require(parameter.candidates.first { $0.typeName.declaredNameForTesting == typeName })
                selectionArguments[parameterName] = .boundGeneric(baseCandidate: baseCandidate, innerArguments: innerArguments.mapValues { .metatype($0) })
            }
        }
        return SpecializationSelection(arguments: selectionArguments)
    }

    private func runtimeInterface(ofTypeNamed typeName: String, arguments: [String: ParityArgument]) async throws -> String {
        let indexer = try await GenericSpecializationFixtureIndexers.shared.runtime()
        let definition = try GenericSpecializationFixtureIndexers.typeDefinition(named: typeName, in: indexer)
        let specializer = GenericSpecializer(indexer: indexer)
        let request = try specializer.makeRequest(for: definition.typeContextDescriptorWrapper)
        let selection = try selection(arguments, for: request, indexer: indexer)
        let result = try specializer.specialize(request, with: selection)
        // What RuntimeViewer hands over: a node per parameter — the
        // specialization's name is built from them, and the runtime path
        // derives the nested types the binding covers with them. Read here
        // from each argument's resolved metadata.
        var typeArgumentNodesByParameter: [String: Node] = [:]
        for resolvedArgument in result.resolvedArguments {
            let argumentType = unsafeBitCast(try resolvedArgument.metadata.asPointer, to: Any.Type.self)
            typeArgumentNodesByParameter[resolvedArgument.parameterName] = try #require(RuntimeTypeNameDemangling.node(forMetatype: argumentType))
        }
        let typeArgumentNodes = request.parameters.compactMap { typeArgumentNodesByParameter[$0.name] }
        let specialized = try await definition.specialize(
            with: result,
            typeArgumentNodes: typeArgumentNodes,
            derivingNestedSpecializationsWith: specializer,
            selection: selection,
            typeArgumentNodesByParameter: typeArgumentNodesByParameter,
            in: indexer.machO
        )
        let printer = SwiftDeclarationPrinter<MachOImage>(configuration: Self.configuration, in: indexer.machO)
        return try await printer.printTypeDefinition(specialized).string
    }

    private func offlineInterface(ofTypeNamed typeName: String, arguments: [String: ParityArgument]) async throws -> String {
        let indexer = try await GenericSpecializationFixtureIndexers.shared.offline()
        let definition = try GenericSpecializationFixtureIndexers.typeDefinition(named: typeName, in: indexer)
        let specializer = GenericSpecializer(indexer: indexer)
        let request = try specializer.makeRequest(for: definition.typeContextDescriptorWrapper)
        let selection = try selection(arguments, for: request, indexer: indexer)
        let result = try specializer.specialize(request, with: selection)
        let specialized = try await definition.specialize(
            with: result,
            derivingNestedSpecializationsWith: specializer,
            in: indexer.machO
        )
        let printer = SwiftDeclarationPrinter<MachOFile>(configuration: Self.configuration, in: indexer.machO)
        return try await printer.printTypeDefinition(specialized).string
    }

    private func expectParity(ofTypeNamed typeName: String, arguments: [String: ParityArgument], sourceLocation: SourceLocation = #_sourceLocation) async throws {
        let runtime = try await runtimeInterface(ofTypeNamed: typeName, arguments: arguments)
        let offline = try await offlineInterface(ofTypeNamed: typeName, arguments: arguments)
        #expect(offline == runtime, "offline:\n\(offline)\nruntime:\n\(runtime)", sourceLocation: sourceLocation)
        // A guard against both sides degrading the same way: the comments
        // must be there.
        #expect(offline.contains("Type Layout") || offline.contains("Enum Layout"), "no layout comment:\n\(offline)", sourceLocation: sourceLocation)
    }

    /// The runtime path printed no `Enum Layout` for any generic enum, a
    /// specialization included, although the specialization's metadata says
    /// exactly how the instantiation lays out.
    @Test("the runtime path lays out a specialized generic enum")
    func runtimePathLaysOutASpecializedGenericEnum() async throws {
        let runtime = try await runtimeInterface(ofTypeNamed: "MultiChoice", arguments: ["A": .host(Int.self), "B": .host(String.self)])

        #expect(runtime.contains("Enum Layout"), "\(runtime)")
    }

    @Test("a struct with two parameters")
    func structWithTwoParameters() async throws {
        try await expectParity(ofTypeNamed: "PairBox", arguments: ["A": .host(Int.self), "B": .host(String.self)])
    }

    @Test("a final class")
    func finalClass() async throws {
        try await expectParity(ofTypeNamed: "ReferenceBox", arguments: ["A": .host(Int.self)])
    }

    @Test("a class whose superclass is generic too")
    func classWithGenericSuperclass() async throws {
        try await expectParity(ofTypeNamed: "DerivedBox", arguments: ["A": .host(Int.self)])
    }

    @Test("a single-payload enum")
    func singlePayloadEnum() async throws {
        try await expectParity(ofTypeNamed: "SingleChoice", arguments: ["A": .host(Int.self)])
    }

    @Test("a multi-payload enum")
    func multiPayloadEnum() async throws {
        try await expectParity(ofTypeNamed: "MultiChoice", arguments: ["A": .host(Int.self), "B": .host(String.self)])
    }

    @Test("a field typed by a member of the argument")
    func associatedTypeField() async throws {
        // `String`'s `Element` is `Character`: `first` reads `Swift.Character?`
        // once the member is projected through the conformance.
        try await expectParity(ofTypeNamed: "ElementsHolder", arguments: ["A": .host(String.self)])
    }

    @Test("a nested type behind a level that declares no parameter")
    func nestedGenericBehindNonDeclaringLevel() async throws {
        try await expectParity(ofTypeNamed: "Inner", arguments: ["A": .host(Int.self), "A1": .host(String.self)])
    }

    @Test("a generic type with a nested type its binding derives")
    func derivedNestedType() async throws {
        try await expectParity(ofTypeNamed: "NestedHost", arguments: ["A": .host(Int.self)])
    }

    @Test("a nested generic type declaring a parameter of its own")
    func nestedGenericDeclaringItsOwnParameter() async throws {
        try await expectParity(ofTypeNamed: "Pair", arguments: ["A": .host(Int.self), "A1": .host(Bool.self)])
    }

    @Test("a private type")
    func privateType() async throws {
        try await expectParity(ofTypeNamed: "PrivateBox", arguments: ["A": .host(Int.self)])
    }

    @Test("a bound-generic argument")
    func boundGenericArgument() async throws {
        try await expectParity(ofTypeNamed: "PairBox", arguments: ["A": .bound(typeName: "ReferenceBox", arguments: ["A": Int.self]), "B": .host(Int8.self)])
    }
}

import Foundation
import Testing
import MachOKit
import MachOFoundation
@_spi(Internals) import Demangling
import MachOSwiftSection
@_spi(Support) @testable import SwiftDeclaration
@_spi(Support) @testable import SwiftIndexing
@testable import SwiftInspection
@testable import MachOTestingSupport

/// `TypeDefinition.attachedMacros` recognizes a class `@Observable` expanded
/// from its field records when the definition is built, before anything is
/// indexed, and `ExtensionDefinition.generatingMacro` marks the conformance
/// the macro generated (evolution proposal `observable-macro-folding`). The
/// field records survive stripping, so every variant answers the same.
@Suite(.serialized)
struct ObservableMacroRecognitionTests {
    private struct Recognition {
        var attachedMacrosByTypeName: [String: Set<SwiftAttachedMacro>] = [:]
        /// The `Observation.Observable` conformance extensions, by the name
        /// of the type they extend.
        var generatingMacrosByConformingTypeName: [String: SwiftAttachedMacro?] = [:]
    }

    private func recognition(in machO: some MachOSwiftSectionRepresentableWithCache) async throws -> Recognition {
        let indexer = SwiftDeclarationIndexer(in: machO)
        try await indexer.prepare()
        var recognition = Recognition()
        for definition in indexer.allTypeDefinitions.values {
            // Nothing is indexed: the macros are known as soon as the model is.
            #expect(!definition.isIndexed)
            recognition.attachedMacrosByTypeName[definition.typeName.declaredNameForTesting] = definition.attachedMacros
        }
        for (extensionName, extensionDefinitions) in indexer.conformanceExtensionDefinitions {
            for extensionDefinition in extensionDefinitions {
                guard let protocolName = extensionDefinition.conformingProtocolName,
                      ObservableMacroRecognition.isObservableProtocol(protocolName.node.materialize())
                else { continue }
                recognition.generatingMacrosByConformingTypeName[extensionName.declaredNameForTesting] = extensionDefinition.generatingMacro
            }
        }
        return recognition
    }

    private func expectFixtureRecognition(_ recognition: Recognition, sourceLocation: SourceLocation = #_sourceLocation) {
        for typeName in ObservableMacroFixture.observableClassNames {
            #expect(recognition.attachedMacrosByTypeName[typeName] == [.observable], "\(typeName)", sourceLocation: sourceLocation)
        }
        for typeName in ObservableMacroFixture.lookalikeTypeNames {
            #expect(recognition.attachedMacrosByTypeName[typeName] == [], "\(typeName)", sourceLocation: sourceLocation)
        }
        // The macro's conformances are marked; the hand-written one is not.
        // The subclass inherits its conformance and has no record of its own.
        #expect(
            recognition.generatingMacrosByConformingTypeName == [
                "FinalModel": .observable,
                "OpenModel": .observable,
                "InternalModel": .observable,
                "GenericModel": .observable,
                "WrapperModel": .observable,
                "ManualObservable": nil,
            ],
            sourceLocation: sourceLocation
        )
    }

    @Test(arguments: ObservableMacroFixture.Variant.allCases)
    func everyVariantRecognizesTheSameClasses(variant: ObservableMacroFixture.Variant) async throws {
        expectFixtureRecognition(try await recognition(in: try ObservableMacroFixture.machOFile(variant)))
    }

    @Test func theInProcessReaderRecognizesTheSameClasses() async throws {
        expectFixtureRecognition(try await recognition(in: try ObservableMacroFixture.loadedImage()))
    }

    @Test func theRegistrarTypeIsReadWithOrWithoutItsTypeNode() {
        let registrar = Node.createTransient(kind: .structure, children: [
            Node.createTransient(kind: .module, text: "Observation"),
            Node.createTransient(kind: .identifier, text: "ObservationRegistrar"),
        ])
        #expect(ObservableMacroRecognition.isObservationRegistrarType(registrar))
        #expect(ObservableMacroRecognition.isObservationRegistrarType(Node.createTransient(kind: .type, child: registrar)))
        let lookalike = Node.createTransient(kind: .structure, children: [
            Node.createTransient(kind: .module, text: "ComposableArchitecture"),
            Node.createTransient(kind: .identifier, text: "ObservationRegistrar"),
        ])
        #expect(!ObservableMacroRecognition.isObservationRegistrarType(lookalike))
    }

    @Test func theConformanceIsToTheObservationModulesProtocol() {
        let observable = Node.createTransient(kind: .protocol, children: [
            Node.createTransient(kind: .module, text: "Observation"),
            Node.createTransient(kind: .identifier, text: "Observable"),
        ])
        #expect(ObservableMacroRecognition.isObservableProtocol(Node.createTransient(kind: .type, child: observable)))
        let structure = Node.createTransient(kind: .structure, children: [
            Node.createTransient(kind: .module, text: "Observation"),
            Node.createTransient(kind: .identifier, text: "Observable"),
        ])
        #expect(!ObservableMacroRecognition.isObservableProtocol(structure))
    }
}

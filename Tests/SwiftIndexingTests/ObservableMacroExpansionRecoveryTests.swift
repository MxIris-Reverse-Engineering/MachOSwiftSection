import Foundation
import Testing
import MachOKit
import MachOFoundation
@_spi(Internals) import Demangling
import MachOSwiftSection
@_spi(Support) @testable import SwiftDeclaration
@_spi(Support) @testable import SwiftIndexing
@testable import MachOTestingSupport

/// `TypeDefinition.observableMacroExpansion` sorts an `@Observable` class's
/// stored `var`s into the storage of the properties the macro tracks and the
/// ones it left alone, and picks out the methods it generated (evolution
/// proposal `observable-macro-folding`). What tells a tracked property's
/// storage `_x` from a stored property the source named `_x` depends on what
/// the symbol table kept, so each variant is pinned with the evidence it
/// gives.
@Suite(.serialized)
struct ObservableMacroExpansionRecoveryTests {
    private typealias TrackedProperty = ObservableMacroExpansion.TrackedProperty

    private func expansion(of typeName: String, in machO: some MachOSwiftSectionRepresentableWithCache) async throws -> ObservableMacroExpansion {
        let indexer = SwiftDeclarationIndexer(in: machO)
        try await indexer.prepare()
        let definition = try #require(indexer.allTypeDefinitions.values.first { $0.typeName.declaredNameForTesting == typeName }, "no type named \(typeName)")
        try definition.index(in: machO)
        return try #require(definition.observableMacroExpansion, "\(typeName) has no expansion")
    }

    private func trackedProperties(of typeName: String, in machO: some MachOSwiftSectionRepresentableWithCache) async throws -> [TrackedProperty] {
        try await expansion(of: typeName, in: machO).trackedProperties
    }

    // MARK: - Images that keep their local symbols

    @Test(arguments: [ObservableMacroFixture.Variant.debug, .release])
    func everyTrackedPropertyIsToldByItsInitAccessor(variant: ObservableMacroFixture.Variant) async throws {
        let machO = try ObservableMacroFixture.machOFile(variant)
        let finalModel = try await expansion(of: "FinalModel", in: machO)
        #expect(finalModel.trackedProperties == [
            TrackedProperty(name: "name", backingFieldName: "_name", origin: .declaredMember, evidence: .initAccessor),
            TrackedProperty(name: "count", backingFieldName: "_count", origin: .declaredMember, evidence: .initAccessor),
            TrackedProperty(name: "uninitialized", backingFieldName: "_uninitialized", origin: .declaredMember, evidence: .initAccessor),
        ])
        // `_cache` has no init accessor named `cache`: it is a stored
        // property of its own. A `let` is never listed.
        #expect(finalModel.ignoredStoredPropertyNames == ["ignored", "_cache", "lazyValue"])
        #expect(Set(finalModel.generatedFunctions.map(\.name)).isSuperset(of: ["access", "withMutation"]))

        let internalModel = try await expansion(of: "InternalModel", in: machO)
        #expect(internalModel.trackedProperties.map(\.name) == ["value", "optionalText", "delegate"])
        #expect(internalModel.trackedProperties.allSatisfy { $0.origin == .declaredMember && $0.evidence == .initAccessor })
        #expect(internalModel.ignoredStoredPropertyNames == ["_underscored"])

        #expect(try await trackedProperties(of: "OpenModel", in: machO).map(\.name) == ["title", "items"])
        #expect(try await trackedProperties(of: "SubModel", in: machO).map(\.name) == ["extra"])
        #expect(try await trackedProperties(of: "GenericModel", in: machO).map(\.name) == ["elements"])

        // A wrapper's storage belongs to the wrapped property, which the
        // source declared `@ObservationIgnored`.
        let wrapperModel = try await expansion(of: "WrapperModel", in: machO)
        #expect(wrapperModel.trackedProperties.map(\.name) == ["tracked"])
        #expect(wrapperModel.ignoredStoredPropertyNames == ["_clamped"])
    }

    @Test func theInProcessReaderRecoversTheSameExpansion() async throws {
        let image = try ObservableMacroFixture.loadedImage()
        let finalModel = try await expansion(of: "FinalModel", in: image)
        #expect(finalModel.trackedProperties.map(\.name) == ["name", "count", "uninitialized"])
        #expect(finalModel.trackedProperties.allSatisfy { $0.evidence == .initAccessor })
        #expect(finalModel.ignoredStoredPropertyNames == ["ignored", "_cache", "lazyValue"])
        let internalModel = try await expansion(of: "InternalModel", in: image)
        #expect(internalModel.trackedProperties.map(\.name) == ["value", "optionalText", "delegate"])
        #expect(internalModel.ignoredStoredPropertyNames == ["_underscored"])
    }

    // MARK: - A dead-stripped image

    /// SwiftUI's shape: the image keeps its local symbols, but linking with
    /// `-dead_strip` dropped every function nothing references — most init
    /// accessors, and every accessor of a final class's internal properties.
    /// The absence of an init accessor must not turn a tracked property's
    /// storage into a stored property of its own; it did, and SwiftUI's
    /// `Immersion` printed `@ObservationIgnored var _amount` beside the
    /// computed `amount`.
    @Test func aDeadStrippedImageIsReadFromWhatItKeeps() async throws {
        let machO = try ObservableMacroFixture.machOFile(.releaseDeadStripped)
        let internalModel = try await expansion(of: "InternalModel", in: machO)
        #expect(internalModel.trackedProperties == [
            // The vtable keeps the computed properties' accessors.
            TrackedProperty(name: "value", backingFieldName: "_value", origin: .declaredMember, evidence: .accessors),
            TrackedProperty(name: "optionalText", backingFieldName: "_optionalText", origin: .declaredMember, evidence: .accessors),
            TrackedProperty(name: "delegate", backingFieldName: "_delegate", origin: .declaredMember, evidence: .accessors),
        ])
        // `_underscored` keeps accessors of its own while nothing names
        // `underscored`: a stored property of its own.
        #expect(internalModel.ignoredStoredPropertyNames == ["_underscored"])

        let finalModel = try await expansion(of: "FinalModel", in: machO)
        #expect(finalModel.trackedProperties == [
            // `name`'s init accessor is one the strip kept.
            TrackedProperty(name: "name", backingFieldName: "_name", origin: .declaredMember, evidence: .initAccessor),
            // The rest of the final class's accessors are gone.
            TrackedProperty(name: "count", backingFieldName: "_count", origin: .synthesized, evidence: .initialValueExpression),
            TrackedProperty(name: "uninitialized", backingFieldName: "_uninitialized", origin: .synthesized, evidence: .backingFieldName),
        ])
        #expect(finalModel.ignoredStoredPropertyNames == ["ignored", "_cache", "lazyValue"])
    }

    // MARK: - An image stripped of its local symbols

    @Test func aStrippedPublicClassIsReadFromItsExports() async throws {
        let machO = try ObservableMacroFixture.machOFile(.releaseStripped)
        let finalModel = try await expansion(of: "FinalModel", in: machO)
        #expect(finalModel.trackedProperties == [
            // Public: the computed property's setter is exported.
            TrackedProperty(name: "name", backingFieldName: "_name", origin: .declaredMember, evidence: .accessors),
            // Internal, with an initial value: the exported initial-value
            // expression is `count`'s, not `_count`'s.
            TrackedProperty(name: "count", backingFieldName: "_count", origin: .synthesized, evidence: .initialValueExpression),
            // Internal, without one: only the storage's name says it.
            TrackedProperty(name: "uninitialized", backingFieldName: "_uninitialized", origin: .synthesized, evidence: .backingFieldName),
        ])
        // `_cache` carries its own exported initial-value expression.
        #expect(finalModel.ignoredStoredPropertyNames == ["ignored", "_cache", "lazyValue"])

        // An open class exports its init accessors.
        let openModel = try await trackedProperties(of: "OpenModel", in: machO)
        #expect(openModel.map(\.name) == ["title", "items"])
        #expect(openModel.allSatisfy { $0.evidence == .initAccessor })
    }

    /// The limit the evidence leaves: an internal class whose symbols are all
    /// stripped keeps only its field records, so an `@ObservationIgnored`
    /// property named `_underscored` reads as the storage of a tracked
    /// `underscored`. It is recorded with the evidence that says so.
    @Test func aStrippedInternalClassIsReadFromItsStorageNames() async throws {
        let machO = try ObservableMacroFixture.machOFile(.releaseStripped)
        let internalModel = try await trackedProperties(of: "InternalModel", in: machO)
        #expect(internalModel == [
            TrackedProperty(name: "value", backingFieldName: "_value", origin: .synthesized, evidence: .backingFieldName),
            TrackedProperty(name: "optionalText", backingFieldName: "_optionalText", origin: .synthesized, evidence: .backingFieldName),
            TrackedProperty(name: "delegate", backingFieldName: "_delegate", origin: .synthesized, evidence: .backingFieldName),
            TrackedProperty(name: "underscored", backingFieldName: "_underscored", origin: .synthesized, evidence: .backingFieldName),
        ])
    }

    // MARK: - The rules on hand-built inputs

    private static let intTypeNode = Node.createTransient(kind: .type, child: Node.createTransient(kind: .structure, children: [
        Node.createTransient(kind: .module, text: "Swift"),
        Node.createTransient(kind: .identifier, text: "Int"),
    ]))

    private static let stringTypeNode = Node.createTransient(kind: .type, child: Node.createTransient(kind: .structure, children: [
        Node.createTransient(kind: .module, text: "Swift"),
        Node.createTransient(kind: .identifier, text: "String"),
    ]))

    @Test func onlyAnUnderscoredNameWithoutADollarSignCanBeStorage() {
        #expect(ObservableMacroExpansionRecovery.trackedPropertyName(forBackingFieldName: "_value") == "value")
        #expect(ObservableMacroExpansionRecovery.trackedPropertyName(forBackingFieldName: "__value") == "_value")
        #expect(ObservableMacroExpansionRecovery.trackedPropertyName(forBackingFieldName: "value") == nil)
        #expect(ObservableMacroExpansionRecovery.trackedPropertyName(forBackingFieldName: "_") == nil)
        #expect(ObservableMacroExpansionRecovery.trackedPropertyName(forBackingFieldName: "_$observationRegistrar") == nil)
    }

    @Test func aWeakStorageStoresTheTypeItsPropertyDeclares() {
        let weakTypeNode = Node.createTransient(kind: .type, child: Node.createTransient(kind: .weak, child: Self.intTypeNode))
        #expect(ObservableMacroExpansionRecovery.referencedTypeNode(ofStoredType: weakTypeNode) == Self.intTypeNode)
        #expect(ObservableMacroExpansionRecovery.referencedTypeNode(ofStoredType: Self.intTypeNode) == Self.intTypeNode)
    }

    @Test func theGeneratedMethodsAreToldByNameAndLabels() {
        #expect(ObservableMacroExpansionRecovery.isGeneratedFunction(name: "access", argumentLabels: ["keyPath"]))
        #expect(ObservableMacroExpansionRecovery.isGeneratedFunction(name: "withMutation", argumentLabels: ["keyPath", "_"]))
        #expect(ObservableMacroExpansionRecovery.isGeneratedFunction(name: "shouldNotifyObservers", argumentLabels: []))
        #expect(!ObservableMacroExpansionRecovery.isGeneratedFunction(name: "access", argumentLabels: []))
        #expect(!ObservableMacroExpansionRecovery.isGeneratedFunction(name: "withMutation", argumentLabels: ["keyPath"]))
        #expect(!ObservableMacroExpansionRecovery.isGeneratedFunction(name: "reload", argumentLabels: []))
    }

    @Test func anInitAccessorOrTheComputedPropertysSetterTellsATrackedProperty() {
        let recovered = ObservableMacroExpansionRecovery.recover(
            storedProperties: [
                .init(name: "_initialized", typeNode: Self.intTypeNode, isVariable: true),
                .init(name: "_settable", typeNode: Self.intTypeNode, isVariable: true, hasAccessors: true),
                .init(name: "_constant", typeNode: Self.intTypeNode, isVariable: false),
                .init(name: "_$observationRegistrar", typeNode: Self.intTypeNode, isVariable: false),
            ],
            // No init accessor for `settable`: dead-stripped, as in SwiftUI.
            memberVariables: [.init(name: "settable", declaredTypeNode: Self.intTypeNode, hasSetterOrModify: true)],
            claimedBackingFieldNames: [],
            evidence: .init(initAccessorNames: ["initialized"])
        )
        #expect(recovered.trackedProperties == [
            TrackedProperty(name: "initialized", backingFieldName: "_initialized", origin: .synthesized, evidence: .initAccessor),
            TrackedProperty(name: "settable", backingFieldName: "_settable", origin: .declaredMember, evidence: .accessors),
        ])
        #expect(recovered.ignoredStoredPropertyNames.isEmpty)
    }

    @Test func aMemberOfAnotherTypeIsNotWhatTheStorageHolds() {
        let recovered = ObservableMacroExpansionRecovery.recover(
            storedProperties: [.init(name: "_label", typeNode: Self.intTypeNode, isVariable: true)],
            memberVariables: [.init(name: "label", declaredTypeNode: Self.stringTypeNode, hasSetterOrModify: true)],
            claimedBackingFieldNames: [],
            evidence: .init(initAccessorNames: ["label"])
        )
        #expect(recovered.trackedProperties.isEmpty)
        #expect(recovered.ignoredStoredPropertyNames == ["_label"])
    }

    @Test func aWrappersStorageIsLeftToTheWrappedProperty() {
        let recovered = ObservableMacroExpansionRecovery.recover(
            storedProperties: [.init(name: "_clamped", typeNode: Self.intTypeNode, isVariable: true)],
            memberVariables: [],
            claimedBackingFieldNames: ["_clamped"],
            evidence: .init(initAccessorNames: ["clamped"])
        )
        #expect(recovered.trackedProperties.isEmpty)
        #expect(recovered.ignoredStoredPropertyNames == ["_clamped"])
    }

    @Test func whatTheStorageHasOfItsOwnRulesItOut() {
        var askedForInitialValueExpressions = 0
        let recovered = ObservableMacroExpansionRecovery.recover(
            storedProperties: [
                .init(name: "_initialized", typeNode: Self.intTypeNode, isVariable: true),
                .init(name: "_ownInitialValue", typeNode: Self.intTypeNode, isVariable: true),
                .init(name: "_ownAccessors", typeNode: Self.intTypeNode, isVariable: true, hasAccessors: true),
                .init(name: "_unnamed", typeNode: Self.intTypeNode, isVariable: true),
            ],
            memberVariables: [],
            claimedBackingFieldNames: [],
            evidence: .init(initialValueExpressionNames: {
                askedForInitialValueExpressions += 1
                return ["initialized", "_ownInitialValue"]
            })
        )
        #expect(recovered.trackedProperties == [
            TrackedProperty(name: "initialized", backingFieldName: "_initialized", origin: .synthesized, evidence: .initialValueExpression),
            TrackedProperty(name: "unnamed", backingFieldName: "_unnamed", origin: .synthesized, evidence: .backingFieldName),
        ])
        #expect(recovered.ignoredStoredPropertyNames == ["_ownInitialValue", "_ownAccessors"])
        // Gathered once, however many storages ask.
        #expect(askedForInitialValueExpressions == 1)
    }

    @Test func theInitialValueExpressionsAreNotGatheredWhenTheAccessorsDecide() {
        var askedForInitialValueExpressions = 0
        _ = ObservableMacroExpansionRecovery.recover(
            storedProperties: [.init(name: "_value", typeNode: Self.intTypeNode, isVariable: true)],
            memberVariables: [.init(name: "value", declaredTypeNode: Self.intTypeNode, hasSetterOrModify: true)],
            claimedBackingFieldNames: [],
            evidence: .init(initialValueExpressionNames: {
                askedForInitialValueExpressions += 1
                return []
            })
        )
        #expect(askedForInitialValueExpressions == 0)
    }
}

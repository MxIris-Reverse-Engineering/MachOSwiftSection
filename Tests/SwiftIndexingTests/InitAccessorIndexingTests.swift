import Foundation
import Testing
import MachOKit
import MachOFoundation
@_spi(Internals) import Demangling
import MachOSwiftSection
@_spi(Support) @testable import SwiftDeclaration
@_spi(Support) @testable import SwiftIndexing
@testable import MachOTestingSupport

/// A SE-0400 init accessor is one of its property's accessors (evolution
/// proposal `init-accessor-recovery`): the index files its symbol with the
/// property's other accessors, after them, without making the property a
/// stored one or moving it in the member order. Which init accessors an image
/// keeps depends on the build, so each variant is pinned with what it keeps.
@Suite(.serialized)
struct InitAccessorIndexingTests {
    private typealias Property = InitAccessorFixture.Property

    private struct Indexed {
        var variablesByProperty: [Property: VariableDefinition] = [:]
        var fieldsByProperty: [Property: FieldDefinition] = [:]
        var orderedMembersByTypeName: [String: [OrderedMember]] = [:]
    }

    private func indexed(in machO: some MachOSwiftSectionRepresentableWithCache) async throws -> Indexed {
        let indexer = SwiftDeclarationIndexer(in: machO)
        try await indexer.prepare()
        var indexed = Indexed()
        for definition in indexer.allTypeDefinitions.values {
            try definition.index(in: machO)
            let typeName = definition.typeName.declaredNameForTesting
            for variable in definition.variables {
                indexed.variablesByProperty[Property(typeName, variable.name)] = variable
            }
            for field in definition.fields {
                indexed.fieldsByProperty[Property(typeName, field.name)] = field
            }
            indexed.orderedMembersByTypeName[typeName] = definition.orderedMembers
        }
        return indexed
    }

    private func expectEveryInitAccessorFiled(_ indexed: Indexed, sourceLocation: SourceLocation = #_sourceLocation) throws {
        for property in InitAccessorFixture.propertiesWithInitAccessors {
            let variable = try #require(indexed.variablesByProperty[property], "no variable \(property)", sourceLocation: sourceLocation)
            #expect(variable.hasInitAccessor, "\(property)", sourceLocation: sourceLocation)
            #expect(variable.accessors.filter { $0.kind == .initAccessor }.count == 1, "\(property)", sourceLocation: sourceLocation)
            // Still computed: an init accessor read as no accessor at all made
            // the property a stored one.
            #expect(!variable.isStored, "\(property)", sourceLocation: sourceLocation)
            // After the accessors that answer for the property.
            #expect(variable.accessors.last?.kind == .initAccessor, "\(property)", sourceLocation: sourceLocation)
            #expect(variable.accessors.first?.kind != .initAccessor, "\(property)", sourceLocation: sourceLocation)
            // The declaration still prints from the getter.
            #expect(variable.node.materialize().first(of: .getter) != nil, "\(property)", sourceLocation: sourceLocation)
            #expect(variable.node.materialize().first(of: .initAccessor) == nil, "\(property)", sourceLocation: sourceLocation)
        }
    }

    // MARK: - Images that keep their local symbols

    @Test(arguments: [InitAccessorFixture.Variant.debug, .release])
    func everyInitAccessorIsOneOfItsPropertysAccessors(variant: InitAccessorFixture.Variant) async throws {
        try expectEveryInitAccessorFiled(try await indexed(in: try await InitAccessorFixture.machOFile(variant)))
    }

    @Test func theInProcessReaderFilesTheSameInitAccessors() async throws {
        try expectEveryInitAccessorFiled(try await indexed(in: try await InitAccessorFixture.loadedImage()))
    }

    // MARK: - Stripped images

    /// SwiftUI's shape, and an OS framework's: an init accessor the image
    /// does not export is gone — the initializers inlined it, so nothing
    /// references it — and the property is left with the accessors it
    /// exports.
    @Test(arguments: [InitAccessorFixture.Variant.releaseDeadStripped, .releaseStripped])
    func onlyTheExportedInitAccessorsSurvive(variant: InitAccessorFixture.Variant) async throws {
        let indexed = try await indexed(in: try await InitAccessorFixture.machOFile(variant))
        for property in InitAccessorFixture.propertiesWithInitAccessors {
            // Every property here is public: its getter is exported.
            let variable = try #require(indexed.variablesByProperty[property], "no variable \(property)")
            #expect(variable.hasInitAccessor == InitAccessorFixture.propertiesWithExportedInitAccessors.contains(property), "\(property)")
            #expect(!variable.isStored, "\(property)")
        }
    }

    // MARK: - A stored property with an init accessor's symbol

    /// SwiftUICore's `_GeometryActionModifier.value`: a stored property, with
    /// a function under its init accessor's name. It stays stored, the symbol
    /// joins the field's accessors, and no computed property appears.
    @Test(arguments: InitAccessorFixture.Variant.allCases)
    func aStoredPropertyKeepsTheSymbolOnItsField(variant: InitAccessorFixture.Variant) async throws {
        let indexed = try await indexed(in: try await InitAccessorFixture.machOFile(variant))
        let property = InitAccessorFixture.storedPropertyWithInitAccessorSymbol
        #expect(indexed.variablesByProperty[property] == nil)
        let field = try #require(indexed.fieldsByProperty[property], "no field \(property)")
        #expect(field.hasInitAccessor)
    }

    // MARK: - What an init accessor initializes

    /// No image records `@storageRestrictions`; the field named `_<name>`
    /// with the property's type is read as what it initializes. `Angle` and
    /// `Pair` initialize fields of other names, `Titled` only accesses one,
    /// and `PersistedLookalike._name` has another type: none of them tells.
    @Test(arguments: [InitAccessorFixture.Variant.debug, .release])
    func theInitializedFieldIsInferredFromItsNameAndType(variant: InitAccessorFixture.Variant) async throws {
        let indexed = try await indexed(in: try await InitAccessorFixture.machOFile(variant))
        for property in InitAccessorFixture.propertiesWithInitAccessors {
            let variable = try #require(indexed.variablesByProperty[property], "no variable \(property)")
            #expect(variable.initializedFieldNames == InitAccessorFixture.inferredInitializedFieldNames[property], "\(property)")
        }
    }

    @Test func theInProcessReaderInfersTheSameFields() async throws {
        let indexed = try await indexed(in: try await InitAccessorFixture.loadedImage())
        for property in InitAccessorFixture.propertiesWithInitAccessors {
            let variable = try #require(indexed.variablesByProperty[property], "no variable \(property)")
            #expect(variable.initializedFieldNames == InitAccessorFixture.inferredInitializedFieldNames[property], "\(property)")
        }
    }

    /// Only a property whose init accessor the image kept is inferred about.
    @Test(arguments: [InitAccessorFixture.Variant.releaseDeadStripped, .releaseStripped])
    func aStrippedImageInfersOnlyWhatItKeeps(variant: InitAccessorFixture.Variant) async throws {
        let indexed = try await indexed(in: try await InitAccessorFixture.machOFile(variant))
        for property in InitAccessorFixture.propertiesWithInitAccessors {
            let variable = try #require(indexed.variablesByProperty[property], "no variable \(property)")
            let expected = InitAccessorFixture.propertiesWithExportedInitAccessors.contains(property) ? InitAccessorFixture.inferredInitializedFieldNames[property] : nil
            #expect(variable.initializedFieldNames == expected, "\(property)")
        }
        #expect(indexed.variablesByProperty[Property("FrozenBox", "value")]?.initializedFieldNames == ["_value"])
    }

    // MARK: - The member order

    /// Whether the image kept an init accessor depends on the build, so it
    /// must not decide where its property sorts. The release build places
    /// `Model.name`'s init accessor before its getter, which the order would
    /// otherwise follow.
    @Test(arguments: InitAccessorFixture.Variant.allCases)
    func theInitAccessorTakesNoPartInTheMemberOrder(variant: InitAccessorFixture.Variant) async throws {
        let indexed = try await indexed(in: try await InitAccessorFixture.machOFile(variant))
        var hasInitAccessorBeforeTheOthers = false
        for (typeName, members) in indexed.orderedMembersByTypeName {
            for member in members {
                guard case .variable(let variable) = member, variable.hasInitAccessor else { continue }
                let initAccessorOffsets = variable.accessors.filter { $0.kind == .initAccessor }.map(\.symbol.offset)
                let otherOffsets = variable.accessors.filter { $0.kind != .initAccessor }.map(\.symbol.offset)
                #expect(member.minSymbolOffset == otherOffsets.min(), "\(typeName).\(variable.name)")
                if let initAccessorOffset = initAccessorOffsets.min(), let otherOffset = otherOffsets.min(), initAccessorOffset < otherOffset {
                    hasInitAccessorBeforeTheOthers = true
                }
            }
        }
        if variant == .release {
            #expect(hasInitAccessorBeforeTheOthers, "the release build no longer places an init accessor before its getter; the order test checks nothing there")
        }
    }
}

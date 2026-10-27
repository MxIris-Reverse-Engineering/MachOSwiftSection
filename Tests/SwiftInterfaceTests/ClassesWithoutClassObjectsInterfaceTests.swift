import Foundation
import Testing
import MachOKit
import MachOFoundation
import MachOSwiftSection
import SwiftDeclaration
import SwiftDeclarationRendering
import SwiftInterface
import SwiftThunkAnalysis
@_spi(Internals) import SwiftInspection
@testable import MachOTestingSupport

/// Swift classes without a class object on the interface path (evolution
/// proposal `objc-classes-without-class-objects`): a generic class, or one
/// with generic ancestry, has its ObjC method table in Swift metadata only,
/// and the ObjC member recovery — the `override` of an ObjC-inherited
/// member, which Swift metadata does not record — used to find none.
///
/// Holds `ExclusiveImageAccess` because the indexer registers an ancestor
/// resolver per image for the file leg.
@Suite(.serialized, ExclusiveImageAccess(ClassesWithoutClassObjectsFixture.moduleName))
struct ClassesWithoutClassObjectsInterfaceTests {
    private static let moduleName = ClassesWithoutClassObjectsFixture.moduleName

    private func interface(of variant: ClassesWithoutClassObjectsFixture.Variant) async throws -> String {
        var configuration = SwiftInterfaceBuilderConfiguration()
        configuration.indexConfiguration.dependencySearchPaths = try ClassesWithoutClassObjectsFixture.dependencySearchPaths()
        let builder = try SwiftInterfaceBuilder(configuration: configuration, eventHandlers: [], in: try ClassesWithoutClassObjectsFixture.machOFile(variant))
        try await builder.prepare()
        return try await builder.printRoot().string
    }

    /// The block whose header line STARTS with `prefix`, through its closing
    /// brace at the same indentation.
    private func block(startingWith prefix: String, in interface: String) -> String? {
        let lines = interface.split(separator: "\n", omittingEmptySubsequences: false)
        guard let start = lines.firstIndex(where: { $0.hasPrefix(prefix) }) else { return nil }
        let indentation = lines[start].prefix { $0 == " " }
        guard let end = lines[start...].firstIndex(where: { $0 == "\(indentation)}" }) else { return nil }
        return lines[start...end].joined(separator: "\n")
    }

    /// The generic class's method table sits in its metadata pattern:
    /// `description` overrides NSObject's, `poke` is its own.
    @Test func genericClassOverridesAreMarked() async throws {
        let interface = try await interface(of: .full)
        let widget = try #require(block(startingWith: "class GenericWidget<", in: interface), "\(interface)")
        #expect(widget.contains("@objc override var description: Swift.String"), "\(widget)")
        #expect(widget.contains("@objc func poke()"), "\(widget)")
        #expect(!widget.contains("override func poke()"), "\(widget)")
    }

    /// Generic ancestry: the chain runs through the generic superclass's
    /// pattern on to NSObject.
    @Test func classWithGenericAncestryOverridesAreMarked() async throws {
        let interface = try await interface(of: .full)
        let subclass = try #require(block(startingWith: "class ConcreteSubclass:", in: interface), "\(interface)")
        #expect(subclass.contains("@objc override var description: Swift.String"), "\(subclass)")
        #expect(subclass.contains("@objc func concretePoke()"), "\(subclass)")
        #expect(!subclass.contains("override func concretePoke()"), "\(subclass)")
    }

    /// With the `To` thunks stripped, as in every OS framework, the method
    /// table is the only `@objc` evidence.
    @Test func strippedGenericClassMembersJoinTheirObjCMethodTable() async throws {
        let interface = try await interface(of: .strippedLocals)
        let widget = try #require(block(startingWith: "class GenericWidget<", in: interface), "\(interface)")
        #expect(widget.contains("@objc override var description: Swift.String"), "\(widget)")
        #expect(widget.contains("@objc func poke()"), "\(widget)")
        #expect(!widget.contains("final"), "\(widget)")
        let subclass = try #require(block(startingWith: "class ConcreteSubclass:", in: interface), "\(interface)")
        #expect(subclass.contains("@objc override var description: Swift.String"), "\(subclass)")
        #expect(subclass.contains("@objc func concretePoke()"), "\(subclass)")
    }

    /// The table itself, asked by the Swift qualified name the way every
    /// consumer asks: a generic class answers under its name with its
    /// generic parameters, the one its template's null name leaves to us.
    @Test func memberTableOfAGenericClassIsFoundByItsQualifiedName() throws {
        let machOFile = try ClassesWithoutClassObjectsFixture.machOFile(.full)
        let table = try #require(ObjCMembers.table(forSwiftClassQualifiedName: "\(Self.moduleName).GenericWidget", in: machOFile))
        #expect(table.hierarchy.className == "\(Self.moduleName).GenericWidget<A>")
    }
}

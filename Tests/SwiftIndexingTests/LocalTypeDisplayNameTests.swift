import Foundation
import Testing
import MachOKit
import MachOSwiftSection
@testable import MachOTestingSupport
import SwiftDeclaration
@_spi(Support) import SwiftIndexing
import SwiftInspection

/// The name a reader is shown of a type declared in a function or closure
/// body, or of a type nested in one (evolution proposal
/// `private-declarations`): no modules, no parameter or result types, the
/// ordinal kept; a position-based one keeps its `$` address.
@Suite(.serialized, ExclusiveImageAccess(LocalTypeFixture.exclusiveAccessName))
struct LocalTypeDisplayNameTests {
    /// Every type of `variant` the fixture declares in a body, with the name a
    /// reader is shown of it, and every other type's.
    private static func displayNames(of variant: LocalTypeFixture.Variant) async throws -> (inBodies: [String], elsewhere: [String?]) {
        let machOFile = try LocalTypeFixture.machOFile(variant)
        let indexer = SwiftDeclarationIndexer(configuration: .init(), eventHandlers: [], in: machOFile)
        try await indexer.prepare()
        var inBodies: [String] = []
        var elsewhere: [String?] = []
        for (typeName, typeDefinition) in indexer.allTypeDefinitions {
            if try LocalTypeFixture.isDeclaredInABody(typeDefinition.typeContextDescriptorWrapper.asContextDescriptorWrapper, in: machOFile.context) {
                inBodies.append(try #require(typeName.localTypeDisplayName, "\(typeName.name)"))
            } else {
                elsewhere.append(typeName.localTypeDisplayName)
            }
        }
        return (inBodies, elsewhere)
    }

    @Test func compilerSpelledNamesLeaveModulesAndSignaturesOut() async throws {
        let (inBodies, elsewhere) = try await Self.displayNames(of: .unstripped)

        #expect(inBodies.sorted() == [
            "Box #1 in Holder.box()",
            "CodingKeys in Payload #1 in Holder.payload()",
            "Counter in WrappingGenerator #1 in Holder.wrapping()",
            "Element in Generator #1 in Holder.nested()",
            "Generator #1 in Holder.nested()",
            "Hidden #1 in Holder.hiddenValues()",
            "InClosure #1 in closure #1 in Holder.valuesFromClosure()",
            "IndexWrappingVisitor in WrappingGenerator #1 in Holder.wrapping()",
            "Key #1 in Holder.keyFromGetter.getter",
            "Key #1 in static Holder.keyFromStaticMethod()",
            "Lookup #1 in Holder.lookup(named:at:)",
            "Mode #1 in Holder.mode(_:)",
            "Payload #1 in Holder.payload()",
            "TopLevel #1 in localTypeFixtureTopLevel()",
            "Twin #1 in Holder.twins(_:)",
            "Twin #2 in Holder.twins(_:)",
            "Visitor #1 in Holder.countValues()",
            "Visitor #1 in Holder.sumValues()",
            "Wrapper #1 in String.localTypeFixtureWrapped()",
            "WrappingGenerator #1 in Holder.wrapping()",
        ])
        #expect(!elsewhere.isEmpty)
        #expect(elsewhere.allSatisfy { $0 == nil }, "\(elsewhere)")
    }

    /// With every name source stripped, a local type is named by the address
    /// of its anonymous context: the address stays, so `Holder`'s two
    /// `Visitor`s stay apart, and no real discriminator is printed.
    @Test func positionBasedNamesKeepTheirAddress() async throws {
        let (inBodies, elsewhere) = try await Self.displayNames(of: .stripped)

        #expect(inBodies.count == 20)
        #expect(Set(inBodies).count == inBodies.count, "\(inBodies.sorted())")
        #expect(inBodies.allSatisfy { $0.contains(" in $") }, "\(inBodies.sorted())")
        #expect(!inBodies.contains { $0.contains(" in _") }, "\(inBodies.sorted())")
        #expect(inBodies.filter { $0.hasPrefix("Holder.(Visitor in $") && $0.hasSuffix(")") }.count == 2, "\(inBodies.sorted())")
        #expect(inBodies.contains { $0.hasPrefix("Holder.(Generator in $") && $0.hasSuffix(").Element") }, "\(inBodies.sorted())")
        #expect(elsewhere.allSatisfy { $0 == nil }, "\(elsewhere)")
    }
}

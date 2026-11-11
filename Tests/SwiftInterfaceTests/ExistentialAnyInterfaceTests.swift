import Foundation
import Testing
import MachOKit
@_spi(Support) @testable import SwiftPrinting
@_spi(Support) @testable import SwiftInterface
@testable import MachOTestingSupport

/// `SwiftDeclarationPrintConfiguration.usesExistentialAny`, on by default,
/// spells existential types with the `any` keyword by the rules the compiler
/// applies when it writes a `.swiftinterface` (evolution proposal
/// `existential-any`): every existential but a lone `Any` or `AnyObject`
/// takes the keyword, an existential metatype always does
/// (`any Any.Type`), the metatype of the existential itself reads
/// `(any P).Type`, and an existential written with the keyword is
/// parenthesized wherever a suffix would bind to its last protocol.
///
/// The spelling with the option off — the interface before it — is pinned
/// beside each one, so a case also proves the option changes nothing but the
/// keyword and the parentheses it needs.
@Suite(.serialized)
struct ExistentialAnyInterfaceTests {
    private func printedInterface(usesExistentialAny: Bool, usesModuleSelectors: Bool = false) async throws -> String {
        let machOFile = try ExistentialAnyFixture.machOFile()
        var printConfiguration = SwiftDeclarationPrintConfiguration()
        printConfiguration.usesExistentialAny = usesExistentialAny
        printConfiguration.usesModuleSelectors = usesModuleSelectors
        let builder = try SwiftInterfaceBuilder(configuration: .init(printConfiguration: printConfiguration), eventHandlers: [], in: machOFile)
        builder.addExtraDataProvider(SwiftInterfaceBuilderOpaqueTypeProvider(machO: machOFile))
        try await builder.prepare()
        return try await builder.printRoot().string
    }

    struct SpellingCase: Sendable, CustomTestStringConvertible {
        let summary: String
        let bareSpelling: String
        let spellingWithKeyword: String

        var testDescription: String { summary }
    }

    static let spellingCases: [SpellingCase] = [
        SpellingCase(
            summary: "a protocol",
            bareSpelling: "var single: ExistentialAnyFixture.Marker\n",
            spellingWithKeyword: "var single: any ExistentialAnyFixture.Marker\n"
        ),
        SpellingCase(
            summary: "a composition writes one keyword",
            bareSpelling: "var composition: ExistentialAnyFixture.Marker & ExistentialAnyFixture.SecondMarker\n",
            spellingWithKeyword: "var composition: any ExistentialAnyFixture.Marker & ExistentialAnyFixture.SecondMarker\n"
        ),
        SpellingCase(
            summary: "a class-bound composition",
            bareSpelling: "var classBound: ExistentialAnyFixture.Marker & Swift.AnyObject\n",
            spellingWithKeyword: "var classBound: any ExistentialAnyFixture.Marker & Swift.AnyObject\n"
        ),
        SpellingCase(
            summary: "a superclass-bound composition",
            bareSpelling: "var superclassBound: ExistentialAnyFixture.Base & ExistentialAnyFixture.Marker\n",
            spellingWithKeyword: "var superclassBound: any ExistentialAnyFixture.Base & ExistentialAnyFixture.Marker\n"
        ),
        SpellingCase(
            summary: "Any stays bare",
            bareSpelling: "var anything: Any\n",
            spellingWithKeyword: "var anything: Any\n"
        ),
        SpellingCase(
            summary: "AnyObject stays bare",
            bareSpelling: "var anyObject: Swift.AnyObject\n",
            spellingWithKeyword: "var anyObject: Swift.AnyObject\n"
        ),
        SpellingCase(
            summary: "a protocol with associated types",
            bareSpelling: "var collection: Swift.Collection\n",
            spellingWithKeyword: "var collection: any Swift.Collection\n"
        ),
        SpellingCase(
            summary: "an optional existential is parenthesized",
            bareSpelling: "var optional: ExistentialAnyFixture.Marker?\n",
            spellingWithKeyword: "var optional: (any ExistentialAnyFixture.Marker)?\n"
        ),
        SpellingCase(
            summary: "an optional composition",
            bareSpelling: "var optionalComposition: (ExistentialAnyFixture.Marker & ExistentialAnyFixture.SecondMarker)?\n",
            spellingWithKeyword: "var optionalComposition: (any ExistentialAnyFixture.Marker & ExistentialAnyFixture.SecondMarker)?\n"
        ),
        SpellingCase(
            summary: "an optional error",
            bareSpelling: "var optionalError: Swift.Error?\n",
            spellingWithKeyword: "var optionalError: (any Swift.Error)?\n"
        ),
        SpellingCase(
            summary: "an optional of Any stays unparenthesized",
            bareSpelling: "var optionalAnything: Any?\n",
            spellingWithKeyword: "var optionalAnything: Any?\n"
        ),
        SpellingCase(
            summary: "an existential metatype",
            bareSpelling: "var existentialMetatype: ExistentialAnyFixture.Marker.Type\n",
            spellingWithKeyword: "var existentialMetatype: any ExistentialAnyFixture.Marker.Type\n"
        ),
        SpellingCase(
            summary: "an existential metatype of a composition parenthesizes it",
            bareSpelling: "var compositionMetatype: ExistentialAnyFixture.Marker & ExistentialAnyFixture.SecondMarker.Type\n",
            spellingWithKeyword: "var compositionMetatype: any (ExistentialAnyFixture.Marker & ExistentialAnyFixture.SecondMarker).Type\n"
        ),
        SpellingCase(
            summary: "the existential metatype of Any gets the keyword",
            bareSpelling: "var anythingMetatype: Any.Type\n",
            spellingWithKeyword: "var anythingMetatype: any Any.Type\n"
        ),
        SpellingCase(
            summary: "the existential metatype of AnyObject gets the keyword",
            bareSpelling: "var anyObjectMetatype: Swift.AnyObject.Type\n",
            spellingWithKeyword: "var anyObjectMetatype: any Swift.AnyObject.Type\n"
        ),
        SpellingCase(
            summary: "an optional existential metatype is parenthesized",
            bareSpelling: "var optionalExistentialMetatype: ExistentialAnyFixture.Marker.Type?\n",
            spellingWithKeyword: "var optionalExistentialMetatype: (any ExistentialAnyFixture.Marker.Type)?\n"
        ),
        SpellingCase(
            summary: "the metatype of an existential",
            bareSpelling: "var protocolMetatype: ExistentialAnyFixture.Marker.Protocol\n",
            spellingWithKeyword: "var protocolMetatype: (any ExistentialAnyFixture.Marker).Type\n"
        ),
        SpellingCase(
            summary: "a constrained existential keeps its one keyword",
            bareSpelling: "var constrained: any ExistentialAnyFixture.Boxed<Swift.Int>\n",
            spellingWithKeyword: "var constrained: any ExistentialAnyFixture.Boxed<Swift.Int>\n"
        ),
        SpellingCase(
            summary: "an optional constrained existential",
            bareSpelling: "var optionalConstrained: (any ExistentialAnyFixture.Boxed<Swift.String>)?\n",
            spellingWithKeyword: "var optionalConstrained: (any ExistentialAnyFixture.Boxed<Swift.String>)?\n"
        ),
        SpellingCase(
            summary: "the existential metatype of a constrained existential writes one keyword",
            bareSpelling: "var constrainedMetatype: any ExistentialAnyFixture.Boxed<Swift.Int>.Type\n",
            spellingWithKeyword: "var constrainedMetatype: any ExistentialAnyFixture.Boxed<Swift.Int>.Type\n"
        ),
        SpellingCase(
            summary: "an optional existential metatype of a constrained existential is parenthesized either way",
            bareSpelling: "var optionalConstrainedMetatype: (any ExistentialAnyFixture.Boxed<Swift.Int>.Type)?\n",
            spellingWithKeyword: "var optionalConstrainedMetatype: (any ExistentialAnyFixture.Boxed<Swift.Int>.Type)?\n"
        ),
        SpellingCase(
            summary: "an array of existentials",
            bareSpelling: "var existentialArray: [ExistentialAnyFixture.Marker]\n",
            spellingWithKeyword: "var existentialArray: [any ExistentialAnyFixture.Marker]\n"
        ),
        SpellingCase(
            summary: "a closure taking and returning existentials",
            bareSpelling: "var existentialFunction: (_: ExistentialAnyFixture.Marker) -> ExistentialAnyFixture.SecondMarker\n",
            spellingWithKeyword: "var existentialFunction: (_: any ExistentialAnyFixture.Marker) -> any ExistentialAnyFixture.SecondMarker\n"
        ),
        SpellingCase(
            summary: "a parameter and a variadic parameter",
            bareSpelling: "func accept(_: ExistentialAnyFixture.Marker, _: ExistentialAnyFixture.Marker...)\n",
            spellingWithKeyword: "func accept(_: any ExistentialAnyFixture.Marker, _: any ExistentialAnyFixture.Marker...)\n"
        ),
        SpellingCase(
            summary: "an inout parameter",
            bareSpelling: "func acceptInout(_: inout ExistentialAnyFixture.Marker)\n",
            spellingWithKeyword: "func acceptInout(_: inout any ExistentialAnyFixture.Marker)\n"
        ),
        SpellingCase(
            summary: "a constrained existential parameter",
            bareSpelling: "func acceptConstrained(_: any ExistentialAnyFixture.Boxed<Swift.Int>)\n",
            spellingWithKeyword: "func acceptConstrained(_: any ExistentialAnyFixture.Boxed<Swift.Int>)\n"
        ),
        SpellingCase(
            summary: "an existential argument of an opaque type's constraint",
            bareSpelling: "func opaqueSequence() -> some Swift.Sequence<ExistentialAnyFixture.Marker>\n",
            spellingWithKeyword: "func opaqueSequence() -> some Swift.Sequence<any ExistentialAnyFixture.Marker>\n"
        ),
    ]

    @Test(arguments: spellingCases)
    func interfaceSpellsExistentialsWithAny(_ spellingCase: SpellingCase) async throws {
        let bareInterface = try await printedInterface(usesExistentialAny: false)
        #expect(bareInterface.contains(spellingCase.bareSpelling), "\(bareInterface)")
        let interface = try await printedInterface(usesExistentialAny: true)
        #expect(interface.contains(spellingCase.spellingWithKeyword), "\(interface)")
    }

    @Test func keywordIsOnByDefault() {
        #expect(SwiftDeclarationPrintConfiguration().usesExistentialAny)
    }

    /// The existential metatype of a constrained existential is a metadata
    /// word plus one witness table, 16 bytes. The static layout engine used to
    /// look for the constrained existential inside the field's extended
    /// existential shape, so its metatype branch was never taken and the field
    /// was laid out as a value container, 40 bytes; the field now reaches it
    /// as an `existentialMetatype` like any other.
    @Test func constrainedExistentialMetatypeIsLaidOutAsAMetatype() async throws {
        let machOFile = try ExistentialAnyFixture.machOFile()
        var printConfiguration = SwiftDeclarationPrintConfiguration()
        printConfiguration.printTypeLayout = true
        let builder = try SwiftInterfaceBuilder(configuration: .init(printConfiguration: printConfiguration), eventHandlers: [], in: machOFile)
        try await builder.prepare()
        let interface = try await builder.printRoot().string
        let lines = interface.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        let fieldIndex = try #require(lines.firstIndex { $0.hasPrefix("var constrainedMetatype: ") }, "\(interface)")
        #expect(lines[fieldIndex - 1] == "// Type Layout: (size: 16, stride: 16, alignment: 8, extraInhabitantCount: 2147483647)", "\(interface)")
    }

    /// The keyword and module selectors are independent spellings: one name
    /// takes both, and so does an opaque type's constraint, which the opaque
    /// type provider spells.
    @Test func keywordCombinesWithModuleSelectors() async throws {
        let interface = try await printedInterface(usesExistentialAny: true, usesModuleSelectors: true)
        #expect(interface.contains("var classBound: any ExistentialAnyFixture::Marker & Swift::AnyObject\n"), "\(interface)")
        #expect(interface.contains("var protocolMetatype: (any ExistentialAnyFixture::Marker).Type\n"), "\(interface)")
        #expect(interface.contains("func opaqueSequence() -> some Swift::Sequence<any ExistentialAnyFixture::Marker>\n"), "\(interface)")
    }
}

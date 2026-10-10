import Foundation
import Testing
import MachOKit
@_spi(Support) @testable import SwiftPrinting
@_spi(Support) @testable import SwiftInterface
@testable import MachOTestingSupport

/// `SwiftDeclarationPrintConfiguration.usesModuleSelectors` qualifies the
/// interface's names with SE-0491 module selectors, by the rules the Swift
/// 6.4 compiler applies when it writes a `.swiftinterface` (evolution
/// proposal `module-selectors`): every type level carries the module that
/// declared it, while a type parameter's associated type carries none.
///
/// The expected spellings follow those rules, not this printer's output:
/// each is the compiler's spelling of the same shape in the Xcode 27 SDK
/// interfaces (`Swift::Duration.Foundation::TimeFormatStyle`,
/// `~Swift::Copyable`, `Swift::AnyObject`) with this fixture's names.
@Suite(.serialized)
struct ModuleSelectorInterfaceTests {
    private func printedInterface(usesModuleSelectors: Bool) async throws -> String {
        let machOFile = try ModuleSelectorFixture.machOFile()
        var printConfiguration = SwiftDeclarationPrintConfiguration()
        printConfiguration.usesModuleSelectors = usesModuleSelectors
        let builder = try SwiftInterfaceBuilder(configuration: .init(printConfiguration: printConfiguration), eventHandlers: [], in: machOFile)
        builder.addExtraDataProvider(SwiftInterfaceBuilderOpaqueTypeProvider(machO: machOFile))
        try await builder.prepare()
        return try await builder.printRoot().string
    }

    struct SpellingCase: Sendable, CustomTestStringConvertible {
        let summary: String
        let spellingWithoutSelectors: String
        let spellingWithSelectors: String

        var testDescription: String { summary }
    }

    static let spellingCases: [SpellingCase] = [
        SpellingCase(
            summary: "a type nested in a type of the same module",
            spellingWithoutSelectors: "var nested: ModuleSelectorFixture.Outer.Inner",
            spellingWithSelectors: "var nested: ModuleSelectorFixture::Outer.ModuleSelectorFixture::Inner"
        ),
        SpellingCase(
            summary: "a type this module declares in an extension of a standard library type",
            spellingWithoutSelectors: "var foreignNested: Swift.Duration.LocalFormat",
            spellingWithSelectors: "var foreignNested: Swift::Duration.ModuleSelectorFixture::LocalFormat"
        ),
        SpellingCase(
            summary: "a type nested in a bound generic standard library type",
            spellingWithoutSelectors: "var standardLibraryNested: [Swift.String : Swift.Int].Index",
            spellingWithSelectors: "var standardLibraryNested: [Swift::String : Swift::Int].Swift::Index"
        ),
        SpellingCase(
            summary: "a type nested in a bound generic type of the same module",
            spellingWithoutSelectors: "var genericNested: ModuleSelectorFixture.Box<Swift.Int>.Slot",
            spellingWithSelectors: "var genericNested: ModuleSelectorFixture::Box<Swift::Int>.ModuleSelectorFixture::Slot"
        ),
        SpellingCase(
            summary: "AnyObject in a composition",
            spellingWithoutSelectors: "var composition: ModuleSelectorFixture.Marker & Swift.AnyObject",
            spellingWithSelectors: "var composition: ModuleSelectorFixture::Marker & Swift::AnyObject"
        ),
        SpellingCase(
            summary: "the header of an extension of another module's type",
            spellingWithoutSelectors: "extension Swift.Duration {",
            spellingWithSelectors: "extension Swift::Duration {"
        ),
        SpellingCase(
            summary: "the header of a conformance extension",
            spellingWithoutSelectors: "extension ModuleSelectorFixture.Outer: Swift.Hashable {",
            spellingWithSelectors: "extension ModuleSelectorFixture::Outer: Swift::Hashable {"
        ),
        SpellingCase(
            summary: "the header of a protocol extension",
            spellingWithoutSelectors: "extension ModuleSelectorFixture.Marker {",
            spellingWithSelectors: "extension ModuleSelectorFixture::Marker {"
        ),
        SpellingCase(
            summary: "an opaque type's constraint",
            spellingWithoutSelectors: "func opaqueCollection() -> some Swift.Collection<Swift.Int>",
            spellingWithSelectors: "func opaqueCollection() -> some Swift::Collection<Swift::Int>"
        ),
        SpellingCase(
            summary: "a suppressed conformance in a type header",
            spellingWithoutSelectors: "struct Unique: ~Swift.Copyable",
            spellingWithSelectors: "struct Unique: ~Swift::Copyable"
        ),
        SpellingCase(
            summary: "a suppressed conformance in a where clause",
            spellingWithoutSelectors: "A: ~Swift.Copyable",
            spellingWithSelectors: "A: ~Swift::Copyable"
        ),
        SpellingCase(
            summary: "an associated type of a type parameter keeps no selector",
            spellingWithoutSelectors: "-> [A.Element] where A: Swift.Sequence",
            spellingWithSelectors: "-> [A.Element] where A: Swift::Sequence"
        ),
    ]

    @Test(arguments: spellingCases)
    func interfaceSpellsNamesWithModuleSelectors(_ spellingCase: SpellingCase) async throws {
        let interfaceWithoutSelectors = try await printedInterface(usesModuleSelectors: false)
        #expect(interfaceWithoutSelectors.contains(spellingCase.spellingWithoutSelectors), "\(interfaceWithoutSelectors)")
        let interfaceWithSelectors = try await printedInterface(usesModuleSelectors: true)
        #expect(interfaceWithSelectors.contains(spellingCase.spellingWithSelectors), "\(interfaceWithSelectors)")
    }

    /// The sweep: once a module is spelled with a selector anywhere, no name
    /// may still be qualified with it the old way. Catches a print path that
    /// writes a qualified name by hand instead of through the type printer —
    /// the extension header was one when the option was added.
    @Test func noNameKeepsItsDottedQualification() async throws {
        let interface = try await printedInterface(usesModuleSelectors: true)
        #expect(interface.contains("Swift::") && interface.contains("\(ModuleSelectorFixture.moduleName)::"), "\(interface)")
        for dottedQualification in ModuleSelectorFixture.dottedQualifications(in: interface) {
            Issue.record("dotted qualification `\(dottedQualification.qualifiedName)` left in: \(dottedQualification.line)")
        }
    }
}

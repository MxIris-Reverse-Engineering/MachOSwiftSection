import Foundation
import Testing
import Semantic
@testable import SwiftDeclarationRendering

/// What formatting promises to keep: it adds line breaks and indentation and
/// drops the space of a broken `, `, and nothing else changes — not the
/// text, not a component's semantic type or identifier, not the regions a
/// host reads back out of the identifiers.
@Suite
struct MultilineTypeFormattingPreservationTests {
    private static let swiftUIBody = """
    extension SettingsApp.SettingsNavigationSplitView: SwiftUI.View {
        typealias Body = SwiftUI.ModifiedContent<SwiftUI.ModifiedContent<SwiftUI.SceneBridgeReader<SwiftUI.SubscriptionView<Combine.PassthroughSubject<Any, Swift.Never>, SwiftUI.NavigationSplitView<SwiftUI.ModifiedContent<SettingsApp.SettingsSidebarList, SwiftUI.ToolbarRemovingModifier>, SettingsApp.SettingsSecondaryColumn>>>, SwiftUI._EnvironmentKeyWritingModifier<Swift.Bool>>, SwiftUI.OnTestViewModifier>
        func update(model: Swift.Result<Swift.Int, Swift.Error>, content: Pair<Swift.Int, (Swift.String, [Swift.String : Pair<A, B>])>) -> Swift.Bool
        var handler: (Pair<Swift.Int, Swift.String>) -> Swift.Void
    }
    """

    private static let sources: [String] = [
        swiftUIBody,
        "var value: Box<Pair<Swift.Int, Swift.String>>",
        "    var pair: (Swift.Int, Swift.String, Pair<A, B>)",
        "func make() -> Pair<A, B>",
    ]

    private static let widths = [10, 30, 60, 100]

    /// `source` with every component carrying an identifier of its own, the
    /// way a printer stamps type references and regions.
    private static func identified(_ source: SemanticString) -> SemanticString {
        SemanticString(components: source.components.enumerated().map { componentIndex, component in
            AtomicComponent(string: component.string, type: component.type, identifier: "component\(componentIndex)")
        })
    }

    /// Every character of `string` that is not whitespace, with the semantic
    /// type and identifier of the component it lies in.
    private static func visibleCharacters(of string: SemanticString) -> [(character: Character, type: SemanticType, identifier: String?)] {
        string.components.flatMap { component in
            component.string.filter { !$0.isWhitespace }.map { (character: $0, type: component.type, identifier: component.identifier) }
        }
    }

    @Test(arguments: sources, widths)
    func formattingKeepsSemanticTypesAndIdentifiers(source: String, maximumLineWidth: Int) {
        let identifiedSource = Self.identified(PrinterShapedSource.make(source))
        let formatted = MultilineTypeFormatting(maximumLineWidth: maximumLineWidth).format(identifiedSource)
        let sourceCharacters = Self.visibleCharacters(of: identifiedSource)
        let formattedCharacters = Self.visibleCharacters(of: formatted)
        #expect(sourceCharacters.count == formattedCharacters.count)
        for (sourceCharacter, formattedCharacter) in zip(sourceCharacters, formattedCharacters) {
            #expect(sourceCharacter.character == formattedCharacter.character)
            #expect(sourceCharacter.type == formattedCharacter.type)
            #expect(sourceCharacter.identifier == formattedCharacter.identifier)
        }
    }

    @Test func insertedLineBreaksCarryTheIdentifierOfTheirBracketOrComma() {
        let source = SemanticString(components: [
            AtomicComponent(string: "Pair", type: .type(.struct, .name), identifier: "pair"),
            AtomicComponent(string: "<", type: .standard, identifier: "opening"),
            AtomicComponent(string: "A", type: .type(.other, .name)),
            AtomicComponent(string: ", ", type: .standard, identifier: "separator"),
            AtomicComponent(string: "B", type: .type(.other, .name)),
            AtomicComponent(string: ">", type: .standard, identifier: "closing"),
        ])
        let formatted = MultilineTypeFormatting(maximumLineWidth: 5).format(source)
        #expect(formatted.components == [
            AtomicComponent(string: "Pair", type: .type(.struct, .name), identifier: "pair"),
            AtomicComponent(string: "<", type: .standard, identifier: "opening"),
            AtomicComponent(string: "\n", type: .standard, identifier: "opening"),
            AtomicComponent(string: "    ", type: .standard, identifier: "opening"),
            AtomicComponent(string: "A", type: .type(.other, .name)),
            AtomicComponent(string: ",", type: .standard, identifier: "separator"),
            AtomicComponent(string: "\n", type: .standard, identifier: "separator"),
            AtomicComponent(string: "    ", type: .standard, identifier: "separator"),
            AtomicComponent(string: "B", type: .type(.other, .name)),
            AtomicComponent(string: "\n", type: .standard, identifier: "closing"),
            AtomicComponent(string: ">", type: .standard, identifier: "closing"),
        ])
    }

    @Test func unchangedLinesAroundAChangedLineKeepTheirComponents() {
        let comment = AtomicComponent(string: "// first\n// second\n", type: .comment, identifier: "comment")
        var source = SemanticString(components: [comment])
        source.append(PrinterShapedSource.make("var value: Pair<A, B>\n"))
        source.append(AtomicComponent(string: "// third", type: .comment, identifier: "trailing"))
        let formatted = MultilineTypeFormatting(maximumLineWidth: 10).format(source)
        #expect(formatted.components.first == comment)
        #expect(formatted.components.last == AtomicComponent(string: "// third", type: .comment, identifier: "trailing"))
        #expect(formatted.string == """
        // first
        // second
        var value: Pair<
            A,
            B
        >
        // third
        """)
    }

    @Test(arguments: sources, widths)
    func removingInsertedBreaksRestoresTheOriginalText(source: String, maximumLineWidth: Int) throws {
        let formatted = MultilineTypeFormatting(maximumLineWidth: maximumLineWidth).format(PrinterShapedSource.make(source)).string
        var restored = formatted
        for (pattern, template) in [(#"([<(\[])\n +"#, "$1"), (#",\n +"#, ", "), (#"\n +([>)\]])"#, "$1"), (#"\n([>)\]])"#, "$1")] {
            let expression = try NSRegularExpression(pattern: pattern)
            restored = expression.stringByReplacingMatches(in: restored, range: NSRange(restored.startIndex..., in: restored), withTemplate: template)
        }
        #expect(restored == source)
    }

    @Test(arguments: sources, widths)
    func formattingIsIdempotent(source: String, maximumLineWidth: Int) {
        let formatting = MultilineTypeFormatting(maximumLineWidth: maximumLineWidth)
        let formattedOnce = formatting.format(PrinterShapedSource.make(source))
        let formattedTwice = formatting.format(formattedOnce)
        #expect(formattedTwice.components == formattedOnce.components)
    }

    /// Indenting every non-empty line by four spaces.
    private static func indented(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.isEmpty ? String($0) : "    " + $0 }
            .joined(separator: "\n")
    }

    @Test(arguments: sources, widths)
    func formattingCommutesWithIndentation(source: String, maximumLineWidth: Int) {
        let formatting = MultilineTypeFormatting(maximumLineWidth: maximumLineWidth)
        let formattedThenIndented = Self.indented(formatting.format(PrinterShapedSource.make(source)).string)
        let indentedThenFormatted = formatting.format(PrinterShapedSource.make(Self.indented(source))).string
        #expect(indentedThenFormatted == formattedThenIndented)
    }

    @Test func annotationAndVisibilityRegionsReadBackUnchanged() throws {
        let typeAlias = "    typealias Body = Pair<Box<Swift.Int>, Pair<Swift.String, Swift.Double>>"
        var source = PrinterShapedSource.make("struct Holder {\n")
        source.append(VisibilityRegion(.enabled("printsTypeAliases"), content: SemanticString(AnnotationRegion(AnnotationRegion.Kind("note"), content: PrinterShapedSource.make(typeAlias)))))
        source.append(PrinterShapedSource.make("\n}"))
        let formatting = MultilineTypeFormatting(maximumLineWidth: 30)
        let formattedTypeAlias = formatting.format(PrinterShapedSource.make(typeAlias)).string

        let formatted = formatting.format(source).frozen()
        let visibility = formatted.separatingVisibilityRegions()
        #expect(visibility.regions.regions.count == 1)
        let hidden = visibility.regions.projection(of: visibility.text, where: { _ in false }).text.string
        #expect(hidden == "struct Holder {\n\n}")
        let shown = visibility.regions.projection(of: visibility.text, where: { _ in true }).text
        #expect(shown.string == "struct Holder {\n" + formattedTypeAlias + "\n}")

        let annotations = shown.separatingAnnotationRegions()
        let region = try #require(annotations.annotations.regions.only)
        #expect(region.kind == AnnotationRegion.Kind("note"))
        let regionBytes = Array(annotations.text.string.utf8)[Int(region.utf8Offset) ..< Int(region.utf8Offset + region.utf8Length)]
        #expect(String(decoding: regionBytes, as: UTF8.self) == formattedTypeAlias.trimmingCharacters(in: .whitespaces))
    }
}

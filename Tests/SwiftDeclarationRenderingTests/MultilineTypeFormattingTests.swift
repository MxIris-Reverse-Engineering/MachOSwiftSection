import Foundation
import Testing
import Semantic
@testable import SwiftDeclarationRendering

/// Builds a `SemanticString` split into components the way both printers split
/// a declaration: each bracket, each `", "`, each run of spaces and each
/// `" -> "` its own `.standard` component, and each word one component of its
/// own — `.keyword` for a keyword, `.type(.other, .name)` for anything else.
/// A test then reads as the text it prints.
enum PrinterShapedSource {
    static let keywords: Set<String> = [
        "any", "case", "class", "enum", "extension", "func", "init", "inout",
        "let", "some", "static", "struct", "typealias", "var", "where",
    ]

    static func make(_ text: String) -> SemanticString {
        var components: [AtomicComponent] = []
        var remainingText = Substring(text)
        while let firstCharacter = remainingText.first {
            if remainingText.hasPrefix(", ") {
                components.append(AtomicComponent(string: ", ", type: .standard))
                remainingText = remainingText.dropFirst(2)
            } else if remainingText.hasPrefix(" -> ") {
                components.append(AtomicComponent(string: " -> ", type: .standard))
                remainingText = remainingText.dropFirst(4)
            } else if firstCharacter == " " {
                let spaces = remainingText.prefix(while: { $0 == " " })
                components.append(AtomicComponent(string: String(spaces), type: .standard))
                remainingText = remainingText.dropFirst(spaces.count)
            } else if isWordCharacter(firstCharacter) {
                let word = String(remainingText.prefix(while: isWordCharacter))
                components.append(AtomicComponent(string: word, type: keywords.contains(word) ? .keyword : .type(.other, .name)))
                remainingText = remainingText.dropFirst(word.count)
            } else {
                components.append(AtomicComponent(string: String(firstCharacter), type: .standard))
                remainingText = remainingText.dropFirst()
            }
        }
        return SemanticString(components: components)
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_" || character == "." || character == "$"
    }
}

@Suite
struct MultilineTypeFormattingTests {
    // MARK: - Lines and the width gate

    @Test func emptySourceIsUnchanged() {
        let formatted = MultilineTypeFormatting(maximumLineWidth: 10).format(SemanticString())
        #expect(formatted.components.isEmpty)
    }

    @Test func linesWithinWidthAreUnchangedComponentForComponent() {
        let source = PrinterShapedSource.make("""
        struct Holder {
            var result: Swift.Result<Swift.Int, Swift.Error>
            typealias Body = SwiftUI.ModifiedContent<SwiftUI.EmptyView, SwiftUI.EmptyModifier>
        }
        """)
        let formatted = MultilineTypeFormatting(maximumLineWidth: 120).format(source)
        #expect(formatted.components == source.components)
    }

    @Test func contentWidthIgnoresLeadingIndentation() throws {
        let lines = MultilineTypeFormatting.SourceLine.lines(in: PrinterShapedSource.make("        var count: Int").components)
        let line = try #require(lines.only)
        #expect(line.leadingIndentation == 8)
        #expect(line.contentWidth == "var count: Int".count)
    }

    @Test func linesSplitAtLineBreaksInsideAComponent() {
        let components = [
            AtomicComponent(string: "first\n    second", type: .comment, identifier: "identity"),
            AtomicComponent(string: " tail", type: .standard),
        ]
        let lines = MultilineTypeFormatting.SourceLine.lines(in: components)
        #expect(lines.count == 2)
        #expect(lines[0].fragments.map(\.text) == ["first"])
        #expect(lines[0].terminator?.componentIndex == 0)
        #expect(lines[1].fragments.map(\.text) == ["    second", " tail"])
        #expect(lines[1].fragments.map(\.componentIndex) == [0, 1])
        #expect(lines[1].leadingIndentation == 4)
        #expect(lines[1].contentWidth == "second tail".count)
    }

    @Test func unchangedLinesSplitInsideAComponentComeBackAsThatComponent() {
        let source = SemanticString(components: [
            AtomicComponent(string: "// first\n    // second", type: .comment, identifier: "identity"),
            AtomicComponent(string: "\n", type: .standard),
        ])
        let formatted = MultilineTypeFormatting(maximumLineWidth: 4).format(source)
        #expect(formatted.components == source.components)
    }

    @Test func nonPositiveWidthIsAPreconditionFailure() async {
        await #expect(processExitsWith: .failure) {
            _ = MultilineTypeFormatting(maximumLineWidth: 0)
        }
    }
}

extension Collection {
    /// The collection's single element; `nil` when it has none or several.
    var only: Element? {
        count == 1 ? first : nil
    }
}

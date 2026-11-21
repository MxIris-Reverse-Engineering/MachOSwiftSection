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

    // MARK: - The bracket tree

    /// The bracket tree of the single line `source` holds, written back as
    /// text: each list with its elements separated by `|` instead of their
    /// commas, a declaration's generic parameters in `‹›`. `nil` when the
    /// line does not parse.
    private func bracketStructure(of source: SemanticString) throws -> String? {
        let components = source.components
        let line = try #require(MultilineTypeFormatting.SourceLine.lines(in: components).only)
        return MultilineTypeFormatting.BracketTree.parse(line, sourceComponents: components).map(describe)
    }

    private func describe(_ nodes: [MultilineTypeFormatting.BracketTreeNode]) -> String {
        nodes.map { node in
            switch node {
            case .text(let fragment):
                return String(fragment.text)
            case .list(let list):
                let brackets: (opening: String, closing: String) = switch list.kind {
                case .genericArguments: ("<", ">")
                case .genericParameters: ("‹", "›")
                case .parentheses: ("(", ")")
                case .squareBrackets: ("[", "]")
                }
                return brackets.opening + list.elements.map(describe).joined(separator: "|") + brackets.closing
            }
        }.joined()
    }

    @Test func genericArgumentListsNestInsideParenthesesAndBrackets() throws {
        let structure = try bracketStructure(of: PrinterShapedSource.make("var value: ([Pair<A, B>], C) -> Box<D>"))
        #expect(structure == "var value: ([Pair<A| B>]| C) -> Box<D>")
    }

    @Test func angleBracketAfterDeclarationNameIsGenericParameterClause() throws {
        let function = SemanticString(components: [
            AtomicComponent(string: "func", type: .keyword),
            AtomicComponent(string: " ", type: .standard),
            AtomicComponent(string: "make", type: .function(.declaration)),
            AtomicComponent(string: "<", type: .standard),
            AtomicComponent(string: "A", type: .type(.other, .name)),
            AtomicComponent(string: ", ", type: .standard),
            AtomicComponent(string: "B", type: .type(.other, .name)),
            AtomicComponent(string: ">", type: .standard),
            AtomicComponent(string: "(", type: .standard),
            AtomicComponent(string: ")", type: .standard),
        ])
        #expect(try bracketStructure(of: function) == "func make‹A| B›()")

        let structure = SemanticString(components: [
            AtomicComponent(string: "struct", type: .keyword),
            AtomicComponent(string: " ", type: .standard),
            AtomicComponent(string: "Holder", type: .type(.struct, .declaration)),
            AtomicComponent(string: "<", type: .standard),
            AtomicComponent(string: "Element", type: .type(.other, .name)),
            AtomicComponent(string: ">", type: .standard),
        ])
        #expect(try bracketStructure(of: structure) == "struct Holder‹Element›")
    }

    @Test func arrowIsNotAClosingBracket() throws {
        #expect(try bracketStructure(of: PrinterShapedSource.make("Box<(A) -> B>")) == "Box<(A) -> B>")

        let arrowAcrossComponents = SemanticString(components: [
            AtomicComponent(string: "Box", type: .type(.other, .name)),
            AtomicComponent(string: "<", type: .standard),
            AtomicComponent(string: "(", type: .standard),
            AtomicComponent(string: ")", type: .standard),
            AtomicComponent(string: " -", type: .standard),
            AtomicComponent(string: "> ", type: .standard),
            AtomicComponent(string: "B", type: .type(.other, .name)),
            AtomicComponent(string: ">", type: .standard),
        ])
        #expect(try bracketStructure(of: arrowAcrossComponents) == "Box<() -> B>")
    }

    @Test func bracketsInsideStringLiteralsAreText() throws {
        let attribute = SemanticString(components: [
            AtomicComponent(string: "@available", type: .keyword),
            AtomicComponent(string: "(*, deprecated, message: \"use Box<A, B> or \\\"(\\\"\")", type: .standard),
        ])
        #expect(try bracketStructure(of: attribute) == "@available(*| deprecated| message: \"use Box<A, B> or \\\"(\\\"\")")
    }

    @Test func bracketsInsideBackticksAreText() throws {
        let name = SemanticString(components: [
            AtomicComponent(string: "Box<`<(`, B>", type: .standard),
        ])
        #expect(try bracketStructure(of: name) == "Box<`<(`| B>")
    }

    @Test func bracketsAfterLineCommentAreText() throws {
        let line = SemanticString(components: [
            AtomicComponent(string: "var value: Box<A> // Box<A, (", type: .standard),
        ])
        #expect(try bracketStructure(of: line) == "var value: Box<A> // Box<A, (")
    }

    @Test func bracketsInNonStandardComponentsAreText() throws {
        let line = SemanticString(components: [
            AtomicComponent(string: "static func", type: .keyword),
            AtomicComponent(string: " ", type: .standard),
            AtomicComponent(string: "<", type: .function(.declaration)),
            AtomicComponent(string: " (", type: .standard),
            AtomicComponent(string: "lhs", type: .argument),
            AtomicComponent(string: ": ", type: .standard),
            AtomicComponent(string: "(Visitor in $1234)", type: .type(.struct, .name)),
            AtomicComponent(string: ", ", type: .standard),
            AtomicComponent(string: "rhs", type: .argument),
            AtomicComponent(string: ": ", type: .standard),
            AtomicComponent(string: "Box", type: .type(.other, .name)),
            AtomicComponent(string: ")", type: .standard),
            AtomicComponent(string: " // Box<A, (", type: .comment),
        ])
        #expect(try bracketStructure(of: line) == "static func < (lhs: (Visitor in $1234)| rhs: Box) // Box<A, (")
    }

    @Test func commaOutsideBracketsIsText() throws {
        #expect(try bracketStructure(of: PrinterShapedSource.make("case first, second")) == "case first, second")
    }

    @Test func unbalancedLineIsLeftUnparsed() throws {
        #expect(try bracketStructure(of: PrinterShapedSource.make("Box<A, (B>")) == nil)
        #expect(try bracketStructure(of: PrinterShapedSource.make("Box<A")) == nil)
        #expect(try bracketStructure(of: PrinterShapedSource.make("A)")) == nil)
    }

    @Test func operatorDeclarationFromDumpIsLeftUnparsed() throws {
        let line = SemanticString(components: [
            AtomicComponent(string: "static func", type: .keyword),
            AtomicComponent(string: " ", type: .standard),
            AtomicComponent(string: "< infix", type: .standard),
            AtomicComponent(string: "(", type: .standard),
            AtomicComponent(string: "Swift.Int", type: .type(.struct, .name)),
            AtomicComponent(string: ", ", type: .standard),
            AtomicComponent(string: "Swift.Int", type: .type(.struct, .name)),
            AtomicComponent(string: ")", type: .standard),
            AtomicComponent(string: " -> ", type: .standard),
            AtomicComponent(string: "Swift.Bool", type: .type(.struct, .name)),
        ])
        #expect(try bracketStructure(of: line) == nil)
    }

    @Test func closingColumnCountsFromTheEndOfIndentation() throws {
        let components = PrinterShapedSource.make("    Box<Pair<A, B>>").components
        let line = try #require(MultilineTypeFormatting.SourceLine.lines(in: components).only)
        let nodes = try #require(MultilineTypeFormatting.BracketTree.parse(line, sourceComponents: components))
        guard case .list(let outerList) = try #require(nodes.last) else {
            Issue.record("the line should end in a list")
            return
        }
        #expect(outerList.closingColumn == "Box<Pair<A, B>>".count)
        guard case .list(let innerList) = try #require(outerList.elements.only?.last) else {
            Issue.record("the outer list should hold a list")
            return
        }
        #expect(innerList.closingColumn == "Box<Pair<A, B>".count)
    }
}

extension Collection {
    /// The collection's single element; `nil` when it has none or several.
    var only: Element? {
        count == 1 ? first : nil
    }
}

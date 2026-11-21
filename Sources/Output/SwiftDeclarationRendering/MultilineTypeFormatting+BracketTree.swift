import Foundation
import Semantic

extension MultilineTypeFormatting {
    /// What a bracketed list is, which decides when it breaks.
    enum BracketKind: Equatable {
        /// `<…>` after a type: the arguments of a generic type, the only
        /// list that breaks for having two or more elements.
        case genericArguments

        /// `<…>` right after a declaration's name: the declaration's generic
        /// parameters.
        case genericParameters

        /// `(…)`: a tuple, a function type's parameters, a declaration's
        /// parameters, an enum case's payload, an attribute's arguments.
        case parentheses

        /// `[…]`: array and dictionary sugar.
        case squareBrackets

        var closingCharacter: Character {
            switch self {
            case .genericArguments,
                 .genericParameters:
                ">"
            case .parentheses:
                ")"
            case .squareBrackets:
                "]"
            }
        }
    }

    /// One bracketed list of a line: its brackets, the commas between its
    /// elements, and the elements themselves.
    struct BracketList {
        let kind: BracketKind

        let opening: SourceFragment

        let closing: SourceFragment

        /// The `,` between the elements, one fewer than `elements`.
        let separators: [SourceFragment]

        var elements: [[BracketTreeNode]]

        /// Where the closing bracket stands on its line, counting from 1 at
        /// the first character after the line's indentation.
        let closingColumn: Int

        /// Whether the list puts each element on a line of its own. Decided
        /// by `LineLayout`; the parser leaves it `false`.
        var isBroken = false
    }

    indirect enum BracketTreeNode {
        case text(SourceFragment)
        case list(BracketList)
    }

    enum BracketTree {
        /// `line` taken apart into text and bracketed lists; `nil` when its
        /// brackets do not pair up, and the line is then left as printed.
        ///
        /// Brackets count only in `.standard` components, which is where
        /// both printers write punctuation: a type name, a declaration name
        /// (an operator's included), a keyword or a comment is text whatever
        /// it contains. In a `.standard` component, a string literal, a
        /// backtick-quoted name and everything after `//` are text, and the
        /// `>` of `->` closes nothing. A line whose brackets still do not
        /// pair up — the dump spells an operator `< infix` — is not guessed
        /// at.
        static func parse(_ line: SourceLine, sourceComponents: [AtomicComponent]) -> [BracketTreeNode]? {
            var parser = BracketTreeParser(leadingIndentation: line.leadingIndentation)
            for fragment in line.fragments {
                let sourceComponent = sourceComponents[fragment.componentIndex]
                if sourceComponent.type == .standard {
                    guard parser.scanPunctuation(in: fragment) else { return nil }
                } else {
                    parser.appendText(fragment, type: sourceComponent.type)
                }
            }
            return parser.finish()
        }
    }
}

private struct BracketTreeParser {
    typealias SourceFragment = MultilineTypeFormatting.SourceFragment
    typealias BracketKind = MultilineTypeFormatting.BracketKind
    typealias BracketList = MultilineTypeFormatting.BracketList
    typealias BracketTreeNode = MultilineTypeFormatting.BracketTreeNode

    private enum Punctuation {
        case opening(Character)
        case closing(Character)
        case separator
    }

    /// A list whose closing bracket has not been read yet.
    private struct OpenList {
        let kind: BracketKind
        let opening: SourceFragment
        var separators: [SourceFragment] = []
        var elements: [[BracketTreeNode]] = []
        var currentElement: [BracketTreeNode] = []
    }

    let leadingIndentation: Int

    private var rootNodes: [BracketTreeNode] = []

    private var openLists: [OpenList] = []

    /// How many characters of the line have been read, its indentation
    /// included.
    private var readCharacterCount = 0

    private var previousCharacter: Character?

    /// The semantic type of the last component that held more than
    /// whitespace — what a `<` follows decides whether it opens generic
    /// arguments or a declaration's generic parameters.
    private var lastSignificantType: SemanticType?

    private var isInStringLiteral = false

    private var escapesNextCharacter = false

    private var isInBacktickName = false

    private var isInLineComment = false

    init(leadingIndentation: Int) {
        self.leadingIndentation = leadingIndentation
    }

    /// A component that is not punctuation: text whatever it contains.
    mutating func appendText(_ fragment: SourceFragment, type: SemanticType) {
        appendNode(.text(fragment))
        readCharacterCount += fragment.text.count
        if fragment.text.contains(where: { !$0.isWhitespace }) {
            lastSignificantType = type
        }
        previousCharacter = fragment.text.last ?? previousCharacter
    }

    /// Reads a `.standard` component, splitting it at every bracket and
    /// list separator. `false` when a closing bracket does not match the
    /// list it would close.
    mutating func scanPunctuation(in fragment: SourceFragment) -> Bool {
        let text = fragment.text
        var textRunStart = text.startIndex
        var characterIndex = text.startIndex
        while characterIndex < text.endIndex {
            let character = text[characterIndex]
            readCharacterCount += 1
            if let punctuation = punctuation(for: character) {
                appendStandardText(SourceFragment(componentIndex: fragment.componentIndex, text: text[textRunStart ..< characterIndex]))
                let nextIndex = text.index(after: characterIndex)
                let punctuationFragment = SourceFragment(componentIndex: fragment.componentIndex, text: text[characterIndex ..< nextIndex])
                switch punctuation {
                case .opening(let bracket):
                    open(bracket, at: punctuationFragment)
                case .closing(let bracket):
                    guard close(bracket, at: punctuationFragment) else { return false }
                case .separator:
                    separate(at: punctuationFragment)
                }
                textRunStart = nextIndex
            }
            previousCharacter = character
            characterIndex = text.index(after: characterIndex)
        }
        appendStandardText(SourceFragment(componentIndex: fragment.componentIndex, text: text[textRunStart ..< text.endIndex]))
        return true
    }

    /// The tree read so far; `nil` while a list is still open.
    func finish() -> [BracketTreeNode]? {
        openLists.isEmpty ? rootNodes : nil
    }

    // MARK: - Reading

    private mutating func punctuation(for character: Character) -> Punctuation? {
        if isInLineComment {
            return nil
        }
        if isInStringLiteral {
            if escapesNextCharacter {
                escapesNextCharacter = false
            } else if character == "\\" {
                escapesNextCharacter = true
            } else if character == "\"" {
                isInStringLiteral = false
            }
            return nil
        }
        if isInBacktickName {
            if character == "`" {
                isInBacktickName = false
            }
            return nil
        }
        switch character {
        case "\"":
            isInStringLiteral = true
            return nil
        case "`":
            isInBacktickName = true
            return nil
        case "/":
            if previousCharacter == "/" {
                isInLineComment = true
            }
            return nil
        case "<", "(", "[":
            return .opening(character)
        case ">":
            return previousCharacter == "-" ? nil : .closing(character)
        case ")", "]":
            return .closing(character)
        case ",":
            return openLists.isEmpty ? nil : .separator
        default:
            return nil
        }
    }

    private mutating func appendStandardText(_ fragment: SourceFragment) {
        guard !fragment.text.isEmpty else { return }
        appendNode(.text(fragment))
        if fragment.text.contains(where: { !$0.isWhitespace }) {
            lastSignificantType = .standard
        }
    }

    private mutating func open(_ bracket: Character, at fragment: SourceFragment) {
        let kind: BracketKind
        switch bracket {
        case "<":
            kind = lastSignificantType.map(Self.namesADeclaration) == true ? .genericParameters : .genericArguments
        case "(":
            kind = .parentheses
        default:
            kind = .squareBrackets
        }
        openLists.append(OpenList(kind: kind, opening: fragment))
        lastSignificantType = .standard
    }

    private mutating func close(_ bracket: Character, at fragment: SourceFragment) -> Bool {
        guard var list = openLists.popLast(), list.kind.closingCharacter == bracket else { return false }
        list.elements.append(list.currentElement)
        let kind: BracketKind = list.kind == .genericArguments && Self.holdsRequirements(list.elements) ? .genericParameters : list.kind
        let closedList = BracketList(
            kind: kind,
            opening: list.opening,
            closing: fragment,
            separators: list.separators,
            elements: list.elements,
            closingColumn: readCharacterCount - leadingIndentation
        )
        appendNode(.list(closedList))
        lastSignificantType = .standard
        return true
    }

    private mutating func separate(at fragment: SourceFragment) {
        let innermostIndex = openLists.count - 1
        openLists[innermostIndex].elements.append(openLists[innermostIndex].currentElement)
        openLists[innermostIndex].currentElement = []
        openLists[innermostIndex].separators.append(fragment)
        lastSignificantType = .standard
    }

    private mutating func appendNode(_ node: BracketTreeNode) {
        if openLists.isEmpty {
            rootNodes.append(node)
        } else {
            openLists[openLists.count - 1].currentElement.append(node)
        }
    }

    /// Whether a `<…>` list holds requirements rather than types — a generic
    /// signature, which the dump writes after a type name too
    /// (`_ConditionalContent< where A: P, B: Q>`, `make<A, B where A == B.Element>`).
    /// One element says `where`, `A: P` or `A == B` at its own level, outside
    /// any list nested in it. A type argument never does: a module selector's
    /// `::` and the dump's `(extension in M):` prefix have no space after the
    /// colon, and a tuple's labels sit in a list of their own.
    private static func holdsRequirements(_ elements: [[BracketTreeNode]]) -> Bool {
        elements.contains { element in
            let topLevelText = element.map { node in
                if case .text(let fragment) = node { String(fragment.text) } else { " " }
            }.joined()
            return topLevelText.split(whereSeparator: \.isWhitespace).contains("where")
                || topLevelText.contains(": ")
                || topLevelText.contains("==")
        }
    }

    private static func namesADeclaration(_ type: SemanticType) -> Bool {
        switch type {
        case .type(_, .declaration),
             .function(.declaration),
             .member(.declaration):
            true
        default:
            false
        }
    }
}

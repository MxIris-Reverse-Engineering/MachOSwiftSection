import Testing
import Semantic
@testable import SwiftInterface

/// Builds a one-line ``DiffLine`` for the synthetic block fixtures below.
private func line(_ marker: DiffMarker, _ content: SemanticString, indent: Int = 0) -> DiffLine {
    DiffLine(marker: marker, content: content, indentLevel: indent)
}

@Suite("DiffFormat.inline")
struct DiffFormatInlineTests {
    @Test("a single line is marker + level indent + content at column 0")
    func singleLine() {
        let blocks = [[line(.added, "var x: Int", indent: 1)]]
        #expect(DiffFormat.inline.render(blocks).string == "+    var x: Int")
    }

    @Test("lines within a block are joined by a single newline")
    func withinBlockNewline() {
        let blocks = [[
            line(.unchanged, "struct A {", indent: 0),
            line(.added, "var x: Int", indent: 1),
            line(.unchanged, "}", indent: 0),
        ]]
        #expect(DiffFormat.inline.render(blocks).string == " struct A {\n+    var x: Int\n }")
    }

    @Test("top-level blocks are separated by exactly one bare blank line")
    func blockSeparator() {
        let blocks = [
            [line(.unchanged, "struct A {", indent: 0), line(.unchanged, "}", indent: 0)],
            [line(.removed, "func gone()", indent: 0)],
        ]
        #expect(DiffFormat.inline.render(blocks).string == " struct A {\n }\n\n-func gone()")
    }

    @Test("a blank interior line carries only the marker, no trailing indent")
    func blankInteriorLine() {
        let blocks = [[
            line(.added, "a", indent: 1),
            line(.added, "", indent: 1),
            line(.added, "b", indent: 1),
        ]]
        #expect(DiffFormat.inline.render(blocks).string == "+    a\n+\n+    b")
    }

    @Test("an all-whitespace line gets no structural indent (content kept verbatim)")
    func whitespaceOnlyLineIsBlank() {
        let blocks = [[line(.unchanged, "    ", indent: 2)]]
        // All-whitespace content => the marker is NOT followed by the level's
        // indent (the `whitespace`, not `isEmpty`, blankness rule); the four
        // content spaces themselves are kept. So: " " (marker) + "    " (content).
        #expect(DiffFormat.inline.render(blocks).string == "     ")
    }

    @Test("empty blocks contribute nothing and emit no separator")
    func emptyBlocksSkipped() {
        let blocks: [[DiffLine]] = [[], [line(.added, "x", indent: 0)], []]
        #expect(DiffFormat.inline.render(blocks).string == "+x")
    }

    @Test("the result has no leading or trailing newline")
    func noOwnNewline() {
        let rendered = DiffFormat.inline.render([[line(.unchanged, "a", indent: 0)]]).string
        #expect(!rendered.hasPrefix("\n"))
        #expect(!rendered.hasSuffix("\n"))
        #expect(rendered == " a")
    }

    @Test("an empty stream renders to nothing")
    func emptyStream() {
        #expect(DiffFormat.inline.render([]).string == "")
    }
}

@Suite("DiffFormat.perLine (custom symbols)")
struct DiffFormatPerLineTests {
    @Test("a caller can render its own diff symbols")
    func customSymbols() {
        let arrows = DiffFormat.perLine(blockSeparator: "\n") { marker, content, _ in
            let symbol = switch marker {
            case .added: "▲ "
            case .removed: "▼ "
            case .unchanged: "  "
            }
            return SemanticString(components: [AtomicComponent(string: symbol, type: .standard)]).appending(content)
        }
        let blocks = [
            [arrowsLine(.added, "x")],
            [arrowsLine(.removed, "y")],
        ]
        #expect(arrows.render(blocks).string == "▲ x\n▼ y")
    }

    private func arrowsLine(_ marker: DiffMarker, _ content: SemanticString) -> DiffLine {
        DiffLine(marker: marker, content: content, indentLevel: 0)
    }
}

@Suite("DiffFormat.unified")
struct DiffFormatUnifiedTests {
    @Test("a replacement renders file headers, a hunk header, and marked lines")
    func basicReplacement() {
        let blocks = [[
            line(.unchanged, "a"),
            line(.removed, "b"),
            line(.added, "c"),
            line(.unchanged, "d"),
        ]]
        let expected = """
        --- old
        +++ new
        @@ -1,3 +1,3 @@
         a
        -b
        +c
         d
        """
        #expect(DiffFormat.unified().render(blocks).string == expected)
    }

    @Test("a pure insertion uses -0,0 and omits the length for the single new line")
    func pureInsertion() {
        let blocks = [[line(.added, "x")]]
        let expected = """
        --- old
        +++ new
        @@ -0,0 +1 @@
        +x
        """
        #expect(DiffFormat.unified().render(blocks).string == expected)
    }

    @Test("a pure deletion uses +0,0 and omits the length for the single old line")
    func pureDeletion() {
        let blocks = [[line(.removed, "x")]]
        let expected = """
        --- old
        +++ new
        @@ -1 +0,0 @@
        -x
        """
        #expect(DiffFormat.unified().render(blocks).string == expected)
    }

    @Test("an interface with no changes renders to nothing (no headers, no hunks)")
    func noChanges() {
        let blocks = [[line(.unchanged, "a"), line(.unchanged, "b")]]
        #expect(DiffFormat.unified().render(blocks).string == "")
    }

    @Test("an empty stream renders to nothing")
    func emptyStream() {
        #expect(DiffFormat.unified().render([]).string == "")
    }

    @Test("nil context folds the whole interface into a single hunk")
    func nilContextSingleHunk() {
        let blocks = [[
            line(.unchanged, "a"),
            line(.added, "b"),
            line(.unchanged, "c"),
        ]]
        let expected = """
        --- old
        +++ new
        @@ -1,2 +1,3 @@
         a
        +b
         c
        """
        #expect(DiffFormat.unified(contextLines: nil).render(blocks).string == expected)
    }

    @Test("changes within twice the context budget merge into one hunk")
    func adjacentChangesMerge() {
        let blocks = [[
            line(.unchanged, "a"),   // 0
            line(.removed, "b"),     // 1 change
            line(.unchanged, "c"),   // 2
            line(.added, "d"),       // 3 change
            line(.unchanged, "e"),   // 4
        ]]
        // contextLines 1: run [1,1] -> [0,2], run [3,3] -> [2,4]; 2 <= 2+1 => merge.
        let rendered = DiffFormat.unified(contextLines: 1).render(blocks).string
        #expect(rendered.components(separatedBy: "@@ ").count - 1 == 1)
    }

    @Test("changes farther apart than the context budget stay in separate hunks")
    func distantChangesSplit() {
        let blocks = [[
            line(.unchanged, "a"),   // 0
            line(.removed, "b"),     // 1 change
            line(.unchanged, "c"),   // 2
            line(.unchanged, "d"),   // 3
            line(.unchanged, "e"),   // 4
            line(.added, "f"),       // 5 change
            line(.unchanged, "g"),   // 6
        ]]
        // contextLines 1: run [1,1] -> [0,2], run [5,5] -> [4,6]; 4 > 2+1 => split.
        let rendered = DiffFormat.unified(contextLines: 1).render(blocks).string
        #expect(rendered.components(separatedBy: "@@ -").count - 1 == 2)
    }

    @Test("custom labels appear in the file headers")
    func customLabels() {
        let blocks = [[line(.added, "x")]]
        let rendered = DiffFormat.unified(oldLabel: "a/Foo", newLabel: "b/Foo").render(blocks).string
        #expect(rendered.hasPrefix("--- a/Foo\n+++ b/Foo\n"))
    }

    @Test("content indentation is preserved after the marker")
    func indentationPreserved() {
        let blocks = [[
            line(.unchanged, "struct A {"),
            line(.added, "var x: Int", indent: 1),
            line(.unchanged, "}"),
        ]]
        let rendered = DiffFormat.unified().render(blocks).string
        #expect(rendered.contains("\n+    var x: Int\n"))
    }
}

@Suite("DiffFormat.markdownFenced")
struct DiffFormatMarkdownTests {
    @Test("the inline body is wrapped in a ```diff fence")
    func wrapsInFence() {
        let blocks = [[line(.added, "var x: Int", indent: 0)]]
        let expected = """
        ```diff
        +var x: Int
        ```
        """
        #expect(DiffFormat.markdownFenced.render(blocks).string == expected)
    }

    @Test("the fence grows past the longest backtick run in the body")
    func variableLengthFence() {
        // Content carrying a triple-backtick run must not close a 3-backtick fence.
        let blocks = [[line(.added, "let doc = \"\"\"```\"\"\"", indent: 0)]]
        let rendered = DiffFormat.markdownFenced.render(blocks).string
        #expect(rendered.hasPrefix("````diff\n"))
        #expect(rendered.hasSuffix("\n````"))
    }

    @Test("an empty diff produces empty output (no fence)")
    func emptyIsEmpty() {
        #expect(DiffFormat.markdownFenced.render([]).string == "")
    }
}

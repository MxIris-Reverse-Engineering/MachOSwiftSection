import Testing
import Semantic
@testable import SwiftInterface

@Suite("DiffMarking.markLines")
struct DiffMarkingTests {
    @Test("a single line gets one marker plus the level indent at column 0")
    func singleLine() {
        #expect(DiffMarking.markLines("var x: Int", marker: .added, indentLevel: 1).string == "+    var x: Int")
        #expect(DiffMarking.markLines("var x: Int", marker: .removed, indentLevel: 2).string == "-        var x: Int")
        #expect(DiffMarking.markLines("struct Foo {", marker: .unchanged, indentLevel: 0).string == " struct Foo {")
    }

    @Test("every line of a multi-line unit carries the marker")
    func multiLine() {
        let source: SemanticString = "var x: Int {\n    get\n}"
        #expect(DiffMarking.markLines(source, marker: .added, indentLevel: 1).string == "+    var x: Int {\n+        get\n+    }")
    }

    @Test("a blank interior line carries only the marker, no trailing indent")
    func blankInteriorLine() {
        #expect(DiffMarking.markLines("a\n\nb", marker: .added, indentLevel: 1).string == "+    a\n+\n+    b")
    }

    @Test("empty source produces no output (no stray marker)")
    func emptySource() {
        #expect(DiffMarking.markLines("", marker: .added, indentLevel: 1).string == "")
        #expect(DiffMarking.markLines(SemanticString(), marker: .removed, indentLevel: 0).string == "")
    }

    @Test("the result carries no leading or trailing newline so callers can join with one")
    func noOwnNewline() {
        let marked = DiffMarking.markLines("a\nb", marker: .unchanged, indentLevel: 0).string
        #expect(!marked.hasPrefix("\n"))
        #expect(!marked.hasSuffix("\n"))
        #expect(marked == " a\n b")
    }
}

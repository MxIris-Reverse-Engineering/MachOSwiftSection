import Testing
import Semantic
@testable import SwiftInterface

/// Covers the renderer's container composition — the empty-body `{}` special
/// case, the marker propagation for added/removed containers, and the
/// changed-header `-`/`+` pair — which the synthetic ``DiffFormat`` tests do not
/// exercise (they start from already-assembled `[[DiffLine]]`).
@Suite("DiffContainerAssembler.assemble")
struct DiffContainerAssemblerTests {
    @Test("an empty body renders as ` {}` on the header line with no closing brace")
    func emptyBody() {
        let lines = DiffContainerAssembler.assemble(oldHeader: "", newHeader: "struct Foo", marker: .added, bodyUnits: [], level: 1)
        #expect(lines.count == 1)
        #expect(lines[0].marker == .added)
        #expect(DiffFormat.inline.render([lines]).string == "+struct Foo {}")
    }

    @Test("a non-empty body opens with ` {`, carries body units, and closes with `}`")
    func nonEmptyBody() {
        let bodyLine = DiffLine(marker: .added, content: "var x: Int", indentLevel: 1)
        let lines = DiffContainerAssembler.assemble(oldHeader: "struct Foo", newHeader: "struct Foo", marker: .unchanged, bodyUnits: [[bodyLine]], level: 1)
        #expect(lines.map(\.marker) == [.unchanged, .added, .unchanged])
        #expect(DiffFormat.inline.render([lines]).string == " struct Foo {\n+    var x: Int\n }")
    }

    @Test("an added container marks every line `+` using the new header")
    func addedContainer() {
        let bodyLine = DiffLine(marker: .added, content: "var x: Int", indentLevel: 1)
        let lines = DiffContainerAssembler.assemble(oldHeader: "", newHeader: "struct Foo", marker: .added, bodyUnits: [[bodyLine]], level: 1)
        #expect(lines.allSatisfy { $0.marker == .added })
        #expect(DiffFormat.inline.render([lines]).string == "+struct Foo {\n+    var x: Int\n+}")
    }

    @Test("a removed container marks every line `-` using the old header")
    func removedContainer() {
        let bodyLine = DiffLine(marker: .removed, content: "var x: Int", indentLevel: 1)
        let lines = DiffContainerAssembler.assemble(oldHeader: "struct Foo", newHeader: "", marker: .removed, bodyUnits: [[bodyLine]], level: 1)
        #expect(lines.allSatisfy { $0.marker == .removed })
        #expect(DiffFormat.inline.render([lines]).string == "-struct Foo {\n-    var x: Int\n-}")
    }

    @Test("a changed header on a common container shows old `-` then new `+`, brace unchanged")
    func changedHeader() {
        let bodyLine = DiffLine(marker: .unchanged, content: "var x: Int", indentLevel: 1)
        let lines = DiffContainerAssembler.assemble(oldHeader: "struct Foo: A", newHeader: "struct Foo: B", marker: .unchanged, bodyUnits: [[bodyLine]], level: 1)
        #expect(lines.map(\.marker) == [.removed, .added, .unchanged, .unchanged])
        #expect(DiffFormat.inline.render([lines]).string == "-struct Foo: A {\n+struct Foo: B {\n     var x: Int\n }")
    }

    @Test("nested-level indentation places the marker at column 0 and indents the header after it")
    func nestedLevelIndentation() {
        // A nested type at level 2: headerLevel 1 => 4-space indent after the marker.
        let lines = DiffContainerAssembler.assemble(oldHeader: "", newHeader: "struct Inner", marker: .added, bodyUnits: [], level: 2)
        #expect(DiffFormat.inline.render([lines]).string == "+    struct Inner {}")
    }
}

import Foundation
import Testing
import Semantic
import SwiftDiffing
@_spi(Support) @testable import SwiftInterface

/// Unit tests for the evolution interface's format layer: how a lifecycle
/// annotation becomes a trailing comment (bitmap, event phrases), which line
/// of a unit carries the annotation (members anchor on their first line,
/// container headers on their last), how a block aligns its annotation
/// column, and how a container assembles.
@Suite
struct EvolutionMarkingTests {
    private let versionAxis: [ABIVersionDescriptor] = [
        ABIVersionDescriptor(label: "1.0"),
        ABIVersionDescriptor(label: "2.0"),
        ABIVersionDescriptor(label: "3.0"),
    ]

    // MARK: - Bitmap & phrases

    @Test func bitmapRendersPresencePerVersion() {
        #expect(EvolutionMarking.bitmap([true, true, false]) == "[●●○]")
        #expect(EvolutionMarking.bitmap([false, true]) == "[○●]")
    }

    @Test func addedAndRemovedPhrasesNameTheTransitionVersion() {
        let added = LineageEvent(versionIndex: 1, status: .added)
        let removed = LineageEvent(versionIndex: 2, status: .removed)
        #expect(EvolutionMarking.phrase(for: added, versions: versionAxis) == "added in 2.0")
        #expect(EvolutionMarking.phrase(for: removed, versions: versionAxis) == "removed in 3.0")
    }

    @Test func modifiedPhraseCarriesTheSignatureArrow() {
        let event = LineageEvent(
            versionIndex: 2,
            status: .modified,
            oldSignature: "var count: Swift.Int32",
            newSignature: "var count: Swift.Int64"
        )
        #expect(
            EvolutionMarking.phrase(for: event, versions: versionAxis)
                == "modified in 3.0: var count: Swift.Int32 → var count: Swift.Int64"
        )
    }

    /// A payload change with no signature-visible difference (accessor set,
    /// symbolic identity) keeps the bare phrase — an identical `A → A` arrow
    /// is pure noise, same reasoning as the two-sided renderer's
    /// identical-rendering collapse.
    @Test func modifiedPhraseOmitsAnIdenticalArrow() {
        let identical = LineageEvent(
            versionIndex: 1,
            status: .modified,
            oldSignature: "var count: Swift.Int32",
            newSignature: "var count: Swift.Int32"
        )
        let missingSide = LineageEvent(versionIndex: 1, status: .modified, oldSignature: "var count: Swift.Int32")
        #expect(EvolutionMarking.phrase(for: identical, versions: versionAxis) == "modified in 2.0")
        #expect(EvolutionMarking.phrase(for: missingSide, versions: versionAxis) == "modified in 2.0")
    }

    @Test func annotationTextJoinsMultipleEvents() {
        let annotation = EvolutionAnnotation(
            presence: [true, false, true],
            events: [
                LineageEvent(versionIndex: 1, status: .removed),
                LineageEvent(versionIndex: 2, status: .added),
            ]
        )
        #expect(
            EvolutionMarking.annotationText(for: annotation, versions: versionAxis)
                == "// [●○●] removed in 2.0 · added in 3.0"
        )
    }

    // MARK: - Line classification

    /// A container header's attribute lines precede the declaration, so the
    /// annotation anchors on the LAST line (the one carrying the brace).
    @Test func headerAnnotationAnchorsOnTheLastLine() {
        let annotation = EvolutionAnnotation(presence: [true, true, false], events: [LineageEvent(versionIndex: 2, status: .removed)])
        let lines = EvolutionMarking.annotatedLines("@propertyWrapper\nstruct Foo", annotation: annotation, indentLevel: 1, anchor: .lastLine)
        #expect(lines.count == 2)
        #expect(lines[0].content.string == "@propertyWrapper")
        #expect(lines[0].annotation == nil)
        #expect(lines[1].content.string == "struct Foo")
        #expect(lines[1].annotation == annotation)
    }

    /// A member's first line IS its declaration (attributes print inline), so
    /// the annotation anchors on the FIRST line — a computed property's
    /// trailing accessor block must never carry it on the closing brace.
    @Test func memberAnnotationAnchorsOnTheFirstLine() {
        let annotation = EvolutionAnnotation(presence: [true, false], events: [LineageEvent(versionIndex: 1, status: .removed)])
        let lines = EvolutionMarking.annotatedLines("var x: Swift.Int {\n    get\n}", annotation: annotation, indentLevel: 1, anchor: .firstLine)
        #expect(lines.count == 3)
        #expect(lines[0].content.string == "var x: Swift.Int {")
        #expect(lines[0].annotation == annotation)
        #expect(lines[1].annotation == nil)
        #expect(lines[2].content.string == "}")
        #expect(lines[2].annotation == nil)
    }

    @Test func emptyUnitProducesNoLinesAndNoStrayAnnotation() {
        let annotation = EvolutionAnnotation(presence: [true], events: [LineageEvent(versionIndex: 1, status: .removed)])
        #expect(EvolutionMarking.annotatedLines(SemanticString(), annotation: annotation, indentLevel: 0, anchor: .firstLine).isEmpty)
        #expect(EvolutionMarking.annotatedLines(SemanticString(), annotation: annotation, indentLevel: 0, anchor: .lastLine).isEmpty)
    }

    // MARK: - Block rendering

    private func annotation(_ presence: [Bool], _ events: [LineageEvent]) -> EvolutionAnnotation {
        EvolutionAnnotation(presence: presence, events: events)
    }

    @Test func annotationsAlignOnOneColumnPerBlock() {
        let removed = annotation([true, true, false], [LineageEvent(versionIndex: 2, status: .removed)])
        let block = [
            EvolutionLine(content: "var a: Swift.Int", indentLevel: 1, annotation: removed),
            EvolutionLine(content: "var muchLonger: Swift.Int", indentLevel: 1, annotation: removed),
        ]
        let rendered = EvolutionMarking.renderBlock(block, versions: versionAxis).string
        let lines = rendered.split(separator: "\n").map(String.init)
        let columns = lines.map { line in try! #require(line.range(of: "// [")).lowerBound.utf16Offset(in: line) }
        #expect(columns.count == 2)
        #expect(columns[0] == columns[1])
        // The widest annotated code line keeps exactly the two-space gutter.
        #expect(lines[1].contains("var muchLonger: Swift.Int  // [●●○] removed in 3.0"))
    }

    @Test func unannotatedLinesCarryNoTrailingWhitespace() {
        let block = [
            EvolutionLine(content: "var plain: Swift.Int", indentLevel: 1, annotation: nil),
            EvolutionLine(
                content: "var changed: Swift.Int",
                indentLevel: 1,
                annotation: annotation([false, true, true], [LineageEvent(versionIndex: 1, status: .added)])
            ),
        ]
        let lines = EvolutionMarking.renderBlock(block, versions: versionAxis).string.split(separator: "\n").map(String.init)
        #expect(lines[0] == "    var plain: Swift.Int")
        #expect(lines[1].hasSuffix("// [○●●] added in 2.0"))
    }

    /// A line whose code runs past the alignment cap pushes its annotation
    /// onto its own comment line, indented one level deeper.
    @Test func overlongLinesOverflowTheirAnnotationToTheNextLine() {
        let overlongName = "var " + String(repeating: "x", count: EvolutionMarking.annotationColumnCap) + ": Swift.Int"
        let block = [
            EvolutionLine(
                content: SemanticString(components: [AtomicComponent(string: overlongName, type: .standard)]),
                indentLevel: 1,
                annotation: annotation([true, false], [LineageEvent(versionIndex: 1, status: .removed)])
            ),
        ]
        let lines = EvolutionMarking.renderBlock(block, versions: [versionAxis[0], versionAxis[1]]).string
            .split(separator: "\n").map(String.init)
        #expect(lines.count == 2)
        #expect(lines[0] == "    " + overlongName)
        #expect(lines[1] == "        // [●○] removed in 2.0")
    }

    @Test func blankLinesEmitNothing() {
        let block = [
            EvolutionLine(content: "struct Foo {", indentLevel: 0, annotation: nil),
            EvolutionLine(content: SemanticString(), indentLevel: 1, annotation: nil),
            EvolutionLine(content: "}", indentLevel: 0, annotation: nil),
        ]
        #expect(EvolutionMarking.renderBlock(block, versions: versionAxis).string == "struct Foo {\n\n}")
    }

    // MARK: - Legend & warnings

    @Test func legendNamesTheAxisAndMapsBitmapPositions() {
        let evolution = ABIEvolution(versions: versionAxis)
        let legend = EvolutionMarking.legendLines(for: evolution).string
        #expect(legend == """
        // Swift ABI evolution across 3 versions: 1.0 → 2.0 → 3.0
        // Bitmap positions: [1] 1.0  [2] 2.0  [3] 3.0
        """)
    }

    @Test func warningsAreNilWithoutDiagnostics() {
        #expect(EvolutionMarking.warningsLines(for: ABIEvolution(versions: versionAxis)) == nil)
    }

    @Test func warningsMirrorTheReporterSections() throws {
        let evolution = ABIEvolution(
            versions: versionAxis,
            keyCollisionsByVersion: [
                [],
                [ABIKeyCollision(key: .printed("k"), containerName: "Module.Foo", droppedSignatures: ["var x: Swift.Int"])],
                [],
            ],
            remangleFallbacksByVersion: [
                [],
                [],
                [ABIRemangleFallback(key: .printed("unmangled:f"), containerName: nil, signature: "func f()")],
            ]
        )
        let warnings = try #require(EvolutionMarking.warningsLines(for: evolution)).string
        #expect(warnings.contains("// Warnings — identity-key collisions"))
        #expect(warnings.contains("//   2.0 · Module.Foo · dropped: var x: Swift.Int"))
        #expect(warnings.contains("// Warnings — remangle-fallback keys"))
        #expect(warnings.contains("//   3.0 · func f()"))
    }

    // MARK: - Container assembly

    @Test func emptyBodyRendersInlineBraces() {
        let headerAnnotation = annotation([false, true, true], [LineageEvent(versionIndex: 1, status: .added)])
        let lines = EvolutionContainerAssembler.assemble(
            header: "public struct Foo",
            annotation: headerAnnotation,
            bodyUnits: [],
            level: 1
        )
        #expect(lines.count == 1)
        #expect(lines[0].content.string == "public struct Foo {}")
        #expect(lines[0].indentLevel == 0)
        #expect(lines[0].annotation == headerAnnotation)
    }

    @Test func bodyAndClosingBraceFollowTheHeader() {
        let headerAnnotation = annotation([true, false, false], [LineageEvent(versionIndex: 1, status: .removed)])
        let bodyLine = EvolutionLine(content: "var x: Swift.Int", indentLevel: 1, annotation: nil)
        let lines = EvolutionContainerAssembler.assemble(
            header: "public struct Foo",
            annotation: headerAnnotation,
            bodyUnits: [[bodyLine]],
            level: 1
        )
        #expect(lines.map(\.content.string) == ["public struct Foo {", "var x: Swift.Int", "}"])
        #expect(lines[0].annotation == headerAnnotation)
        #expect(lines[2].annotation == nil)
    }
}

/// Unit tests for the lineage → annotation join: a lookup hit yields an
/// annotation, a miss is the "present throughout, never changed" verdict, and
/// a container whose lineage exists only because of member events keeps its
/// header bare.
@Suite
struct EvolutionAnnotationIndexTests {
    private let versionAxis: [ABIVersionDescriptor] = [
        ABIVersionDescriptor(label: "1.0"),
        ABIVersionDescriptor(label: "2.0"),
    ]

    private var memberLineage: MemberLineage {
        MemberLineage(
            key: .printed("member"),
            kind: .function,
            presence: [true, false],
            events: [LineageEvent(versionIndex: 1, status: .removed)]
        )
    }

    @Test func containerWithPresenceEventsAnnotates() {
        let lineage = ContainerLineage(
            key: .printed("container"),
            name: "Module.Foo",
            containerKind: .type,
            presence: [true, false],
            events: [LineageEvent(versionIndex: 1, status: .removed)],
            memberLineages: []
        )
        let index = EvolutionAnnotationIndex(evolution: ABIEvolution(versions: versionAxis, types: [lineage]))
        let annotation = index.containerAnnotation(forKey: .printed("container"))
        #expect(annotation == EvolutionAnnotation(presence: [true, false], events: lineage.events))
        #expect(index.containerAnnotation(forKey: .printed("absent")) == nil)
    }

    /// A container that exists on every version but has member events still
    /// materializes a lineage — with empty container events. Its header must
    /// stay bare: the signal belongs on the member lines.
    @Test func memberOnlyLineageKeepsTheContainerHeaderBare() {
        let lineage = ContainerLineage(
            key: .printed("container"),
            name: "Module.Foo",
            containerKind: .type,
            presence: [true, true],
            events: [],
            memberLineages: [memberLineage]
        )
        let index = EvolutionAnnotationIndex(evolution: ABIEvolution(versions: versionAxis, types: [lineage]))
        #expect(index.containerAnnotation(forKey: .printed("container")) == nil)
        let annotation = index.memberAnnotation(forContainerKey: .printed("container"), memberKey: .printed("member"))
        #expect(annotation == EvolutionAnnotation(presence: [true, false], events: memberLineage.events))
        #expect(index.memberAnnotation(forContainerKey: .printed("container"), memberKey: .printed("absent")) == nil)
    }

    @Test func globalLineagesResolveByKey() {
        let index = EvolutionAnnotationIndex(evolution: ABIEvolution(versions: versionAxis, globalFunctions: [memberLineage]))
        #expect(index.globalAnnotation(forKey: .printed("member")) != nil)
        #expect(index.globalAnnotation(forKey: .printed("absent")) == nil)
    }
}

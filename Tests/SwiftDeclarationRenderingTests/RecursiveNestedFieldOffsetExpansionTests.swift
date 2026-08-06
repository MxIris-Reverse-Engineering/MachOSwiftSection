import Foundation
import Testing
import MachOKit
import MachOFoundation
@testable import MachOSwiftSection
@_spi(Internals) import SwiftInspection
@testable import SwiftDeclarationRendering
import Demangling
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Regression coverage for the nested expanded-field-offset walk on a **cyclic**
/// field graph.
///
/// `RecursiveIndirectFieldLayout.ReferenceSpec.value` is `ValueSpec<String>?`,
/// and `ValueSpec` has an `indirect case reference(ReferenceSpec)` — so the
/// field graph is a cycle. Before the fix the walk had only a depth limit
/// (`nestedFieldOffsetExpansionDepthLimit`, 16), which bounds how *deep* it
/// goes but not how many *paths* it takes: on a cycle it enumerated every path
/// up to depth 16, which is exponential, and each node cost two to three
/// uncached demangles. `DVTIconKit`'s icon-spec tree (the same shape, found in
/// Xcode's own frameworks) turned that into an apparent hang.
///
/// Two guards now bound it, and both are asserted here:
///
/// 1. An `indirect` case's payload lives in a heap box, so the declared payload
///    type is not laid out at the case's offset — the walk reports the case and
///    stops, exactly as it already does for a class reference. This is also
///    what makes the cycle representable at all, so cutting it is what removes
///    the explosion in practice.
/// 2. A path-scoped set of the types already open above the current node, so a
///    type re-entered on the same path is not expanded again. This is
///    defence-in-depth: a *well-formed* value-type field graph can only cycle
///    through an indirect case (an inline self-reference would be infinitely
///    sized and would not compile), so guard 1 is what fires on this fixture.
///    Guard 2 covers the case where metatype resolution goes wrong on a real
///    binary — `resolveNestedMetatype` has a no-context fallback that can land
///    on a same-named type — and produces a cycle that the source language
///    never permitted.
@Suite(.serialized)
final class RecursiveNestedFieldOffsetExpansionTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {
    /// One parsed line of the rendered expanded-field-offset tree.
    private struct ExpandedLine {
        /// Nesting depth, recovered from the `│   ` / `    ` continuation runs
        /// that `expandedFieldOffsetComment` emits before the `├── ` / `└── `
        /// branch marker.
        let depth: Int
        let fieldName: String
        let typeName: String

        /// Parses `// │   ├── fieldName (Some.Type): 0x10`, returning `nil` for
        /// any line that is not an expanded-field-offset row.
        init?(rawLine: String) {
            guard let markerRange = rawLine.range(of: "├── ") ?? rawLine.range(of: "└── ") else { return nil }
            let beforeMarker = rawLine[rawLine.startIndex ..< markerRange.lowerBound]
            guard let treeStart = beforeMarker.range(of: "// ")?.upperBound else { return nil }
            let continuations = beforeMarker[treeStart...]
            // Every ancestor level contributes exactly four characters.
            guard continuations.count % 4 == 0 else { return nil }
            self.depth = continuations.count / 4

            let body = rawLine[markerRange.upperBound...]
            guard let offsetSeparator = body.range(of: ": 0x", options: .backwards) else { return nil }
            let nameAndType = body[body.startIndex ..< offsetSeparator.lowerBound]
            if let typeOpen = nameAndType.range(of: " (", options: .backwards), nameAndType.hasSuffix(")") {
                self.fieldName = String(nameAndType[nameAndType.startIndex ..< typeOpen.lowerBound])
                self.typeName = String(nameAndType[typeOpen.upperBound ..< nameAndType.index(before: nameAndType.endIndex)])
            } else {
                self.fieldName = String(nameAndType)
                self.typeName = ""
            }
        }
    }

    /// Renders the expanded nested-field-offset tree for one stored field of a
    /// fixture struct, and returns it parsed.
    private func expandedTree(
        forStructNamed structTypeName: String,
        fieldNamed targetFieldName: String
    ) async throws -> [ExpandedLine] {
        var configuration = DeclarationRenderConfiguration.demangleOptions(.default)
        configuration.printFieldOffset = true
        configuration.printExpandedFieldOffsets = true

        let type = try #require(try findFixtureStruct(named: structTypeName), "fixture struct \(structTypeName) not found — rebuild SymbolTestsCore")
        guard case .struct(let structType) = type else {
            Issue.record("\(structTypeName) resolved to a non-struct")
            return []
        }

        let records = try structType.descriptor.fieldDescriptor(in: machOImage).records(in: machOImage)
        let fieldIndex = try #require(
            try records.firstIndex { (try? $0.fieldName(in: machOImage)) == targetFieldName },
            "\(structTypeName) has no stored property named \(targetFieldName)"
        )
        let mangledTypeName = try records[fieldIndex].mangledTypeName(in: machOImage)

        let renderer = FieldLayoutRenderer(type: type, metadata: nil, machO: machOImage, configuration: configuration)
        let rendered = try await renderer.storedFieldComments(
            forFieldAtIndex: fieldIndex,
            mangledTypeName: mangledTypeName,
            fieldOffsets: renderer.fieldOffsets
        )
        return rendered.string.split(separator: "\n", omittingEmptySubsequences: true).compactMap { ExpandedLine(rawLine: String($0)) }
    }

    private func findFixtureStruct(named typeName: String) throws -> TypeContextWrapper? {
        for type in try machOImage.swift.types {
            guard case .struct(let structType) = type, !structType.descriptor.isGeneric else { continue }
            guard let node = try? MetadataReader.demangleContext(for: .type(.struct(structType.descriptor)), in: machOImage) else { continue }
            if node.print(using: .default).hasSuffix(typeName) {
                return type
            }
        }
        return nil
    }

    /// Rebuilds the root-to-node type path for each rendered row from the depth
    /// column, so a repeated type *on one path* can be told apart from the same
    /// type legitimately reached through two different fields.
    private func typePathsAlongTree(_ lines: [ExpandedLine]) -> [[String]] {
        var currentPath: [String] = []
        var allPaths: [[String]] = []
        for line in lines {
            // `depth` counts ancestors; trim back to that many entries before
            // appending this row's own type.
            if currentPath.count > line.depth {
                currentPath.removeLast(currentPath.count - line.depth)
            }
            currentPath.append(line.typeName)
            allPaths.append(currentPath)
        }
        return allPaths
    }

    /// The headline regression: the walk terminates with a small tree instead of
    /// enumerating every path through the cycle.
    ///
    /// Before the fix this produced thousands of rows (and, on `DVTIconKit`'s
    /// larger version of the shape, effectively never finished). The bound is
    /// deliberately loose — the point is the difference between "tens" and
    /// "exponential in the depth limit", not an exact row count.
    @MainActor
    @Test func cyclicFieldGraphExpandsToABoundedTree() async throws {
        let lines = try await expandedTree(forStructNamed: "ReferenceSpec", fieldNamed: "value")

        #expect(!lines.isEmpty, "the field should still expand — the guards must not disable expansion outright")
        #expect(lines.count < 64, "expanded \(lines.count) rows; a cyclic graph must not be walked path-by-path")
        #expect(
            lines.allSatisfy { $0.depth < nestedFieldOffsetExpansionDepthLimit },
            "no row should reach the depth limit — the cycle is cut long before it"
        )
    }

    /// The invariant behind the row count: no type is expanded twice on one
    /// root-to-node path. A type reached through two *different* fields still
    /// expands under both, which is why this checks paths rather than a global
    /// set of seen types.
    @MainActor
    @Test func noTypeRepeatsAlongASinglePath() async throws {
        let lines = try await expandedTree(forStructNamed: "ReferenceSpec", fieldNamed: "value")

        for path in typePathsAlongTree(lines) {
            let named = path.filter { !$0.isEmpty }
            #expect(
                Set(named).count == named.count,
                "type repeats on one path: \(named.joined(separator: " → "))"
            )
        }
    }

    /// Pins guard 1 directly: an `indirect` case is a boxed pointer, so it is
    /// reported as a leaf. `ValueSpec.reference` is the indirect case; if the
    /// walk descended into it, `ReferenceSpec`'s own stored properties
    /// (`name` / `value` / `weight`) would appear underneath it.
    @MainActor
    @Test func indirectEnumCaseIsALeaf() async throws {
        let lines = try await expandedTree(forStructNamed: "ReferenceSpec", fieldNamed: "value")

        let referenceCaseIndex = try #require(
            lines.firstIndex { $0.fieldName == "reference" },
            "the indirect case should still be reported, just not descended into; got \(lines.map(\.fieldName))"
        )
        let referenceCase = lines[referenceCaseIndex]
        let nextLine = lines[lines.index(after: referenceCaseIndex)...].first
        #expect(
            nextLine.map { $0.depth <= referenceCase.depth } ?? true,
            "the indirect case has children — its boxed payload was walked as if laid out inline"
        )
    }

    /// The complement: the guards must not clip an ordinary deep-but-acyclic
    /// type. `AcyclicNesting.inner` is three levels of plain structs.
    @MainActor
    @Test func acyclicNestingStillFullyExpands() async throws {
        let lines = try await expandedTree(forStructNamed: "AcyclicNesting", fieldNamed: "inner")

        #expect(lines.contains { $0.fieldName == "innermost" }, "got \(lines.map(\.fieldName))")
        #expect(lines.contains { $0.fieldName == "value" }, "got \(lines.map(\.fieldName))")
        #expect(lines.contains { $0.fieldName == "flag" }, "got \(lines.map(\.fieldName))")
        #expect((lines.map(\.depth).max() ?? 0) >= 2, "nesting was clipped: \(lines.map { "\($0.depth):\($0.fieldName)" })")
    }
}

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

/// The in-process nested field-offset expansion reads byte for byte the same
/// with its per-metatype memo as without it (evolution proposal
/// `nested-field-offset-memoization`).
///
/// The memo keeps, per metatype, what one level of the walk reads — each
/// row's field name, type name and relative offset, the metatype one level
/// down, and whether the row draws the closing branch — and the walk keeps
/// everything positional. The fixture's `RecursiveIndirectFieldLayout` carries
/// every shape that could tell the two apart: a cycle, `indirect` payloads,
/// and `ValueSpec<String>`'s last payload case `pair`, whose type does not
/// resolve, so the row before it keeps its `├──` although nothing follows.
@Suite(.serialized)
final class NestedFieldOffsetMemoizationTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {
    private struct FirstProbe {}

    private struct SecondProbe {}

    /// Every stored field of every non-generic struct and class in the
    /// fixture, rendered in process with field offsets, expanded field
    /// offsets and type layouts on.
    private func renderEveryStoredField() async throws -> [(label: String, rendered: String)] {
        var configuration = DeclarationRenderConfiguration.demangleOptions(.default)
        configuration.printFieldOffset = true
        configuration.printExpandedFieldOffsets = true
        configuration.printTypeLayout = true

        var renderings: [(label: String, rendered: String)] = []
        for (typeIndex, type) in try machOImage.swift.types.enumerated() {
            let fieldDescriptor: FieldDescriptor
            switch type {
            case .struct(let structType):
                guard !structType.descriptor.isGeneric else { continue }
                fieldDescriptor = try structType.descriptor.fieldDescriptor(in: imageContext)
            case .class(let classType):
                guard !classType.descriptor.isGeneric else { continue }
                fieldDescriptor = try classType.descriptor.fieldDescriptor(in: imageContext)
            case .enum:
                continue
            }
            let renderer = FieldLayoutRenderer(type: type, metadata: nil, machO: machOImage, configuration: configuration)
            let fieldOffsets = renderer.fieldOffsets
            for (fieldIndex, record) in try fieldDescriptor.records(in: imageContext).enumerated() {
                let mangledTypeName = try record.mangledTypeName(in: imageContext)
                let rendered = try await renderer.storedFieldComments(forFieldAtIndex: fieldIndex, mangledTypeName: mangledTypeName, fieldOffsets: fieldOffsets)
                let fieldName = (try? record.fieldName(in: imageContext)) ?? "#\(fieldIndex)"
                renderings.append(("type \(typeIndex) field \(fieldName)", rendered.string))
            }
        }
        return renderings
    }

    private static func mismatches(between expected: [(label: String, rendered: String)], and actual: [(label: String, rendered: String)]) -> [String] {
        guard expected.count == actual.count else {
            return ["rendered \(actual.count) fields, expected \(expected.count)"]
        }
        return zip(expected, actual).compactMap { expectedRendering, actualRendering in
            expectedRendering.rendered == actualRendering.rendered ? nil : "\(expectedRendering.label):\n\(actualRendering.rendered)\n--- expected ---\n\(expectedRendering.rendered)"
        }
    }

    @Test func memoizedExpansionReadsAsTheUnmemoizedOne() async throws {
        RuntimeFieldLayoutMemo.removeAll()
        let unmemoized = try await NestedFieldOffsetLevelMemo.$isBypassed.withValue(true) {
            try await renderEveryStoredField()
        }
        // The first pass builds the levels, the second reads them all back.
        let firstMemoized = try await renderEveryStoredField()
        let secondMemoized = try await renderEveryStoredField()

        let expandedRowCount = unmemoized.reduce(0) { count, rendering in
            count + rendering.rendered.components(separatedBy: "── ").count - 1
        }
        #expect(expandedRowCount > 100, "the fixture should expand plenty of nested rows; got \(expandedRowCount)")
        let mismatches = Self.mismatches(between: unmemoized, and: firstMemoized) + Self.mismatches(between: unmemoized, and: secondMemoized)
        #expect(mismatches.isEmpty, "\(mismatches.prefix(3).joined(separator: "\n\n"))")
    }

    /// The row before an unresolved last payload keeps the branch it drew
    /// without the memo, read from a cold memo and from a warm one alike.
    @Test func aRowBeforeAnUnresolvedLastPayloadKeepsItsOpenBranch() async throws {
        RuntimeFieldLayoutMemo.removeAll()
        let unmemoized = try await NestedFieldOffsetLevelMemo.$isBypassed.withValue(true) {
            try await renderEveryStoredField()
        }
        let memoized = try await renderEveryStoredField()
        let referenceRows = unmemoized.flatMap { rendering in
            rendering.rendered.split(separator: "\n").filter { $0.contains("── reference (") }
        }
        #expect(!referenceRows.isEmpty, "ValueSpec<String>.reference should be expanded somewhere in the fixture")
        #expect(referenceRows.allSatisfy { $0.contains("├── reference (") }, "\(referenceRows)")
        #expect(Self.mismatches(between: unmemoized, and: memoized).isEmpty)
    }

    @Test func aLevelIsBuiltOnceUntilTheMemoIsCleared() {
        RuntimeFieldLayoutMemo.removeAll()
        var buildCount = 0
        let build: () -> NestedFieldOffsetLevel = {
            buildCount += 1
            return .notExpanded
        }
        _ = NestedFieldOffsetLevelMemo.level(for: FirstProbe.self, building: build)
        _ = NestedFieldOffsetLevelMemo.level(for: FirstProbe.self, building: build)
        #expect(buildCount == 1)

        RuntimeFieldLayoutMemo.removeAll()
        _ = NestedFieldOffsetLevelMemo.level(for: FirstProbe.self, building: build)
        #expect(buildCount == 2)
    }

    /// A host that loads an image while a level is being built clears the
    /// memo in between; the level built from the old state must not land in
    /// the cleared memo.
    @Test func aLevelBuiltAcrossRemoveAllIsNotStored() {
        RuntimeFieldLayoutMemo.removeAll()
        var buildCount = 0
        _ = NestedFieldOffsetLevelMemo.level(for: SecondProbe.self) {
            buildCount += 1
            RuntimeFieldLayoutMemo.removeAll()
            return .notExpanded
        }
        _ = NestedFieldOffsetLevelMemo.level(for: SecondProbe.self) {
            buildCount += 1
            return .notExpanded
        }
        #expect(buildCount == 2)
    }
}

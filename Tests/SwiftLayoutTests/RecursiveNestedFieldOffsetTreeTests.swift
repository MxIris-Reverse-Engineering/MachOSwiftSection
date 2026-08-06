import Foundation
import Testing
import MachOKit
import MachOFoundation
@testable import MachOSwiftSection
@_spi(Internals) import SwiftInspection
@testable import SwiftLayout
@testable import MachOTestingSupport
import MachOFixtureSupport
import Demangling

/// The static (offline) counterpart of
/// `RecursiveNestedFieldOffsetExpansionTests`: `nestedFieldOffsetTree` walks the
/// same cyclic field graph through descriptors instead of in-process metadata,
/// and carried the same two defects — no cycle guard, and it descended into an
/// `indirect` case's boxed payload as if it were laid out inline.
///
/// Kept as a separate suite rather than folded into the runtime one because the
/// two engines share no code: the runtime walk keys its guard on `Any.Type`
/// identity, the static walk on the printed type name (so that `Box<Int>` and
/// `Box<String>` stay distinct). Both need their own regression.
@Suite
final class RecursiveNestedFieldOffsetTreeTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {
    private func nestedTree(
        forStructNamed qualifiedTypeName: String,
        fieldNamed targetFieldName: String
    ) throws -> [NestedFieldOffset] {
        let machO = machOFile
        let calculator = try StaticLayoutCalculator(machO: machO)

        for contextDescriptor in try machO.swift.contextDescriptors {
            guard let descriptor = contextDescriptor.typeContextDescriptorWrapper, descriptor.isStruct else { continue }
            guard
                let name = (try? MetadataReader.demangleContext(for: contextDescriptor, in: machO))
                    .flatMap(NodeTypeNaming.nominalQualifiedName(of:)),
                name == qualifiedTypeName
            else { continue }

            let records = try descriptor.typeContextDescriptor.fieldDescriptor(in: machO).records(in: machO)
            let record = try #require(
                records.first { (try? $0.fieldName(in: machO)) == targetFieldName },
                "\(qualifiedTypeName) has no stored property named \(targetFieldName)"
            )
            let mangledTypeName = try record.mangledTypeName(in: machO)
            return calculator.nestedFieldOffsetTree(
                forMangledTypeName: mangledTypeName,
                baseOffset: 0,
                depthLimit: 16
            )
        }
        Issue.record("fixture struct \(qualifiedTypeName) not found — rebuild SymbolTestsCore")
        return []
    }

    private func flattened(_ nodes: [NestedFieldOffset]) -> [NestedFieldOffset] {
        nodes.flatMap { [$0] + flattened($0.children) }
    }

    /// Walks every root-to-node type path, so a type repeated *on one path* is
    /// distinguishable from the same type legitimately reached through two
    /// different fields.
    private func typePathsAlongTree(_ nodes: [NestedFieldOffset], prefix: [String] = []) -> [[String]] {
        nodes.flatMap { node -> [[String]] in
            let path = prefix + [node.typeName]
            return [path] + typePathsAlongTree(node.children, prefix: path)
        }
    }

    @Test func cyclicFieldGraphBuildsABoundedTree() throws {
        let tree = try nestedTree(
            forStructNamed: "SymbolTestsCore.RecursiveIndirectFieldLayout.ReferenceSpec",
            fieldNamed: "direct"
        )
        let allNodes = flattened(tree)

        #expect(!allNodes.isEmpty, "the field should still expand — the guards must not disable expansion outright")
        #expect(allNodes.count < 64, "built \(allNodes.count) nodes; a cyclic graph must not be walked path-by-path")
    }

    @Test func noTypeRepeatsAlongASinglePath() throws {
        let tree = try nestedTree(
            forStructNamed: "SymbolTestsCore.RecursiveIndirectFieldLayout.ReferenceSpec",
            fieldNamed: "direct"
        )

        for path in typePathsAlongTree(tree) {
            let named = path.filter { !$0.isEmpty }
            #expect(
                Set(named).count == named.count,
                "type repeats on one path: \(named.joined(separator: " → "))"
            )
        }
    }

    /// An `indirect` case's payload is a heap box reference, so the case is a
    /// leaf — descending into it would place `ReferenceSpec`'s stored properties
    /// at offsets where the box pointer actually lives.
    @Test func indirectEnumCaseIsALeaf() throws {
        let tree = try nestedTree(
            forStructNamed: "SymbolTestsCore.RecursiveIndirectFieldLayout.ReferenceSpec",
            fieldNamed: "direct"
        )

        let referenceCase = try #require(
            flattened(tree).first { $0.fieldName == "reference" },
            "the indirect case should still be reported, just not descended into; got \(flattened(tree).map(\.fieldName))"
        )
        #expect(
            referenceCase.children.isEmpty,
            "the indirect case has children — its boxed payload was walked as if laid out inline"
        )
    }

    /// The guards must not clip an ordinary deep-but-acyclic type.
    @Test func acyclicNestingStillFullyExpands() throws {
        let tree = try nestedTree(
            forStructNamed: "SymbolTestsCore.RecursiveIndirectFieldLayout.AcyclicNesting",
            fieldNamed: "inner"
        )
        let fieldNames = flattened(tree).map(\.fieldName)

        #expect(fieldNames.contains("innermost"), "got \(fieldNames)")
        #expect(fieldNames.contains("value"), "got \(fieldNames)")
        #expect(fieldNames.contains("flag"), "got \(fieldNames)")
    }
}

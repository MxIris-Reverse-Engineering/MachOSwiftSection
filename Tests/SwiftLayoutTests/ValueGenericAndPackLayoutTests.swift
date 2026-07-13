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

/// Validates value-generic (SE-0452) and parameter-pack (SE-0393) layout
/// resolution: non-generic holders whose fields are concrete instantiations of
/// variadic (`VariadicPack<Int32, Int8, Int64>`) and value-generic
/// (`ValueGenericBuffer<5>`, `InlineArray<3, Int64>`) types must resolve
/// *fully* (no field degrades to `unknown`) and match the runtime field-offset
/// vector, on both the in-process and the offline (`MachOFile`) reader.
@Suite
final class ValueGenericAndPackLayoutTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {

    /// Holders whose every field the static engine must fully compute, keyed
    /// by short name under `SymbolTestsCore.GenericFieldLayout`.
    private static let fullyResolvingHolders = [
        "PackExpansionFieldHolder",
        "MixedPackFieldHolder",
        "PackForwardingFieldHolder",
        "FixedArrayPayloadEnumFieldHolder",
        "ValueGenericFieldHolder",
        "TupleExtraInhabitantFieldHolder",
    ]

    @MainActor
    @Test func valueGenericAndPackFieldHoldersFullyResolveAndMatchRuntime() async throws {
        let machO = machOImage
        let calculator = try StaticLayoutCalculator(machO: machO)
        let fileCalculator = try StaticLayoutCalculator(machO: machOFile)

        for shortName in Self.fullyResolvingHolders {
            let qualifiedTypeName = "SymbolTestsCore.GenericFieldLayout.\(shortName)"
            let aggregate = try fieldLayout(ofQualifiedTypeName: qualifiedTypeName, with: calculator, in: machO)
            let runtimeOffsets = try #require(
                try runtimeFieldOffsets(ofQualifiedTypeName: qualifiedTypeName, in: machO),
                "no runtime field-offset vector for \(qualifiedTypeName)"
            )
            assertFullyComputed(aggregate, equals: runtimeOffsets, typeName: qualifiedTypeName)

            // Offline parity: the `MachOFile` reader — the path `swift-section
            // dump` takes — must compute the identical vector.
            let fileAggregate = try fieldLayout(ofQualifiedTypeName: qualifiedTypeName, with: fileCalculator, in: machOFile)
            assertFullyComputed(fileAggregate, equals: runtimeOffsets, typeName: "\(qualifiedTypeName) (MachOFile)")
        }
    }

    /// Top-level concrete instantiation with a *value* argument:
    /// `ValueGenericBuffer<5>`. Runtime metadata for a value-generic
    /// instantiation cannot be materialized through the metatype-only accessor
    /// helper, so the expected offsets are literals verified against
    /// `MemoryLayout` externally: `storage` (`InlineArray<5, Int8>`, five
    /// bytes) at 0, `tail` (`Int32`, 4-aligned) at 8, whole type 12 bytes.
    @MainActor
    @Test func topLevelValueGenericInstantiationComputesFieldOffsets() async throws {
        let machO = machOImage
        let calculator = try StaticLayoutCalculator(machO: machO)

        let valueArgument = Node.create(kind: .type, child: Node.create(kind: .integer, index: 5))
        let aggregate = try fieldLayout(
            ofGenericQualifiedTypeName: "SymbolTestsCore.GenericFieldLayout.ValueGenericBuffer",
            genericArguments: [valueArgument],
            with: calculator,
            in: machO
        )
        assertFullyComputed(aggregate, equals: [0, 8], typeName: "ValueGenericBuffer<5>")
        #expect(aggregate.size == 12)
        #expect(aggregate.alignment == 4)
    }

    /// Top-level concrete instantiation with a *pack* argument:
    /// `VariadicPack<Int32, Int8, Int64>`. Its single stored property is the
    /// expanded tuple `(Int32, Int8, Int64)` — offsets 0/4/8 within the tuple,
    /// 16 bytes total.
    @MainActor
    @Test func topLevelPackInstantiationComputesFieldOffsets() async throws {
        let machO = machOImage
        let calculator = try StaticLayoutCalculator(machO: machO)

        let packArgument = Node.create(kind: .type, child: Node.create(kind: .pack, children: [
            swiftStructureType(named: "Int32"),
            swiftStructureType(named: "Int8"),
            swiftStructureType(named: "Int64"),
        ]))
        let aggregate = try fieldLayout(
            ofGenericQualifiedTypeName: "SymbolTestsCore.GenericFieldLayout.VariadicPack",
            genericArguments: [packArgument],
            with: calculator,
            in: machO
        )
        assertFullyComputed(aggregate, equals: [0], typeName: "VariadicPack<Int32, Int8, Int64>")
        #expect(aggregate.size == 16)
        #expect(aggregate.alignment == 8)
    }

    /// A bare variadic generic type (no arguments supplied) stays degraded:
    /// the pack expansion's arity is unknowable without an instantiation.
    @MainActor
    @Test func bareVariadicGenericTypeDegradesPackFields() async throws {
        let machO = machOImage
        let calculator = try StaticLayoutCalculator(machO: machO)

        let aggregate = try fieldLayout(
            ofQualifiedTypeName: "SymbolTestsCore.GenericFieldLayout.VariadicPack",
            with: calculator,
            in: machO
        )
        let unresolved = aggregate.fields.contains { field in
            if case .unknown = field.resolution { return true }
            return false
        }
        #expect(unresolved, "a bare pack parameter must leave the expanded tuple field unknown")
    }

    // MARK: - Node builders

    private func swiftStructureType(named typeName: String) -> Node {
        Node.create(kind: .type, child: Node.create(kind: .structure, children: [
            Node.create(kind: .module, text: "Swift"),
            Node.create(kind: .identifier, text: typeName),
        ]))
    }
}

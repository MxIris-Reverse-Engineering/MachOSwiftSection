import Foundation
import Testing
import MachOKit
import MachOFoundation
@testable import MachOSwiftSection
@_spi(Internals) import SwiftInspection
@testable import SwiftLayout
@testable import MachOTestingSupport
import Demangling

/// Validates concrete same-type pinning: a generic parameter pinned to a
/// concrete type by a **constrained extension** (`extension Foo where Value ==
/// Date`) is resolved from the requirement signature alone — a type nested in
/// such an extension inherits the `Value == …` requirement, so a field typed by
/// the parameter lays out as the pinned concrete type **without any argument**.
///
/// Because a same-type-to-concrete parameter is dropped from the metadata
/// accessor's key arguments (it is fully determined), the no-argument runtime
/// field-offset vector is clean ground truth. Both readers are checked.
@Suite
final class SameTypePinnedParameterLayoutTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {

    /// A parameter pinned to a **scalar** concrete type (`Value == Int64`)
    /// resolves in a single-image scope — `Int64` needs no cross-module
    /// descriptor.
    @MainActor
    @Test func scalarPinnedParameterResolvesSingleImage() async throws {
        let machO = machOImage
        let qualifiedTypeName = "SymbolTestsCore.GenericFieldLayout.SameTypePinnedOuter.ScalarPinnedInner"
        let runtimeOffsets = try #require(
            try runtimeFieldOffsets(ofQualifiedTypeName: qualifiedTypeName, in: machO),
            "no runtime field-offset vector for \(qualifiedTypeName)"
        )

        let calculator = try StaticLayoutCalculator(machO: machO)
        let aggregate = try fieldLayout(ofQualifiedTypeName: qualifiedTypeName, with: calculator, in: machO)
        assertFullyComputed(aggregate, equals: runtimeOffsets, typeName: qualifiedTypeName)
        // The pinned field resolved to Int64 (8 bytes), not degraded.
        #expect(aggregate.fields.first?.layout?.size == 8, "pinnedValue must resolve to Int64 (8 bytes)")

        let fileCalculator = try StaticLayoutCalculator(machO: machOFile)
        let fileAggregate = try fieldLayout(ofQualifiedTypeName: qualifiedTypeName, with: fileCalculator, in: machOFile)
        assertFullyComputed(fileAggregate, equals: runtimeOffsets, typeName: "\(qualifiedTypeName) (MachOFile)")
    }

    /// A parameter pinned to a **bound-generic concrete** type (`Value ==
    /// Range<Int>`) resolves once the stdlib descriptor is reachable — the
    /// same-type substitution feeds a full concrete type node, laid out through
    /// the dependency closure.
    @MainActor
    @Test func boundGenericPinnedParameterResolvesThroughClosure() async throws {
        let machO = machOImage
        let qualifiedTypeName = "SymbolTestsCore.GenericFieldLayout.SameTypePinnedOuter.RangePinnedInner"
        let runtimeOffsets = try #require(
            try runtimeFieldOffsets(ofQualifiedTypeName: qualifiedTypeName, in: machO),
            "no runtime field-offset vector for \(qualifiedTypeName)"
        )

        let universe = try ImageUniverse.dependencyClosure(root: machO)
        let calculator = StaticLayoutCalculator(imageUniverse: universe)
        let aggregate = try fieldLayout(ofQualifiedTypeName: qualifiedTypeName, with: calculator, in: machO)
        assertFullyComputed(aggregate, equals: runtimeOffsets, typeName: qualifiedTypeName)
        // The pinned field resolved to Range<Int> (16 bytes).
        #expect(aggregate.fields[safe: 1]?.layout?.size == 16, "pinnedRange must resolve to Range<Int> (16 bytes)")
    }

    /// The analysis pins only a parameter whose same-type RHS is fully concrete.
    /// A `Value` left free (no same-type requirement) still degrades — the pin
    /// is not invented.
    @MainActor
    @Test func freeParameterWithoutPinStillDegrades() async throws {
        let machO = machOImage
        let calculator = try StaticLayoutCalculator(machO: machO)
        // `SameTypePinnedOuter<Value>` itself: `anchor: Value` is unconstrained
        // at the top level → degrades.
        let aggregate = try fieldLayout(
            ofQualifiedTypeName: "SymbolTestsCore.GenericFieldLayout.SameTypePinnedOuter",
            with: calculator,
            in: machO
        )
        let anchorField = try #require(aggregate.fields.first)
        guard case .unknown = anchorField.resolution else {
            Issue.record("an unpinned free parameter field must degrade, got \(anchorField.resolution)")
            return
        }
    }
}

import Foundation
import Testing
import MachOKit
import MachOFoundation
@testable import MachOSwiftSection
@_spi(Internals) import SwiftInspection
@testable import SwiftLayout
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Pins the exact field-offset vectors the existential and default-actor layout
/// support must produce, with literal expected values, so a regression in the
/// container-size formulas (opaque `32 + 8N`, class-bound `8 * (1 + N)`,
/// existential metatype, `any Error`, the 96-byte default-actor storage) is
/// caught with a precise message — independently of the broad runtime-prefix
/// suite. The values are the runtime field-offset vectors verified in
/// `StaticLayoutVsRuntimeTests`.
@Suite
final class ExistentialLayoutTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {

    /// Fully-qualified type name → the complete, fully-computed field-offset
    /// vector. Every type here must resolve with no `unknown` fields.
    private static let expectedFieldOffsets: [String: [Int]] = [
        // Opaque existentials (40 = 32 + 8·1), `Optional<any P>` (still 40),
        // `Array`/`Dictionary` of existential (one pointer), existential closure.
        "SymbolTestsCore.ExistentialAny.ExistentialFieldTest": [0, 40, 80, 120, 128, 136],
        // Class-bound existential (16 = 8·(1 + 1)) then `AnyObject` (8 = 8·1).
        "SymbolTestsCore.ExistentialAny.ExistentialClassBoundTest": [0, 16],
        // 2-protocol opaque (48), 3-protocol opaque (56), class-bound (16),
        // `& Sendable` (marker stripped → opaque 40).
        "SymbolTestsCore.ProtocolComposition.ProtocolCompositionFieldTest": [0, 48, 104, 120],
        // Thin concrete metatype (0), `Any.Type` (8), `P.Type` (16), `AnyObject.Type` (8).
        "SymbolTestsCore.MetatypeUsage.MetatypeFieldTest": [0, 0, 8, 24],
        // Reference-storage fields ending in two `AnyObject` (class-bound, 8 each).
        "SymbolTestsCore.FieldDescriptorVariants.ReferenceFieldTest": [16, 24, 32, 40, 48, 56, 64, 72],
        // Default-actor storage (96 bytes, 16-aligned at offset 16) + a stored Int.
        "SymbolTestsCore.Actors.ActorTest": [16, 112],
        "SymbolTestsCore.Actors.CustomGlobalActor": [16],
        "SymbolTestsCore.DeinitVariants.ActorDeinitTest": [16, 112],
        "SymbolTestsCore.Initializers.AsyncInitializerActorTest": [16, 112],
    ]

    @MainActor
    @Test func existentialAndActorFieldOffsetsMatchExpected() async throws {
        let machO = machOImage
        let calculator = try StaticLayoutCalculator(machO: machO)
        var checkedTypeNames: Set<String> = []

        for contextDescriptor in try machO.swift.contextDescriptors {
            guard let descriptor = contextDescriptor.typeContextDescriptorWrapper else { continue }
            guard descriptor.isStruct || descriptor.isClass else { continue }
            guard
                let qualifiedTypeName = (try? MetadataReader.demangleContext(for: contextDescriptor, in: machO))
                    .flatMap(NodeTypeNaming.nominalQualifiedName(of:)),
                let expectedOffsets = Self.expectedFieldOffsets[qualifiedTypeName]
            else { continue }

            let aggregate = try calculator.fieldLayout(of: descriptor)
            let isFullyComputed = aggregate.fields.allSatisfy {
                if case .computed = $0.resolution { return true } else { return false }
            }
            #expect(isFullyComputed, "\(qualifiedTypeName) should fully resolve (no unknown fields)")
            #expect(
                aggregate.computedFieldOffsets == expectedOffsets,
                "\(qualifiedTypeName): got \(aggregate.computedFieldOffsets), expected \(expectedOffsets)"
            )
            checkedTypeNames.insert(qualifiedTypeName)
        }

        let missing = Set(Self.expectedFieldOffsets.keys).subtracting(checkedTypeNames)
        #expect(missing.isEmpty, "fixture types not found in the binary: \(missing.sorted())")
    }
}

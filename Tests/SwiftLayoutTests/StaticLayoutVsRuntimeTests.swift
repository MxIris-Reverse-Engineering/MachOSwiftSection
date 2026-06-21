import Foundation
import Testing
import MachOKit
import MachOFoundation
@testable import MachOSwiftSection
@_spi(Internals) import SwiftInspection
@testable import SwiftLayout
@testable import MachOTestingSupport
import MachOFixtureSupport

/// The core correctness suite: for every non-generic struct/class defined in
/// the fixture module, materialize the runtime field-offset vector via the
/// metadata accessor (the ground truth) and assert the static engine — which
/// never calls that accessor — recomputes it offset-for-offset.
///
/// Where a type contains a field the single-image engine does not yet resolve
/// (existential, an actor's default storage, a cross-module resilient type),
/// that field and everything after it degrade to `unknown`; the suite then
/// asserts the *computed prefix* still matches the runtime prefix exactly.
@Suite
final class StaticLayoutVsRuntimeTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {

    private struct Mismatch: CustomStringConvertible {
        let typeName: String
        let runtimeOffsets: [Int]
        let staticOffsets: [Int]
        let unresolvedReasons: [String]
        var description: String {
            "\(typeName): runtime=\(runtimeOffsets) static=\(staticOffsets)"
                + (unresolvedReasons.isEmpty ? "" : " unresolved=\(unresolvedReasons)")
        }
    }

    @MainActor
    @Test func staticStructAndClassOffsetsMatchRuntime() async throws {
        let machO = machOImage
        let calculator = try StaticLayoutCalculator(machO: machO)

        var comparedCount = 0
        var fullyComputedCount = 0
        var mismatches: [Mismatch] = []

        for contextDescriptor in try machO.swift.contextDescriptors {
            guard let descriptor = contextDescriptor.typeContextDescriptorWrapper else { continue }
            guard !descriptor.typeContextDescriptor.layout.flags.isGeneric else { continue }
            guard descriptor.isStruct || descriptor.isClass else { continue }

            // Single-image scope: only validate types defined in the fixture
            // module. Cross-module C-imported types (e.g. `__C.Decimal`, whose
            // C bitfield layout is not reflected in Swift field records) are out
            // of scope until the dependency-closure phase.
            guard
                let qualifiedTypeName = (try? MetadataReader.demangleContext(for: contextDescriptor, in: machO))
                    .flatMap(NodeTypeNaming.nominalQualifiedName(of:)),
                qualifiedTypeName.hasPrefix("SymbolTests")
            else { continue }

            // Ground truth: the runtime field-offset vector via the metadata
            // accessor.
            guard let accessor = try descriptor.typeContextDescriptor.metadataAccessorFunction(in: machO) else { continue }
            let runtimeOffsets: [Int]
            do {
                let response = try accessor(request: .init())
                let metadata = try response.value.resolve(in: machO)
                switch metadata {
                case .struct(let structMetadata):
                    runtimeOffsets = try structMetadata.fieldOffsets(in: machO).map { Int($0) }
                case .class(let classMetadata):
                    runtimeOffsets = try classMetadata.fieldOffsets(in: machO).map { Int($0) }
                default:
                    continue
                }
            } catch {
                // Metadata that cannot be materialized in this process is not
                // something the static engine is expected to match.
                continue
            }

            let aggregate = try calculator.fieldLayout(of: descriptor)
            let staticOffsets = aggregate.computedFieldOffsets
            let isFullyComputed = aggregate.fields.allSatisfy {
                if case .computed = $0.resolution { return true } else { return false }
            }
            let unresolvedReasons: [String] = aggregate.fields.compactMap { field in
                if case .unknown(let reason) = field.resolution { return "\(field.fieldName):\(reason)" }
                return nil
            }

            comparedCount += 1
            if isFullyComputed { fullyComputedCount += 1 }

            // The computed prefix must always equal the runtime prefix.
            let runtimePrefix = Array(runtimeOffsets.prefix(staticOffsets.count))
            if staticOffsets != runtimePrefix {
                let typeName = (try? descriptor.typeContextDescriptor.name(in: machO)) ?? qualifiedTypeName
                mismatches.append(Mismatch(
                    typeName: typeName,
                    runtimeOffsets: runtimeOffsets,
                    staticOffsets: staticOffsets,
                    unresolvedReasons: unresolvedReasons
                ))
            }
        }

        // Guard against a silently-empty run (e.g. all types degrading and
        // passing vacuously): the fixture module has many fully-resolvable
        // struct/class types.
        #expect(comparedCount > 100, "expected to compare many fixture types, got \(comparedCount)")
        // With existential, existential-metatype and default-actor storage now
        // resolved, only ObjC-ancestor / cross-module-resilient types remain
        // unresolved (a handful). Floor set to lock that gain in.
        #expect(fullyComputedCount > 128, "expected most fixture types to fully resolve, got \(fullyComputedCount)")
        #expect(
            mismatches.isEmpty,
            Comment(rawValue: "field-offset mismatches:\n" + mismatches.map(\.description).joined(separator: "\n"))
        )
    }
}

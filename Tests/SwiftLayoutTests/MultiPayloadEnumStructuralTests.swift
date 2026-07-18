import Foundation
import Testing
import MachOKit
import MachOFoundation
@testable import MachOSwiftSection
@_spi(Internals) import SwiftInspection
@testable import SwiftLayout
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Validates the structural multi-payload enum path (the fallback reached when no
/// `__swift5_builtin` whole-type descriptor exists). The resolver prefers the
/// builtin descriptor, so this exercises `multiPayloadEnumLayout` directly and
/// checks its size/stride/extra-inhabitant count against the runtime
/// value-witness table — the same values the builtin path would return, proving
/// the structural computation is a correct fallback. The extra-inhabitant check
/// is also driven end-to-end: `Optional<MPE>` must spend an inhabitant instead
/// of appending a tag byte, so the statically-wrapped optional's size/stride is
/// compared against the live `MemoryLayout<MPE?>`.
@Suite
final class MultiPayloadEnumStructuralTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {

    @MainActor
    @Test func structuralMultiPayloadLayoutMatchesRuntime() async throws {
        let machO = machOImage
        let universe = try ImageUniverse.dependencyClosure(root: machO)
        let resolver = StaticTypeLayoutResolver(imageUniverse: universe)

        var comparedCount = 0
        var unresolvedNames: [String] = []

        for contextDescriptor in try machO.swift.contextDescriptors {
            guard
                let descriptor = contextDescriptor.typeContextDescriptorWrapper,
                let enumDescriptor = descriptor.enum,
                enumDescriptor.numberOfPayloadCases > 1
            else { continue }
            guard
                let node = try? MetadataReader.demangleContext(for: contextDescriptor, in: machO),
                let qualifiedTypeName = NodeTypeNaming.nominalQualifiedName(of: node),
                qualifiedTypeName.hasPrefix("SymbolTests")
            else { continue }

            // The structural method may legitimately fail to resolve a payload
            // (e.g. a generic parameter); only assert on the ones it can compute.
            let structural: StaticTypeLayout
            do {
                structural = try resolver.multiPayloadEnumLayout(enumDescriptor, node: node, in: universe.rootImage)
            } catch {
                unresolvedNames.append(qualifiedTypeName)
                continue
            }
            guard let runtime = try runtimeValueWitnessLayout(ofQualifiedTypeName: qualifiedTypeName, in: machO) else { continue }

            comparedCount += 1
            #expect(
                structural.size == runtime.size,
                "\(qualifiedTypeName): structural size \(structural.size) != runtime \(runtime.size)"
            )
            #expect(
                structural.stride == runtime.stride,
                "\(qualifiedTypeName): structural stride \(structural.stride) != runtime \(runtime.stride)"
            )
            #expect(
                structural.extraInhabitantCount == runtime.extraInhabitantCount,
                "\(qualifiedTypeName): structural extra inhabitants \(structural.extraInhabitantCount) != runtime \(runtime.extraInhabitantCount)"
            )

            // End-to-end: wrapping the structural layout in `Optional` must
            // agree with the live runtime `Optional<MPE>` — a wrong extra
            // inhabitant count would add (or omit) a tag byte here.
            let staticOptional = StaticTypeLayoutResolver<MachOImage>.singlePayloadEnumLayout(
                payload: structural,
                emptyCaseCount: 1
            )
            let metatype = try #require(
                try runtimeMetatype(ofQualifiedTypeName: qualifiedTypeName, in: machO),
                "no runtime metatype for \(qualifiedTypeName)"
            )
            let runtimeOptional = optionalSizeStride(wrapping: metatype)
            #expect(
                staticOptional.size == runtimeOptional.size,
                "Optional<\(qualifiedTypeName)>: static size \(staticOptional.size) != runtime \(runtimeOptional.size)"
            )
            #expect(
                staticOptional.stride == runtimeOptional.stride,
                "Optional<\(qualifiedTypeName)>: static stride \(staticOptional.stride) != runtime \(runtimeOptional.stride)"
            )
        }

        #expect(comparedCount >= 3, "expected several fixture multi-payload enums to compute structurally, got \(comparedCount) (unresolved: \(unresolvedNames))")
    }

    /// `MemoryLayout` of `Optional<Wrapped>` for a metatype only known at
    /// runtime, opened generically.
    private func optionalSizeStride(wrapping metatype: Any.Type) -> (size: Int, stride: Int) {
        func measure<Wrapped>(_: Wrapped.Type) -> (size: Int, stride: Int) {
            (MemoryLayout<Wrapped?>.size, MemoryLayout<Wrapped?>.stride)
        }
        return _openExistential(metatype, do: measure(_:))
    }
}

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
/// checks its size/stride against the runtime value-witness table — the same
/// value the builtin path would return, proving the structural computation is a
/// correct fallback.
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
            let structural: TypeLayoutInfo
            do {
                structural = try resolver.multiPayloadEnumLayout(enumDescriptor, node: node, in: universe.rootImage)
            } catch {
                unresolvedNames.append(qualifiedTypeName)
                continue
            }
            guard let runtime = try runtimeValueWitnessSizeStride(ofQualifiedTypeName: qualifiedTypeName, in: machO) else { continue }

            comparedCount += 1
            #expect(
                structural.size == runtime.size,
                "\(qualifiedTypeName): structural size \(structural.size) != runtime \(runtime.size)"
            )
            #expect(
                structural.stride == runtime.stride,
                "\(qualifiedTypeName): structural stride \(structural.stride) != runtime \(runtime.stride)"
            )
        }

        #expect(comparedCount >= 3, "expected several fixture multi-payload enums to compute structurally, got \(comparedCount) (unresolved: \(unresolvedNames))")
    }
}

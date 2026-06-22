import Foundation
import Testing
import MachOKit
import MachOFoundation
@testable import MachOSwiftSection
@_spi(Internals) import SwiftInspection
@testable import SwiftLayout
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Validates that `__swift5_builtin` `BuiltinTypeDescriptor` records back the
/// layouts of types the structural engine cannot derive — multi-payload enums
/// and imported C value types — both in the index itself and through the
/// resolver, cross-checked against the runtime value-witness table.
@Suite
final class BuiltinTypeLayoutTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {

    /// Multi-payload (and indirect / raw `@objc`) enums the fixture defines;
    /// these have a builtin descriptor and are degraded by the structural path.
    private static let multiPayloadEnumNames = [
        "SymbolTestsCore.Enums.MultiPayloadEnumTests",
        "SymbolTestsCore.Enums.MultiPayloadEnumTests2",
        "SymbolTestsCore.Enums.FunctionReferenceCaseTest",
        "SymbolTestsCore.ErrorTypes.AssociatedValueErrorTest",
        "SymbolTestsCore.CodableTests.CodableEnumTest",
    ]

    /// The builtin index now keys by the demangled qualified name (the raw
    /// symbolic-reference string is empty), and each embedded layout matches the
    /// runtime value-witness table size/stride.
    @MainActor
    @Test func builtinIndexResolvesMultiPayloadEnumsMatchingRuntime() async throws {
        let machO = machOImage
        let builtinIndex = try BuiltinTypeLayoutIndex(machO: machO)
        for typeName in Self.multiPayloadEnumNames {
            guard let layout = builtinIndex.layout(forTypeName: typeName) else {
                Issue.record("builtin index missing \(typeName)")
                continue
            }
            guard let runtime = try runtimeValueWitnessSizeStride(ofQualifiedTypeName: typeName, in: machO) else {
                Issue.record("no runtime value-witness table for \(typeName)")
                continue
            }
            #expect(layout.size == runtime.size, "\(typeName) builtin size \(layout.size) != runtime \(runtime.size)")
            #expect(layout.stride == runtime.stride, "\(typeName) builtin stride \(layout.stride) != runtime \(runtime.stride)")
        }
    }

    /// `__C.Decimal` — an imported C value type with no Swift type descriptor —
    /// resolves through the builtin index (it would otherwise be unreachable).
    @MainActor
    @Test func builtinIndexResolvesImportedCValueType() async throws {
        let builtinIndex = try BuiltinTypeLayoutIndex(machO: machOImage)
        let decimalLayout = builtinIndex.layout(forTypeName: "__C.Decimal")
        #expect(decimalLayout?.size == 20)
        #expect(decimalLayout?.stride == 20)
        #expect(decimalLayout?.alignmentMask == 3)
    }

    /// End-to-end: the resolver — which previously degraded multi-payload enums
    /// to `unknown` — now returns the builtin-backed layout, matching the runtime
    /// value-witness table.
    @MainActor
    @Test func resolverComputesMultiPayloadEnumViaBuiltin() async throws {
        let machO = machOImage
        let universe = try ImageUniverse.singleImage(machO)
        let resolver = StaticTypeLayoutResolver(imageUniverse: universe)
        let targetName = "SymbolTestsCore.Enums.MultiPayloadEnumTests"

        var resolved: TypeLayoutInfo?
        for contextDescriptor in try machO.swift.contextDescriptors {
            guard
                let node = try? MetadataReader.demangleContext(for: contextDescriptor, in: machO),
                NodeTypeNaming.nominalQualifiedName(of: node) == targetName
            else { continue }
            resolved = try resolver.layout(forTypeNode: node, in: universe.rootImage)
            break
        }

        let runtime = try runtimeValueWitnessSizeStride(ofQualifiedTypeName: targetName, in: machO)
        #expect(resolved != nil, "resolver did not resolve \(targetName)")
        #expect(runtime != nil, "no runtime value-witness table for \(targetName)")
        #expect(resolved?.size == runtime?.size, "resolver size \(String(describing: resolved?.size)) != runtime \(String(describing: runtime?.size))")
        #expect(resolved?.stride == runtime?.stride, "resolver stride \(String(describing: resolved?.stride)) != runtime \(String(describing: runtime?.stride))")
    }
}

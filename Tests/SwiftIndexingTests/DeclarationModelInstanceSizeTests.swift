import Foundation
import ObjectiveC
import Testing
import MachOSwiftSection
import SwiftDeclaration

/// Evolution proposal 0002 regression guard: the declaration model retains
/// descriptor references, not eagerly parsed wrappers, so its per-instance
/// footprint must stay in the descriptor-sized band. The pre-slimming sizes
/// (measured 2026-08-09 with this same probe, see
/// `Documentations/Internal/DeclarationModelMemoryFootprint.md`) were
/// `TypeDefinition` 1272 B, `ExtensionDefinition` 640 B,
/// `ProtocolDefinition` 440 B; the post-slimming sizes are 384 / 224 / 384 B,
/// and the ceilings leave room for a few added fields — a regression that re-embeds a wrapper
/// (`TypeContextWrapper` alone is 472 B inline) blows straight through
/// these ceilings.
@Suite struct DeclarationModelInstanceSizeTests {
    @Test func definitionInstancesStayDescriptorSized() {
        let typeDefinitionSize = class_getInstanceSize(TypeDefinition.self)
        let extensionDefinitionSize = class_getInstanceSize(ExtensionDefinition.self)
        let protocolDefinitionSize = class_getInstanceSize(ProtocolDefinition.self)
        print("Definition instance sizes — TypeDefinition: \(typeDefinitionSize) B, ExtensionDefinition: \(extensionDefinitionSize) B, ProtocolDefinition: \(protocolDefinitionSize) B")

        #expect(typeDefinitionSize <= 448, "TypeDefinition instance size: \(typeDefinitionSize) B")
        #expect(extensionDefinitionSize <= 320, "ExtensionDefinition instance size: \(extensionDefinitionSize) B")
        #expect(protocolDefinitionSize <= 416, "ProtocolDefinition instance size: \(protocolDefinitionSize) B")
    }

    /// The retained references themselves must stay descriptor-sized: they
    /// are raw layout + offset values, an order of magnitude below the
    /// parsed wrappers they replaced.
    @Test func retainedDescriptorReferencesStayCompact() {
        #expect(MemoryLayout<TypeContextDescriptorWrapper>.size <= 128, "TypeContextDescriptorWrapper: \(MemoryLayout<TypeContextDescriptorWrapper>.size) B")
        #expect(MemoryLayout<ProtocolConformanceDescriptor>.size <= 64, "ProtocolConformanceDescriptor: \(MemoryLayout<ProtocolConformanceDescriptor>.size) B")
        #expect(MemoryLayout<ProtocolDescriptor>.size <= 96, "ProtocolDescriptor: \(MemoryLayout<ProtocolDescriptor>.size) B")
    }
}

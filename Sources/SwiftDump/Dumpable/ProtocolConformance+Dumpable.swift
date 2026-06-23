import Foundation
import MachOKit
import MachOSwiftSection
import Semantic
import Demangling
import Utilities
import SwiftDeclarationRendering
import OrderedCollections

extension ProtocolConformance: ConformedDumpable {
    public func dumpTypeName<MachO: FieldLayoutRenderable>(using configuration: DumperConfiguration, in machO: MachO) async throws -> SemanticString {
        try await ProtocolConformanceDumper(self, using: configuration, in: machO).typeName
    }

    public func dumpProtocolName<MachO: FieldLayoutRenderable>(using configuration: DumperConfiguration, in machO: MachO) async throws -> SemanticString {
        try await ProtocolConformanceDumper(self, using: configuration, in: machO).protocolName
    }

    public func dump<MachO: FieldLayoutRenderable>(using configuration: DumperConfiguration, in machO: MachO) async throws -> SemanticString {
        try await ProtocolConformanceDumper(self, using: configuration, in: machO).body
    }
}

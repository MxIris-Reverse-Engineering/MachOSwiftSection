import Foundation
import MachOKit
import MachOSwiftSection
import MachOFoundation
import Semantic
import Demangling
import Utilities
import SwiftDeclarationRendering
import OrderedCollections

extension ProtocolConformance: ConformedDumpable {
    public func dumpTypeName(using configuration: DumperConfiguration, in machO: some MachOFieldLayoutRenderable) async throws -> SemanticString {
        try await ProtocolConformanceDumper(self, using: configuration, in: machO).typeName
    }

    public func dumpProtocolName(using configuration: DumperConfiguration, in machO: some MachOFieldLayoutRenderable) async throws -> SemanticString {
        try await ProtocolConformanceDumper(self, using: configuration, in: machO).protocolName
    }

    public func dump(using configuration: DumperConfiguration, in machO: some MachOFieldLayoutRenderable) async throws -> SemanticString {
        try await LargeStackTaskExecution.run {
            try await ProtocolConformanceDumper(self, using: configuration, in: machO).body
        }
    }
}

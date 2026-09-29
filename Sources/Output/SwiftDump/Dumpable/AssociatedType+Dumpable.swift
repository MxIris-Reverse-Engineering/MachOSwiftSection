import Foundation
import MachOKit
import MachOSwiftSection
import MachOFoundation
import Semantic
import Utilities
import SwiftDeclarationRendering

extension AssociatedType: ConformedDumpable {
    public func dumpTypeName(using configuration: DumperConfiguration, in machO: some MachOFieldLayoutRenderable) async throws -> SemanticString {
        try await AssociatedTypeDumper(self, using: configuration, in: machO).typeName
    }

    public func dumpProtocolName(using configuration: DumperConfiguration, in machO: some MachOFieldLayoutRenderable) async throws -> SemanticString {
        try await AssociatedTypeDumper(self, using: configuration, in: machO).protocolName
    }

    public func dump(using configuration: DumperConfiguration, in machO: some MachOFieldLayoutRenderable) async throws -> SemanticString {
        try await LargeStackTaskExecution.run {
            try await AssociatedTypeDumper(self, using: configuration, in: machO).body
        }
    }
}

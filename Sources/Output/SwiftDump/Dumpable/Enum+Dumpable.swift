import Foundation
import MachOKit
import MachOSwiftSection
import MachOFoundation
import Semantic
import Utilities
import SwiftDeclarationRendering

extension Enum: NamedDumpable {
    public func dumpName(using configuration: DumperConfiguration, in machO: some MachOFieldLayoutRenderable) async throws -> SemanticString {
        try await EnumDumper(self, using: configuration, in: machO).name
    }

    public func dump(using configuration: DumperConfiguration, in machO: some MachOFieldLayoutRenderable) async throws -> SemanticString {
        try await LargeStackTaskExecution.run {
            try await EnumDumper(self, using: configuration, in: machO).body
        }
    }
}
